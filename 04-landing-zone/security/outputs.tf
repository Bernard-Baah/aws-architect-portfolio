output "trail_arn" {
  value = aws_cloudtrail.org.arn
}

output "trail_bucket" {
  description = "Bucket in Log Archive holding every account's CloudTrail logs"
  value       = aws_s3_bucket.trail.id
}

output "trail_kms_key_arn" {
  value = aws_kms_key.trail.arn
}

output "guardduty_detector_ids" {
  description = "Audit account (delegated admin) detector per region"
  value = {
    "us-east-1" = module.guardduty_use1.audit_detector_id
    "us-west-2" = module.guardduty_usw2.audit_detector_id
  }
}

output "config_bucket" {
  description = "Central AWS Config bucket in Log Archive"
  value       = aws_s3_bucket.config.id
}
