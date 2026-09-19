output "alb_dns_name" {
  description = "DNS del ALB (backend + AI)"
  value       = aws_lb.this.dns_name
}

output "frontend_bucket" {
  description = "Bucket S3 del frontend estatico"
  value       = aws_s3_bucket.frontend.bucket
}

output "cloudfront_domain" {
  description = "Dominio de CloudFront del frontend"
  value       = aws_cloudfront_distribution.frontend.domain_name
}

output "ecr_backend" {
  value = aws_ecr_repository.backend.repository_url
}

output "ecr_ai" {
  value = aws_ecr_repository.ai.repository_url
}
