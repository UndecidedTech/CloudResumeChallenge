variable "aws_region" {
  type        = string
  description = "The AWS region to put the bucket into"
  default     = "us-east-2"
}

variable "site_domain" {
  type        = string
  description = "The domain to use for the static site"
}

variable "source_files" {
  type        = string
  description = "The directory that contains the frontend files to be uploaded"
}

variable "common_tags" {
  type        = map(any)
  description = "Common tags to be applied to the resources"
}

variable "naming_prefix" {
  type        = string
  description = "Prefix to be added to the resource names"
}

variable "custom_domain_name" {
  type        = string
  description = "The custom domain name for the CloudFront distribution"
}