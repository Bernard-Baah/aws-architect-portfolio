# App tier: launch template + Auto Scaling group across the private app subnets.
#
# - No SSH and no key pair: shell access is through SSM Session Manager.
# - IMDSv2 only, so the instance credentials can't be stolen through SSRF-style metadata calls.
# - The instance role can read exactly one secret (the DB credentials).

data "aws_region" "current" {}

# Latest Amazon Linux 2023 for Graviton, published by AWS as a public SSM parameter
data "aws_ssm_parameter" "al2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

# ---------------------------------------------------------------- IAM

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app" {
  name               = "${var.name}-app-instance"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "read_db_secret" {
  statement {
    sid       = "ReadDbSecretOnly"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.db_secret_arn]
  }
}

resource "aws_iam_role_policy" "read_db_secret" {
  name   = "read-db-secret"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.read_db_secret.json
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.name}-app-instance"
  role = aws_iam_role.app.name

  tags = var.tags
}

# ---------------------------------------------------------------- Launch template

resource "aws_launch_template" "app" {
  name_prefix            = "${var.name}-app-"
  description            = "ha-web-app instances (AL2023 arm64)"
  image_id               = data.aws_ssm_parameter.al2023_arm64.insecure_value
  instance_type          = var.instance_type
  vpc_security_group_ids = var.security_group_ids
  update_default_version = true

  iam_instance_profile {
    arn = aws_iam_instance_profile.app.arn
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 10
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh.tftpl", {
    app_py        = file("${path.module}/app/app.py")
    app_port      = var.app_port
    region        = data.aws_region.current.name
    db_host       = var.db_host
    db_name       = var.db_name
    db_secret_arn = var.db_secret_arn
  }))

  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.tags, { Name = "${var.name}-app" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(var.tags, { Name = "${var.name}-app" })
  }

  tags = var.tags
}

# ---------------------------------------------------------------- Auto Scaling group

resource "aws_autoscaling_group" "app" {
  name                = "${var.name}-app"
  vpc_zone_identifier = var.subnet_ids
  min_size            = var.min_size
  max_size            = var.max_size
  # desired_capacity left unset: it starts at min_size, then target tracking owns it.
  # Setting it here would make every terraform apply undo a scale-out.

  health_check_type         = var.health_check_type
  health_check_grace_period = 300
  target_group_arns         = var.target_group_arns

  launch_template {
    id      = aws_launch_template.app.id
    version = aws_launch_template.app.latest_version
  }

  # A new launch template version (new AMI, app change) replaces instances
  # gradually, keeping at least half of capacity serving.
  instance_refresh {
    strategy = "Rolling"

    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 180
    }
  }

  enabled_metrics = [
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupMinSize",
    "GroupMaxSize",
    "GroupTotalInstances",
  ]

  tag {
    key                 = "Name"
    value               = "${var.name}-app"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = var.tags

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}

resource "aws_autoscaling_policy" "cpu" {
  name                   = "${var.name}-cpu-target"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = var.cpu_target_percent
  }
}
