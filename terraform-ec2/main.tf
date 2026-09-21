# Opcion A+ con Terraform: EC2 (Docker Compose: frontend nginx + backend + IA) + RDS
# + CloudFront (HTTPS) + Secrets Manager + IAM con Bedrock. Misma arquitectura que el
# template de CloudFormation, en HCL. Usa la VPC por defecto (apto demo/taller).

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_vpc" "default" {
  default = true
}
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  name = "${var.project}-${var.environment}"
}

resource "random_password" "db" {
  length  = 24
  special = false
}

resource "random_password" "internal_token" {
  length  = 40
  special = false
}

# --- Secretos --------------------------------------------------------------

resource "aws_secretsmanager_secret" "db" {
  name                    = "${local.name}/intersectia/database"
  description             = "Credenciales de RDS PostgreSQL para IntersectIA"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = var.database_user
    password = random_password.db.result
  })
}

resource "aws_secretsmanager_secret" "token" {
  name                    = "${local.name}/intersectia/internal-token"
  description             = "Token interno backend <-> IA"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "token" {
  secret_id     = aws_secretsmanager_secret.token.id
  secret_string = jsonencode({ token = random_password.internal_token.result })
}

# --- Base de datos (RDS) ---------------------------------------------------

resource "aws_db_subnet_group" "this" {
  name       = "${local.name}-db"
  subnet_ids = data.aws_subnets.default.ids
}

resource "aws_security_group" "rds" {
  name_prefix = "${local.name}-rds-"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }
}

resource "aws_db_instance" "this" {
  identifier             = "${local.name}-db"
  engine                 = "postgres"
  engine_version         = "16"
  instance_class         = var.db_instance_class
  allocated_storage      = 20
  storage_type           = "gp3"
  db_name                = var.database_name
  username               = var.database_user
  password               = random_password.db.result
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  skip_final_snapshot    = true
  deletion_protection    = false
  storage_encrypted      = true
}

# --- IAM (Secrets + Logs + SSM + Bedrock) ----------------------------------

resource "aws_iam_role" "ec2" {
  name = "${local.name}-ec2"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_logs" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "ec2_secrets" {
  name = "${local.name}-ec2-secrets"
  role = aws_iam_role.ec2.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = [aws_secretsmanager_secret.db.arn, aws_secretsmanager_secret.token.arn]
    }]
  })
}

resource "aws_iam_role_policy" "ec2_bedrock" {
  name = "${local.name}-ec2-bedrock"
  role = aws_iam_role.ec2.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
      Resource = [
        "arn:aws:bedrock:${var.aws_region}:${data.aws_caller_identity.current.account_id}:inference-profile/${var.bedrock_model_id}",
        "arn:aws:bedrock:*::foundation-model/meta.llama3-1-8b-instruct-v1:0",
      ]
    }]
  })
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${local.name}-ec2"
  role = aws_iam_role.ec2.name
}

# --- EC2 -------------------------------------------------------------------

resource "aws_security_group" "ec2" {
  name_prefix = "${local.name}-ec2-"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP (CloudFront origin)"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "this" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  iam_instance_profile   = aws_iam_instance_profile.ec2.name
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.ec2.id]
  # Hop limit 2: el contenedor de la IA debe alcanzar IMDS para las credenciales
  # del instance role (necesario para invocar Bedrock).
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "optional"
    http_put_response_hop_limit = 2
  }
  user_data_replace_on_change = true
  user_data = templatefile("${path.module}/user-data.sh.tpl", {
    region            = var.aws_region
    branch            = var.git_branch
    db_address        = aws_db_instance.this.address
    db_name           = var.database_name
    db_user           = var.database_user
    db_secret_name    = aws_secretsmanager_secret.db.name
    token_secret_name = aws_secretsmanager_secret.token.name
    cors_origin       = var.allowed_cors_origin
    bedrock_model_id  = var.bedrock_model_id
  })

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = { Name = "${local.name}-intersectia" }
}

resource "aws_eip" "this" {
  domain = "vpc"
  tags   = { Name = "${local.name}-intersectia-eip" }
}

resource "aws_eip_association" "this" {
  instance_id   = aws_instance.this.id
  allocation_id = aws_eip.this.id
}

# --- CloudFront (HTTPS sin dominio) ----------------------------------------

resource "aws_cloudfront_distribution" "this" {
  enabled     = true
  price_class = "PriceClass_100"
  comment     = "${local.name} IntersectIA"

  origin {
    domain_name = aws_eip.this.public_dns
    origin_id   = "ec2"
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
      origin_read_timeout    = 60
    }
  }

  default_cache_behavior {
    target_origin_id       = "ec2"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    forwarded_values {
      query_string = true
      headers      = ["*"]
      cookies {
        forward = "all"
      }
    }
    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
    compress    = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
