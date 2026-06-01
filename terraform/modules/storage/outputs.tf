output "sensor_bucket_name" {
  value       = aws_s3_bucket.sensor_data.bucket
  description = "Nombre del bucket de S3 para sensores"
}

output "athena_results_bucket_name" {
  value       = aws_s3_bucket.athena_results.bucket
  description = "Nombre del bucket de S3 para Athena"
}
