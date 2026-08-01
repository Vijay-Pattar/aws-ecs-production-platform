<#
.SYNOPSIS
    Tear the whole stack down (stop all cost). Run this after every work session.

.DESCRIPTION
    `terraform destroy` removes every resource Terraform created. The billable
    ones (NAT gateway, ALB, Fargate tasks) stop charging as soon as they're gone.
    ECR + DynamoDB + budget are effectively free and also removed.
#>
$ErrorActionPreference = "Stop"
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User") + ";$env:LOCALAPPDATA\Microsoft\WinGet\Links"
Set-Location (Join-Path $PSScriptRoot "..\terraform")

Write-Host "== Destroying the whole stack ==" -ForegroundColor Yellow
terraform destroy -auto-approve

Write-Host "`nDestroyed. Verify nothing is left (see scripts/cost-check.ps1)." -ForegroundColor Green
