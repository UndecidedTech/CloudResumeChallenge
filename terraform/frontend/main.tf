
resource "aws_s3_bucket" "site" {
  bucket = var.site_domain
}

resource "aws_s3_bucket_website_configuration" "site" {
  bucket = aws_s3_bucket.site.id

  index_document {
    suffix = "index.html"
  }
}

locals {
  # Map of file extensions to MIME types
  mime_types = {
    "html" = "text/html"
    "css"  = "text/css"
    "js"   = "application/javascript"
    "png"  = "image/png"
    "jpg"  = "image/jpeg"
    "jpeg" = "image/jpeg"
    "gif"  = "image/gif"
    "ico"  = "image/x-icon"
  }
}

resource "aws_s3_object" "provision_source_files" {
  bucket = aws_s3_bucket.site.id

  for_each = fileset("${var.source_files}/", "**/*.*")

  key          = each.value
  source       = "${var.source_files}/${each.value}"
  content_type = lookup(local.mime_types, element(split(".", basename(each.value)), length(split(".", basename(each.value))) - 1), "application/octet-stream") # Default to binary stream if not found
  etag         = filemd5("${var.source_files}/${each.value}")
}

resource "aws_cloudfront_origin_access_control" "cf-s3-oac" {
  name                              = "CloudFront S3 OAC"
  description                       = "CloudFront S3 OAC"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

data "aws_acm_certificate" "cert" {
  provider    = aws.us-east-1
  domain      = var.custom_domain_name
  statuses    = ["ISSUED"]
  most_recent = true
}

resource "aws_cloudfront_distribution" "cf-dist" {
  enabled             = true
  default_root_object = "index.html"
  aliases             = [var.custom_domain_name]

  origin {
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id                = aws_s3_bucket.site.id
    origin_access_control_id = aws_cloudfront_origin_access_control.cf-s3-oac.id
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_s3_bucket.site.id
    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  price_class = "PriceClass_All"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn = data.aws_acm_certificate.cert.arn
    ssl_support_method  = "sni-only"
  }

  tags = merge(var.common_tags, {
    Name = "${var.naming_prefix}-cloudfront"
  })
}

data "aws_iam_policy_document" "s3_bucket_policy" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.cf-dist.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "static_site_bucket_policy" {
  bucket = aws_s3_bucket.site.id
  policy = data.aws_iam_policy_document.s3_bucket_policy.json
}

resource "null_resource" "cloudfront_invalidation" {
  # This resource will trigger an invalidation when the S3 objects change
  triggers = {
    # Use a hash of the S3 objects to trigger this resource only when content changes
    s3_object_hash = join("", [for obj in aws_s3_object.provision_source_files : obj.etag])
  }

  # Ensure this runs after the CloudFront distribution is created/updated
  depends_on = [
    aws_cloudfront_distribution.cf-dist,
    aws_s3_object.provision_source_files,
  ]

  provisioner "local-exec" {
    command = "aws cloudfront create-invalidation --distribution-id ${aws_cloudfront_distribution.cf-dist.id} --paths '/*'"
    # Only run this provisioner when the resource is created or updated
    when = create
  }
}

