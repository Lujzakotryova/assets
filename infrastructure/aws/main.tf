resource "aws_s3_bucket" "bucket" {
  bucket = var.manual-bucket-name
}

resource "aws_s3_bucket_acl" "bucket" {
  bucket = aws_s3_bucket.bucket.id
  acl    = "private"
}

resource "aws_s3_bucket_cors_configuration" "bucket" {
  bucket = aws_s3_bucket.bucket.id

  cors_rule {
    allowed_headers = [
    ]
    allowed_methods = [
      "GET",
      "HEAD"
    ]
    allowed_origins = [
      "*"
    ]
    expose_headers  = []
    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket" "automated_bucket" {
  bucket = var.automated-bucket-name
}

resource "aws_s3_bucket_acl" "automated_bucket" {
  bucket = aws_s3_bucket.automated_bucket.id
  acl    = "private"
}

resource "aws_s3_bucket_cors_configuration" "automated_bucket" {
  bucket = aws_s3_bucket.automated_bucket.id

  cors_rule {
    allowed_headers = [
    ]
    allowed_methods = [
      "GET",
      "HEAD"
    ]
    allowed_origins = [
      "*"
    ]
    expose_headers  = []
    max_age_seconds = 3000
  }
}

locals {
  origin_id                 = "S3-${aws_s3_bucket.bucket.id}"
  automated_origin_id       = "S3-${aws_s3_bucket.automated_bucket.id}"
  group_origin_id           = "S3-cesko-digital-all-assets"
  resize_function_origin_id = "cesko-digital-resized-assets"
}

resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
}

data "aws_iam_policy_document" "distribution_policy" {
  statement {
    actions = [
      "s3:GetObject"
    ]
    principals {
      type        = "AWS"
      identifiers = [
        aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn
      ]
    }
    resources = [
      "${aws_s3_bucket.bucket.arn}/*",
    ]
  }
}

data "aws_iam_policy_document" "automated_distribution_policy" {
  statement {
    actions = [
      "s3:GetObject"
    ]
    principals {
      type        = "AWS"
      identifiers = [
        aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn
      ]
    }
    resources = [
      "${aws_s3_bucket.automated_bucket.arn}/*",
    ]
  }
}

resource "aws_s3_bucket_policy" "web_distribution" {
  bucket = aws_s3_bucket.bucket.id
  policy = data.aws_iam_policy_document.distribution_policy.json
}

resource "aws_s3_bucket_policy" "web_distribution_automated" {
  bucket = aws_s3_bucket.automated_bucket.id
  policy = data.aws_iam_policy_document.automated_distribution_policy.json
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin_group {
    origin_id = local.group_origin_id

    failover_criteria {
      status_codes = [
        403,
        404,
        500,
        502
      ]
    }

    member {
      origin_id = local.origin_id
    }

    member {
      origin_id = local.automated_origin_id
    }
  }

  origin {
    origin_id   = local.resize_function_origin_id
    domain_name = "cesko.digital"
    origin_path = "/api"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "match-viewer"
      origin_ssl_protocols   = [
        "TLSv1",
        "TLSv1.1",
        "TLSv1.2",
        "SSLv3"
      ]
    }
  }

  origin {
    domain_name = aws_s3_bucket.bucket.bucket_regional_domain_name
    origin_id   = local.origin_id

    s3_origin_config {

      origin_access_identity = aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path
    }
  }

  origin {
    domain_name = aws_s3_bucket.automated_bucket.bucket_regional_domain_name
    origin_id   = local.automated_origin_id

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path
    }
  }

  enabled         = true
  is_ipv6_enabled = true

  aliases = [
    var.domain
  ]

  default_cache_behavior {
    allowed_methods = [
      "GET",
      "HEAD"
    ]
    cached_methods = [
      "GET",
      "HEAD"
    ]
    target_origin_id = local.group_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  # Cache behavior for resize function
  ordered_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    path_pattern     = "/resize"
    target_origin_id = local.resize_function_origin_id

    forwarded_values {
      query_string = true

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
  }

  price_class = "PriceClass_100"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn = var.ssl_certificate_arn
    ssl_support_method  = "sni-only"
  }

  custom_error_response {
    error_code            = 403
    error_caching_min_ttl = 10
    response_page_path    = "/index.html"
    response_code         = 404
  }
}