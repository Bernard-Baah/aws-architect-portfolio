# Edge layer: CloudFront in front of an internal ALB, protected by AWS WAF.
#
#   viewer --HTTPS--> CloudFront (+ WAF) --VPC origin, AWS network--> internal ALB
#
# The ALB has no public IP. CloudFront reaches it through a VPC origin, an ENI
# that CloudFront manages inside the VPC. TLS terminates at CloudFront using its
# default *.cloudfront.net certificate, so no domain is needed.

locals {
  failover = var.secondary_alb_arn != null
}

# ---------------------------------------------------------------- AWS-managed policies

data "aws_cloudfront_cache_policy" "disabled" {
  name = "Managed-CachingDisabled" # dynamic app: every request goes to the origin
}

data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

data "aws_cloudfront_response_headers_policy" "security_headers" {
  name = "Managed-SecurityHeadersPolicy" # HSTS, X-Content-Type-Options, X-Frame-Options, ...
}

# ---------------------------------------------------------------- VPC origin

resource "aws_cloudfront_vpc_origin" "alb" {
  vpc_origin_endpoint_config {
    name                   = "${var.name}-alb"
    arn                    = var.alb_arn
    http_port              = 80
    https_port             = 443
    origin_protocol_policy = "http-only" # traffic stays on the AWS network, inside the VPC

    origin_ssl_protocols {
      items    = ["TLSv1.2"]
      quantity = 1
    }
  }

  # Provisioning the VPC origin's ENIs typically takes 10-15 minutes.
  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }

  tags = var.tags
}

# Standby ALB in another region (Project 03). A VPC origin can point at an ALB
# in any supported region; CloudFront reaches it over the AWS network.
resource "aws_cloudfront_vpc_origin" "secondary" {
  count = local.failover ? 1 : 0

  vpc_origin_endpoint_config {
    name                   = "${var.name}-alb-secondary"
    arn                    = var.secondary_alb_arn
    http_port              = 80
    https_port             = 443
    origin_protocol_policy = "http-only"

    origin_ssl_protocols {
      items    = ["TLSv1.2"]
      quantity = 1
    }
  }

  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }

  tags = var.tags
}

# ---------------------------------------------------------------- Distribution

resource "aws_cloudfront_distribution" "app" {
  enabled         = true
  comment         = "${var.name}: HTTPS front door for the internal ALB"
  is_ipv6_enabled = true
  http_version    = "http2and3"
  price_class     = var.price_class
  web_acl_id      = aws_wafv2_web_acl.edge.arn

  origin {
    origin_id   = "alb"
    domain_name = var.alb_dns_name

    # With a standby origin, give up on the primary fast (1 attempt, 2 s) so
    # failover adds seconds, not the default 3 x 10 s, to each request.
    connection_attempts = local.failover ? 1 : 3
    connection_timeout  = local.failover ? 2 : 10

    vpc_origin_config {
      vpc_origin_id            = aws_cloudfront_vpc_origin.alb.id
      origin_keepalive_timeout = 5
      origin_read_timeout      = 30
    }
  }

  dynamic "origin" {
    for_each = local.failover ? [1] : []

    content {
      origin_id   = "alb-secondary"
      domain_name = var.secondary_alb_dns_name

      vpc_origin_config {
        vpc_origin_id            = aws_cloudfront_vpc_origin.secondary[0].id
        origin_keepalive_timeout = 5
        origin_read_timeout      = 30
      }
    }
  }

  # Per-request failover: if the primary answers 5xx or can't be reached,
  # CloudFront retries the same request on the standby. No DNS TTL to wait out.
  dynamic "origin_group" {
    for_each = local.failover ? [1] : []

    content {
      origin_id = "alb-failover"

      failover_criteria {
        status_codes = [500, 502, 503, 504]
      }

      member {
        origin_id = "alb"
      }

      member {
        origin_id = "alb-secondary"
      }
    }
  }

  # Origin groups only fail over GET/HEAD/OPTIONS, and CloudFront requires a
  # behavior that targets a group to allow only those methods.
  default_cache_behavior {
    target_origin_id           = local.failover ? "alb-failover" : "alb"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = local.failover ? ["GET", "HEAD", "OPTIONS"] : ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = data.aws_cloudfront_cache_policy.disabled.id
    origin_request_policy_id   = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security_headers.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = var.tags
}

# ---------------------------------------------------------------- WAF

resource "aws_wafv2_web_acl" "edge" {
  provider = aws.us_east_1

  name        = "${var.name}-edge"
  description = "AWS managed protections + per-IP rate limit for ${var.name}"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  # Per-IP flood protection. Evaluated first so floods never reach the managed rules.
  rule {
    name     = "rate-limit-per-ip"
    priority = 0

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.rate_limit_per_5min
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  # Known-malicious IPs (botnets, scanners) from Amazon threat intelligence
  rule {
    name     = "aws-ip-reputation"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesAmazonIpReputationList"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-ip-reputation"
      sampled_requests_enabled   = true
    }
  }

  # OWASP-style baseline: XSS, path traversal, oversized requests, etc.
  rule {
    name     = "aws-common"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-common"
      sampled_requests_enabled   = true
    }
  }

  # Request patterns tied to known exploits (e.g. Log4Shell)
  rule {
    name     = "aws-known-bad-inputs"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name}-edge"
    sampled_requests_enabled   = true
  }

  tags = var.tags
}
