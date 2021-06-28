provider "aws" {
  region = "us-east-1"
}

terraform {
  required_version = ">= 1.0.0"

  required_providers {
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.47"
    }
  }

  backend "s3" {
    bucket         = "mvana-account-terraform"
    region         = "us-east-1"
    dynamodb_table = "mvana-account-terraform"
    key            = "bmlt-metrics/terraform.tfstate"
  }
}

output "base_url" {
  value = aws_api_gateway_deployment.metrics.invoke_url
}
