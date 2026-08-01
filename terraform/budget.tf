# ============================================================================
# SAFETY RAIL #1 — an AWS Budget that emails you before costs get real.
# This is deliberately the FIRST thing we create. On a free-tier account, an
# accidental always-on resource (NAT gateway, RDS) is the usual way people get a
# surprise bill. This catches it early.
# ============================================================================

# Notify at 80% (forecast) and 100% (actual) of the monthly limit.
resource "aws_budgets_budget" "monthly" {
  name         = "${var.project}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Warn when AWS *forecasts* you'll cross 80% of the limit this month.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_alert_email]
  }

  # Warn again when *actual* spend hits 100%.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }
}
