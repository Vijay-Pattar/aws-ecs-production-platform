# ============================================================================
# IAM ROLES for ECS. Two DIFFERENT roles — a classic interview distinction:
#
#   EXECUTION role : used by the ECS *agent* to START the task — pull the image
#                    from ECR, fetch secrets, write logs. (Infrastructure plane.)
#   TASK role      : the identity the *app code* runs as — what your container
#                    can do to AWS (e.g. read DynamoDB, read a secret). (App plane.)
#
# Least privilege: the task role only gets the specific actions the app needs.
# ============================================================================

data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# ---- Execution role: pull image, write logs, read secrets at startup ----
resource "aws_iam_role" "execution" {
  name               = "${var.project}-exec-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Allow the execution role to read our specific secret (for secret injection).
resource "aws_iam_role_policy" "execution_secrets" {
  name = "read-app-secret"
  role = aws_iam_role.execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = [aws_secretsmanager_secret.app.arn]
    }]
  })
}

# ---- Task role: what the running app may do (least privilege) ----
resource "aws_iam_role" "task" {
  name               = "${var.project}-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

# App can read/write ONLY its own DynamoDB table, and read ONLY its own secret.
resource "aws_iam_role_policy" "task_app" {
  name = "app-permissions"
  role = aws_iam_role.task.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:UpdateItem", "dynamodb:GetItem", "dynamodb:PutItem"]
        Resource = [aws_dynamodb_table.visits.arn]
      },
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [aws_secretsmanager_secret.app.arn]
      }
    ]
  })
}
