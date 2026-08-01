# ECR — Elastic Container Registry. A private Docker registry in your AWS account.
# GitHub Actions builds the image and pushes it here; ECS Fargate pulls it from
# here to run tasks. (Like Docker Hub, but private and inside your account.)

resource "aws_ecr_repository" "app" {
  name = "${var.project}-app"

  # Immutable tags: once you push image:abc123 you can't overwrite that tag.
  # Prevents "the tag moved under me" surprises — every deploy is a distinct image.
  image_tag_mutability = "IMMUTABLE"

  # Scan images for known CVEs automatically on push.
  image_scanning_configuration {
    scan_on_push = true
  }

  # Demo project: allow `terraform destroy` to remove the repo even if it still
  # holds images. (In prod you'd protect this.)
  force_delete = true
}

# Lifecycle policy: keep only the last 10 images so the registry doesn't grow
# (and cost) forever. Old images are expired automatically.
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

output "ecr_repository_url" {
  description = "Push/pull URL for the app image"
  value       = aws_ecr_repository.app.repository_url
}
