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
