# Terraform STATE backend.
#
# By default this project uses LOCAL state (a terraform.tfstate file on your
# machine, git-ignored). That's perfectly fine for a solo apply→demo→destroy
# project and keeps setup simple.
#
# In a REAL team you'd store state remotely so everyone shares one source of
# truth and can lock it during applies. The standard AWS pattern is an S3 bucket
# (state) + a DynamoDB table (lock). To switch, create those two resources, then
# uncomment and fill in the block below and run `terraform init -migrate-state`.
#
# terraform {
#   backend "s3" {
#     bucket         = "<your-tf-state-bucket>"
#     key            = "ecs-prod-platform/terraform.tfstate"
#     region         = "ap-south-1"
#     dynamodb_table = "<your-tf-lock-table>"
#     encrypt        = true
#   }
# }
