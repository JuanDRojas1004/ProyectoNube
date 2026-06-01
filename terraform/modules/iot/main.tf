# Creación del Thing (Dispositivo Edge Gateway)
resource "aws_iot_thing" "edge_gateway" {
  name = "edge-gateway-01-${var.environment}"
}

# Creación de los certificados
resource "aws_iot_certificate" "cert" {
  active = true
}

# Creación de la política de IoT
resource "aws_iot_policy" "sensor_policy" {
  name = "EdgeGatewayPolicy-${var.environment}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["iot:Connect"]
        Effect   = "Allow"
        Resource = ["arn:aws:iot:${var.region}:${var.account_id}:client/${aws_iot_thing.edge_gateway.name}"]
      },
      {
        Action   = ["iot:Publish", "iot:Receive"]
        Effect   = "Allow"
        Resource = ["arn:aws:iot:${var.region}:${var.account_id}:topic/lab/sensors/*"]
      },
      {
        Action   = ["iot:Subscribe"]
        Effect   = "Allow"
        Resource = ["arn:aws:iot:${var.region}:${var.account_id}:topicfilter/lab/sensors/*"]
      }
    ]
  })
}

# Adjuntar política al certificado
resource "aws_iot_policy_attachment" "att" {
  policy = aws_iot_policy.sensor_policy.name
  target = aws_iot_certificate.cert.arn
}

# Adjuntar certificado al Thing
resource "aws_iot_thing_principal_attachment" "att" {
  principal = aws_iot_certificate.cert.arn
  thing     = aws_iot_thing.edge_gateway.name
}

# Escribir los certificados generados al disco local (Edge Gateway)
resource "local_file" "certificate_pem" {
  content  = aws_iot_certificate.cert.certificate_pem
  filename = "${path.root}/../edge_gateway/certs/certificate.pem.crt"
}

resource "local_file" "private_key" {
  content  = aws_iot_certificate.cert.private_key
  filename = "${path.root}/../edge_gateway/certs/private.pem.key"
}

resource "local_file" "public_key" {
  content  = aws_iot_certificate.cert.public_key
  filename = "${path.root}/../edge_gateway/certs/public.pem.key"
}

resource "local_file" "root_ca" {
  content  = var.root_ca_pem
  filename = "${path.root}/../edge_gateway/certs/AmazonRootCA1.pem"
}

# Generar mosquitto.conf automáticamente inyectando el endpoint de AWS
resource "local_file" "mosquitto_conf" {
  content  = <<-EOT
# Configuración del servidor local Mosquitto
listener 1883 0.0.0.0
allow_anonymous true

# Configuración del Bridge hacia AWS IoT Core
connection awsiot
address ${var.iot_endpoint}:8883

# Mapeo de tópicos: local -> remoto
topic lab/sensors/data out 1 "" ""

bridge_protocol_version mqttv311
bridge_insecure false

cleansession true
clientid ${aws_iot_thing.edge_gateway.name}
start_type automatic
notifications false
keepalive_interval 60

# Certificados TLS para la conexión con AWS
bridge_cafile /mosquitto/certs/AmazonRootCA1.pem
bridge_certfile /mosquitto/certs/certificate.pem.crt
bridge_keyfile /mosquitto/certs/private.pem.key
EOT
  filename = "${path.root}/../edge_gateway/mosquitto.conf"
}

# === REGLAS IOT ===

# Regla de DynamoDB
resource "aws_iot_topic_rule" "dynamodb_rule" {
  name        = "SensorDataToDynamoDB_${var.environment}"
  description = "Guarda los eventos de sensores en DynamoDB"
  enabled     = true
  sql         = "SELECT * FROM 'lab/sensors/data'"
  sql_version = "2016-03-23"

  dynamodbv2 {
    role_arn = var.lab_role_arn
    put_item {
      table_name = var.sensor_table_name
    }
  }
}

