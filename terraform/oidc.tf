# ============================================================================
# GITHUB OIDC — let GitHub Actions assume an AWS role with NO static keys.
#
# The old way: store an AWS access key + secret as GitHub secrets (long-lived,
# leakable). The modern way: GitHub Actions presents a short-lived OIDC token;
# AWS trusts GitHub's OIDC provider and issues TEMPORARY credentials, scoped to
# THIS repo only. Nothing long-lived to leak. This is a strong security signal.
#
# Set var.github_repo to your actual GitHub owner/name before use.
# ============================================================================

variable "github_repo" {
  description = "GitHub repo allowed to assume the deploy role, as owner/name"
  type        = string
  default     = "Vijay-Pattar/aws-ecs-production-platform"
}

# Register GitHub as an OIDC identity provider in your account.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # GitHub's OIDC thumbprint (well-known). AWS now largely ignores this but the
  # field is still required.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_policy_document" "github_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    # Only THIS repo (any branch) may assume the role.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  name               = "${var.project}-gha-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_assume.json
}

# Least-privilege deploy permissions: push to ECR, register task defs, and drive
# CodeDeploy. (Kept tight; not AdministratorAccess.)
resource "aws_iam_role_policy" "github_deploy" {
  name = "deploy-permissions"
  role = aws_iam_role.github_deploy.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ECRAuth"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "ECRPush"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability", "ecr:CompleteLayerUpload",
          "ecr:InitiateLayerUpload", "ecr:PutImage", "ecr:UploadLayerPart",
          "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"
        ]
        Resource = [aws_ecr_repository.app.arn]
      },
      {
        Sid      = "TaskDefRegister"
        Effect   = "Allow"
        Action   = ["ecs:RegisterTaskDefinition", "ecs:DescribeTaskDefinition", "ecs:DescribeServices"]
        Resource = "*"
      },
      {
        Sid      = "EcsDeploy"
        Effect   = "Allow"
        Action   = ["ecs:UpdateService"]
        Resource = "*"
      },
      {
        Sid      = "PassEcsRoles"
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = [aws_iam_role.execution.arn, aws_iam_role.task.arn]
      }
    ]
  })
}

output "github_deploy_role_arn" {
  description = "Set this as the AWS_DEPLOY_ROLE in GitHub Actions (repo variable)"
  value       = aws_iam_role.github_deploy.arn
}
