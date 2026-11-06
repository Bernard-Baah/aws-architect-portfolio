output "url" {
  description = "Public HTTPS URL of the app"
  value       = "https://${aws_cloudfront_distribution.app.domain_name}"
}

output "distribution_id" {
  value = aws_cloudfront_distribution.app.id
}

output "web_acl_name" {
  value = aws_wafv2_web_acl.edge.name
}

output "vpc_origin_id" {
  value = aws_cloudfront_vpc_origin.alb.id
}