# Regla de S3
resource "aws_iot_topic_rule" "s3_rule" {
  name        = "SensorDataToS3_${var.environment}"
  description = "Guarda los eventos de sensores en S3 particionados por fecha"
  enabled     = true
  sql         = "SELECT * FROM 'lab/sensors/data'"
  sql_version = "2016-03-23"

  s3 {
    bucket_name = var.sensor_bucket_name
    key         = "data/year=$${parse_time(\"yyyy\", timestamp())}/month=$${parse_time(\"MM\", timestamp())}/day=$${parse_time(\"dd\", timestamp())}/$${topic(3)}_$${newuuid()}.json"
    role_arn    = var.lab_role_arn
  }
}

# === LAMBDA HISTÓRICO: S3 -> MONGODB ===

data "archive_file" "lambda_history_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_history_build"
  output_path = "${path.module}/lambda_history.zip"
}

resource "aws_lambda_function" "lambda_history" {
  function_name    = "S3ToMongoHistory-${var.environment}"
  role             = var.lab_role_arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda_history_zip.output_path
  source_code_hash = data.archive_file.lambda_history_zip.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      MONGODB_URI = var.mongodb_uri
    }
  }
}

resource "aws_lambda_permission" "allow_s3_history" {
  statement_id  = "AllowExecutionFromS3History"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_history.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = "arn:aws:s3:::${var.sensor_bucket_name}"
}

resource "aws_s3_bucket_notification" "sensor_bucket_notification" {
  bucket = var.sensor_bucket_name

  lambda_function {
    lambda_function_arn = aws_lambda_function.lambda_history.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [
    aws_lambda_permission.allow_s3_history
  ]
}

# === SISTEMA DE ALERTAS: IOT -> LAMBDA -> SQS -> LAMBDA -> CLOUDWATCH ===

# Cola SQS donde se almacenan temporalmente las alertas de temperatura crítica
resource "aws_sqs_queue" "alerts_queue" {
  name = "iot-alerts-${var.environment}"
}

# Empaquetado de la Lambda de alerta
data "archive_file" "lambda_alert_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_alert"
  output_path = "${path.module}/lambda_alert.zip"
}

# Lambda que recibe el evento desde IoT Core y envía el mensaje a SQS
resource "aws_lambda_function" "lambda_alert" {
  function_name    = "IoTAlertToSQS-${var.environment}"
  role             = var.lab_role_arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda_alert_zip.output_path
  source_code_hash = data.archive_file.lambda_alert_zip.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      ALERT_QUEUE_URL = aws_sqs_queue.alerts_queue.url
    }
  }
}

# Regla IoT que detecta temperaturas superiores al umbral definido
resource "aws_iot_topic_rule" "high_temperature_rule" {
  name        = "HighTemperatureAlert_${var.environment}"
  description = "Dispara alerta cuando la temperatura supera el umbral"
  enabled     = true
  sql         = "SELECT * FROM 'lab/sensors/data' WHERE sensor_type = 'temperature' AND value > 35"
  sql_version = "2016-03-23"

  lambda {
    function_arn = aws_lambda_function.lambda_alert.arn
  }
}

# Permiso para que AWS IoT Core pueda invocar la Lambda de alerta
resource "aws_lambda_permission" "allow_iot_alert" {
  statement_id  = "AllowExecutionFromIoTAlert"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_alert.function_name
  principal     = "iot.amazonaws.com"
  source_arn    = aws_iot_topic_rule.high_temperature_rule.arn
}

# Empaquetado de la Lambda que consume mensajes desde SQS
data "archive_file" "lambda_cloudwatch_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_cloudwatch"
  output_path = "${path.module}/lambda_cloudwatch.zip"
}

# Lambda que consume alertas desde SQS y las escribe en CloudWatch Logs
resource "aws_lambda_function" "lambda_cloudwatch" {
  function_name    = "SQSAlertToCloudWatch-${var.environment}"
  role             = var.lab_role_arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda_cloudwatch_zip.output_path
  source_code_hash = data.archive_file.lambda_cloudwatch_zip.output_base64sha256
  timeout          = 30
}

# Trigger que conecta la cola SQS con la Lambda CloudWatch
resource "aws_lambda_event_source_mapping" "sqs_to_cloudwatch" {
  event_source_arn = aws_sqs_queue.alerts_queue.arn
  function_name    = aws_lambda_function.lambda_cloudwatch.arn
  batch_size       = 10
}