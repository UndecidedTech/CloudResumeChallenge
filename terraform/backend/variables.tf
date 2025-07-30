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