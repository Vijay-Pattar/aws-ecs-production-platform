# ============================================================================
# DATA STORE + SECRETS
#
# DynamoDB (not RDS) on purpose: on-demand billing = pay-per-request (free-tier
# covers this demo), provisions in seconds (RDS takes ~10 min and costs more),
# and needs no VPC/subnet/patching. Perfect for a cost-controlled portfolio demo.
# The app increments a "visits" counter here to prove a private-subnet task can
# reach AWS data with least-privilege IAM.
# ============================================================================
resource "aws_dynamodb_table" "visits" {
  name         = "${var.project}-visits"
  billing_mode = "PAY_PER_REQUEST" # on-demand; no capacity to size or pay idle
  hash_key     = "pk"

  attribute {
    name = "pk"
    type = "S"
  }
  tags = { Name = "${var.project}-visits" }
}

# ---- Secrets Manager: a demo secret the app reads at runtime ----
# The point: NO secret value in code, env files, or git. The app fetches it at
# runtime using its task-role identity. We only store a harmless "greeting" here.
resource "aws_secretsmanager_secret" "app" {
  name                    = "${var.project}-app-secret"
  description             = "Demo app secret (proves secret wiring, no real sensitive data)"
  recovery_window_in_days = 0 # allow immediate delete on destroy (demo only)
}

resource "aws_secretsmanager_secret_version" "app" {
  secret_id     = aws_secretsmanager_secret.app.id
  secret_string = jsonencode({ greeting = "hello-from-secrets-manager" })
}
