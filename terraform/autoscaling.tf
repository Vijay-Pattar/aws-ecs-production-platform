# ============================================================================
# APPLICATION AUTO SCALING — grow/shrink the number of Fargate tasks with load.
# Target-tracking: "keep average CPU at 50%". If CPU rises above target, add
# tasks; when it falls, remove them (down to min). Like a thermostat for capacity.
# ============================================================================

resource "aws_appautoscaling_target" "ecs" {
  max_capacity       = 6
  min_capacity       = var.desired_count
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# Scale on CPU utilization.
resource "aws_appautoscaling_policy" "cpu" {
  name               = "${var.project}-cpu-target"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 50.0
    scale_in_cooldown  = 60
    scale_out_cooldown = 60
  }
}

# Also scale on requests-per-task through the ALB — often a better signal than
# CPU for web apps (traffic spikes before CPU does).
resource "aws_appautoscaling_policy" "requests" {
  name               = "${var.project}-req-target"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      # tie the metric to our ALB + blue target group
      resource_label = "${aws_lb.app.arn_suffix}/${aws_lb_target_group.blue.arn_suffix}"
    }
    target_value       = 1000.0 # requests per task per minute
    scale_in_cooldown  = 60
    scale_out_cooldown = 60
  }
}
