output "cloudfront_domain" {
  description = "The domain name of the CloudFront distribution"
  value       = aws_cloudfront_distribution.cf-dist.domain_name
}
