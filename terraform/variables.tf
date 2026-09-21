variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "environment" {
  type    = string
  default = "demo"
}

variable "project" {
  type    = string
  default = "intersectia"
}

variable "backend_image" {
  description = "URI de la imagen del backend en ECR (con tag). Requerido al crear el servicio (deploy_services=true)."
  type        = string
  default     = ""
}

variable "ai_image" {
  description = "URI de la imagen del AI en ECR (con tag). Requerido al crear el servicio (deploy_services=true)."
  type        = string
  default     = ""
}

variable "deploy_services" {
  description = "Crear el task definition y el servicio ECS (2a fase, despues de subir las imagenes a ECR)."
  type        = bool
  default     = false
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "db_name" {
  type    = string
  default = "intersectia"
}

variable "db_username" {
  type    = string
  default = "intersectia"
}

variable "container_cpu" {
  type    = number
  default = 512
}

variable "container_memory" {
  type    = number
  default = 1024
}

variable "desired_count" {
  type    = number
  default = 1
}
