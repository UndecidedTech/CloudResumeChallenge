terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.4.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "3.2.1"
    }
  }

  required_version = ">= 1.0.0"

  backend "s3" {
    bucket = "branresumechallenge"
    key    = "frontend.tfstate"
    region = "us-east-2"
  }
}

provider "aws" {
  region = var.aws_region
}

provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"
}
