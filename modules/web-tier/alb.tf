# Application Load Balancer in the public subnets, forwarding to the ASG.
#
# HTTP only for now: HTTPS needs a certificate for a domain. Layer 5 puts
# CloudFront (with its own TLS certificate) in front and locks the ALB down
# to CloudFront traffic only.

resource "aws_lb" "app" {
  name               = "${var.name}-alb"
  load_balancer_type = "application"
  internal           = false
  subnets            = var.public_subnet_ids
  security_groups    = var.alb_security_group_ids

  drop_invalid_header_fields = true
  enable_deletion_protection = false # lab: terraform destroy must work
  idle_timeout               = 60

  tags = merge(var.tags, { Name = "${var.name}-alb" })
}

resource "aws_lb_target_group" "app" {
  name                 = "${var.name}-app"
  vpc_id               = var.vpc_id
  port                 = var.app_port
  protocol             = "HTTP"
  target_type          = "instance"
  deregistration_delay = 30 # default 300s makes scale-in and refreshes slow

  # /health has no DB dependency (see app.py), so a database failover doesn't
  # take every target out of service.
  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = var.tags
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  tags = var.tags
}
