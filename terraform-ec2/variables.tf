variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "environment" {
  type    = string
  default = "production"
}

variable "project" {
  type    = string
  default = "intersectia"
}

variable "instance_type" {
  description = "t3.small (2 GB, recomendado para compilar) o t2.micro (free tier, con swap)."
  type        = string
  default     = "t3.small"
}

variable "git_branch" {
  description = "Rama de los repos a clonar en la instancia."
  type        = string
  default     = "v2"
}

variable "database_name" {
  type    = string
  default = "intersectia"
}

variable "database_user" {
  type    = string
  default = "intersectia"
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "allowed_cors_origin" {
  description = "Origen permitido para CORS. Ajustar al dominio de CloudFront tras el primer apply."
  type        = string
  default     = "*"
}

variable "bedrock_model_id" {
  type    = string
  default = "us.meta.llama3-1-8b-instruct-v1:0"
}
