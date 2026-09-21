terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }

  # Para produccion, usa un backend remoto con locking:
  # backend "s3" {
  #   bucket = "mi-tfstate"
  #   key    = "intersectia/ec2.tfstate"
  #   region = "us-east-1"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "intersectia"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
