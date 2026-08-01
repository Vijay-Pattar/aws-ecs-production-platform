# Terraform + provider setup.
#
# Terraform is "infrastructure as code": you declare the AWS resources you want
# in these .tf files, and `terraform apply` makes AWS match them. `terraform
# destroy` deletes them all — that's our cost-control lever.
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }

  # State (the record of what Terraform created) is stored LOCALLY by default —
  # fine for an apply→demo→destroy project. For team use you'd store it in S3
  # with a DynamoDB lock; see backend.tf for that (commented) option.
}

provider "aws" {
  region = var.region

  # Tag EVERY resource automatically. Makes cost tracking + cleanup easy, and
  # proves good hygiene (interviewers notice consistent tagging).
  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Owner     = "vijay-pattar"
      Ephemeral = "true" # reminder: this stack is meant to be destroyed after demos
    }
  }
}
