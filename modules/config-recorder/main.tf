# One AWS Config recorder + delivery channel in one account and region.
# Used for the management account, which StackSets can't deploy to.

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

variable "role_arn" {
  description = "IAM role Config assumes to record and deliver"
  type        = string
}

variable "delivery_bucket" {
  description = "Central Config bucket (in Log Archive)"
  type        = string
}

variable "include_global" {
  description = "Record global resources (IAM). True in exactly one region so they aren't counted twice."
  type        = bool
}

resource "aws_config_configuration_recorder" "this" {
  name     = "default"
  role_arn = var.role_arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = var.include_global
  }

  # Daily snapshots: a fraction of continuous recording's cost.
  recording_mode {
    recording_frequency = "DAILY"
  }
}

resource "aws_config_delivery_channel" "this" {
  name           = "default"
  s3_bucket_name = var.delivery_bucket

  snapshot_delivery_properties {
    delivery_frequency = "TwentyFour_Hours"
  }

  depends_on = [aws_config_configuration_recorder.this]
}

resource "aws_config_configuration_recorder_status" "this" {
  name       = aws_config_configuration_recorder.this.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.this]
}
