# Layer 5c: CloudWatch cross-account observability (Observability Access
# Manager). Audit owns a sink; each source account creates a link to it.
# Audit's CloudWatch console then shows the source accounts' metrics, log
# groups and X-Ray traces next to its own, without copying any data and
# without anyone signing into the workload account to investigate.
#
# The sink policy only accepts links from this organization and only for the
# three telemetry types below. Sharing is read-only: Audit can see, not change.

locals {
  telemetry = [
    "AWS::CloudWatch::Metric",
    "AWS::Logs::LogGroup",
    "AWS::XRay::Trace",
  ]
}

resource "aws_oam_sink" "audit" {
  provider = aws.audit

  name = "org-monitoring"
}

resource "aws_oam_sink_policy" "audit" {
  provider = aws.audit

  sink_identifier = aws_oam_sink.audit.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = ["oam:CreateLink", "oam:UpdateLink"]
      Resource  = "*"
      Condition = {
        StringEquals                = { "aws:PrincipalOrgID" = local.org.organization_id }
        "ForAllValues:StringEquals" = { "oam:ResourceTypes" = local.telemetry }
      }
    }]
  })
}

# One link per source account. Providers can't be chosen with for_each, so a
# new source account means one more provider + link pair (dev only for now).
resource "aws_oam_link" "dev" {
  provider = aws.dev

  sink_identifier = aws_oam_sink.audit.arn
  label_template  = "$AccountName"
  resource_types  = local.telemetry

  depends_on = [aws_oam_sink_policy.audit]
}
