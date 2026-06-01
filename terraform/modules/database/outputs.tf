output "sensor_table_name" {
  value       = aws_dynamodb_table.sensor_data.name
  description = "Nombre de la tabla DynamoDB para los datos del sensor"
}

output "mongodb_private_ip" {
  value       = aws_instance.mongodb.private_ip
  description = "IP privada de la instancia MongoDB"
}

output "mongodb_public_ip" {
  value       = aws_instance.mongodb.public_ip
  description = "IP publica de la instancia MongoDB"
}

output "mongodb_uri" {
  value = "mongodb://${aws_instance.mongodb.public_ip}:27017/iot_history"
}