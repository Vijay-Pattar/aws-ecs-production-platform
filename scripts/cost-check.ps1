<#
.SYNOPSIS
    After `terraform destroy`, confirm no billable resources are left running.
#>
$ErrorActionPreference = "Continue"
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
$region = "ap-south-1"

Write-Host "== Checking for leftover billable resources in $region ==" -ForegroundColor Cyan

Write-Host "`n-- Load balancers --" -ForegroundColor Yellow
aws elbv2 describe-load-balancers --region $region --query "LoadBalancers[?contains(LoadBalancerName,'ecs-prod-platform')].LoadBalancerName" --output text

Write-Host "-- NAT gateways (available) --" -ForegroundColor Yellow
aws ec2 describe-nat-gateways --region $region --filter "Name=state,Values=available" --query "NatGateways[].NatGatewayId" --output text

Write-Host "-- ECS services --" -ForegroundColor Yellow
aws ecs list-services --cluster ecs-prod-platform-cluster --region $region --query "serviceArns" --output text 2>$null

Write-Host "-- Unattached Elastic IPs --" -ForegroundColor Yellow
aws ec2 describe-addresses --region $region --query "Addresses[?AssociationId==null].PublicIp" --output text

Write-Host "`nIf all of the above are empty, you're at ~`$0. Otherwise run terraform destroy again." -ForegroundColor Green
