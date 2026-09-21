output "cloudfront_url" {
  description = "URL HTTPS publica (usar esta)"
  value       = "https://${aws_cloudfront_distribution.this.domain_name}"
}

output "ec2_public_ip" {
  value = aws_eip.this.public_ip
}

output "ec2_instance_id" {
  description = "Para actualizar con deploy/ec2-update.sh <id>"
  value       = aws_instance.this.id
}

output "rds_endpoint" {
  value = aws_db_instance.this.address
}
