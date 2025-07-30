variable "site_domain" {
  description = "The domain name of the site"
  type        = string
}

variable "source_files" {
  description = "The path to the source files for the site"
  type        = string
}

variable "custom_domain_name" {
  description = "The custom domain name for the site"
  type        = string
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
}

variable "naming_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "aws_region" {
  description = "The AWS region to deploy resources into"
  type        = string
}