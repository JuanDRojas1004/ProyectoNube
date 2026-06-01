resource "aws_dynamodb_table" "sensor_data" {
  name         = "SensorData-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"

  # Ahora guardamos múltiples eventos por sensor:
  # PK = device_id
  # SK = timestamp
  hash_key  = "device_id"
  range_key = "timestamp"

  attribute {
    name = "device_id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_security_group" "mongodb_sg" {
  name        = "mongodb-sg-${var.environment}"
  description = "Security group para MongoDB"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "MongoDB"
    from_port   = 27017
    to_port     = 27017
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Salida total"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "MongoDB-SG-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_instance" "mongodb" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = var.key_name
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.mongodb_sg.id]
  iam_instance_profile   = "LabInstanceProfile"
  user_data              = file("${path.module}/scripts/install_mongodb.sh")

  tags = {
    Name        = "MongoDB-${var.environment}"
    Role        = "NoSQLDatabase"
    Environment = var.environment
    Project     = var.project_name
  }
}