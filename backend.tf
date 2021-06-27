provider "aws" {
  region = "us-east-1"
}

terraform {
  required_version = ">= 1.0.0"

  required_providers {
    archive = {
      source = "hashicorp/archive"
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
