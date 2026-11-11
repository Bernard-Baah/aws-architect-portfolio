output "sink_arn" {
  value = aws_oam_sink.audit.arn
}

output "dev_link_label" {
  description = "How dev appears in Audit's CloudWatch console"
  value       = aws_oam_link.dev.label
}
