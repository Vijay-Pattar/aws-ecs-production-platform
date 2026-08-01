# ============================================================================
# APPLICATION LOAD BALANCER (ALB) — the public entry point.
# The internet hits the ALB; the ALB forwards to healthy Fargate tasks.
#
# For BLUE/GREEN we need TWO target groups:
#   - blue  : the currently-live version's tasks
#   - green : the new version's tasks during a deploy
# CodeDeploy shifts the ALB listener between these two to move traffic, and can
# swing it back to 'blue' to roll back. That's the whole trick.
# ============================================================================

resource "aws_lb" "app" {
  name               = "${var.project}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id
  tags               = { Name = "${var.project}-alb" }
}

# Health check config shared by both target groups: the ALB calls /health and a
# target is "healthy" only after it returns 200. Unhealthy targets get no traffic.
locals {
  tg_health = {
    path                = "/health"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_target_group" "blue" {
  name        = "${var.project}-blue"
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip" # Fargate tasks register by IP, not instance

  health_check {
    path                = local.tg_health.path
    matcher             = local.tg_health.matcher
    interval            = local.tg_health.interval
    timeout             = local.tg_health.timeout
    healthy_threshold   = local.tg_health.healthy_threshold
    unhealthy_threshold = local.tg_health.unhealthy_threshold
  }
  tags = { Name = "${var.project}-blue" }
}

resource "aws_lb_target_group" "green" {
  name        = "${var.project}-green"
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path                = local.tg_health.path
    matcher             = local.tg_health.matcher
    interval            = local.tg_health.interval
    timeout             = local.tg_health.timeout
    healthy_threshold   = local.tg_health.healthy_threshold
    unhealthy_threshold = local.tg_health.unhealthy_threshold
  }
  tags = { Name = "${var.project}-green" }
}

# The production listener on :80. It starts pointing at BLUE. CodeDeploy will
# flip it to GREEN during a deploy (and back to BLUE on rollback).
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }

  # CodeDeploy manages which target group this points at; ignore drift so
  # Terraform doesn't fight it after a deploy.
  lifecycle {
    ignore_changes = [default_action]
  }
}

output "alb_url" {
  description = "Public URL of the app"
  value       = "http://${aws_lb.app.dns_name}"
}
