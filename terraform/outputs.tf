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

output "cloudfront_url" {
  description = "URL HTTPS publica (usar esta para abrir la app)"
  value       = "https://${aws_cloudfront_distribution.frontend.domain_name}"
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "ecs_security_group_id" {
  value = aws_security_group.ecs.id
}

output "default_subnet_ids" {
  value = data.aws_subnets.default.ids
}

output "backend_task_family" {
  value = local.name
}

output "ecr_backend" {
  value = aws_ecr_repository.backend.repository_url
}

output "ecr_ai" {
  value = aws_ecr_repository.ai.repository_url
}
