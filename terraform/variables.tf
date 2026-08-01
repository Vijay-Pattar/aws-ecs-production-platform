# Input variables — the knobs for the whole stack. Override in terraform.tfvars.

variable "project" {
  description = "Name prefix applied to every resource"
  type        = string
  default     = "ecs-prod-platform"
}

variable "region" {
  description = "AWS region to deploy into (ap-south-1 = Mumbai, low latency from India)"
  type        = string
  default     = "ap-south-1"
}

variable "budget_limit_usd" {
  description = "Monthly budget in USD; you get emailed if forecast/actual exceeds it"
  type        = number
  default     = 10
}

variable "budget_alert_email" {
  description = "Email address to receive budget + CloudWatch alarm notifications"
  type        = string
  # No default on purpose — set this in terraform.tfvars so alerts actually reach you.
}

variable "app_port" {
  description = "Container port the Flask app listens on"
  type        = number
  default     = 8000
}

variable "desired_count" {
  description = "Baseline number of Fargate tasks"
  type        = number
  default     = 2
}
