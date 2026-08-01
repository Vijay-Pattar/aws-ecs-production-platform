# ============================================================================
# ECS FARGATE — the runtime.
#   Cluster      : a logical grouping for services.
#   Task def     : the "recipe" for a container (image, CPU/mem, env, ports, logs).
#   Service      : keeps N copies (tasks) of the task def running behind the ALB,
#                  replaces unhealthy ones, and (here) uses the CODE_DEPLOY
#                  controller so CodeDeploy drives blue/green deployments.
# ============================================================================

resource "aws_ecs_cluster" "main" {
  name = "${var.project}-cluster"

  # Container Insights = richer CloudWatch metrics (CPU/mem/task counts).
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# Where container stdout/stderr goes. 7-day retention keeps cost ~nil.
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.project}"
  retention_in_days = 7
}

# The task definition. image is provided via a variable so CI can pass the exact
# ECR image tag; for the first `apply` it defaults to the :v1 we already pushed.
variable "image_tag" {
  description = "ECR image tag to run"
  type        = string
  default     = "v1"
}

data "aws_caller_identity" "current" {}

locals {
  ecr_image = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.project}-app:${var.image_tag}"
}

resource "aws_ecs_task_definition" "app" {
  family                   = "${var.project}-app"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc" # each task gets its own ENI/IP
  cpu                      = "256"    # 0.25 vCPU — smallest, cheapest
  memory                   = "512"    # 0.5 GB
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([{
    name         = "app"
    image        = local.ecr_image
    essential    = true
    portMappings = [{ containerPort = var.app_port, protocol = "tcp" }]
    environment = [
      { name = "APP_VERSION", value = var.image_tag },
      { name = "AWS_REGION", value = var.region },
      { name = "VISITS_TABLE", value = aws_dynamodb_table.visits.name },
      { name = "SECRET_NAME", value = aws_secretsmanager_secret.app.name },
      # reliability knobs — CI overrides these to run a healthy vs broken version
      { name = "ERROR_RATE", value = "0.0" },
      { name = "EXTRA_LATENCY_MS", value = "0" },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.app.name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "app"
      }
    }
  }])
}

resource "aws_ecs_service" "app" {
  name            = "${var.project}-svc"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  # Built-in ECS rolling deployment controller with a CIRCUIT BREAKER.
  # This is the auto-rollback engine: ECS replaces tasks gradually; if the new
  # tasks fail to become healthy (or a rollback alarm fires), it AUTOMATICALLY
  # rolls back to the last-good task definition. No CodeDeploy required — works
  # on any account and is a very common production pattern for ECS.
  deployment_controller {
    type = "ECS"
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true # on failed deployment → auto-revert to previous version
  }

  # ALSO roll back if the 5xx CloudWatch alarm fires during/after a deploy — this
  # catches a version that starts "healthy" (passes /health) but errors on real
  # traffic (our ERROR_RATE break-test). This is the metric-driven rollback.
  alarms {
    alarm_names = [aws_cloudwatch_metric_alarm.http_5xx.alarm_name]
    enable      = true
    rollback    = true
  }

  # During a deploy keep at least 100% capacity and allow up to 200%, so new
  # tasks come up before old ones drain (zero-downtime rolling update).
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  # Wait this long for new tasks to pass ALB health checks before counting them.
  health_check_grace_period_seconds = 30

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.task.id]
    assign_public_ip = false # tasks are private; reach internet via NAT
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.blue.arn
    container_name   = "app"
    container_port   = var.app_port
  }

  # CI updates the task definition out-of-band; don't let Terraform fight it.
  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }

  depends_on = [aws_lb_listener.http]
}

