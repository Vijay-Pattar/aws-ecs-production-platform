<#
.SYNOPSIS
    Build the app image and push it to ECR.

.DESCRIPTION
    Usage:  scripts/build-push.ps1 -Tag v1 [-ErrorRate 0.0]
    Builds the Docker image, logs in to ECR, tags, and pushes.

    NOTE on the ECR login: on Windows PowerShell, piping the token straight into
    `docker login --password-stdin` can fail with a 400 (encoding of the piped
    string). Capturing the token in a variable and passing --password avoids it.
#>
param(
    [string]$Tag = "v1",
    [string]$ErrorRate = "0.0",
    [string]$Region = "ap-south-1"
)
$ErrorActionPreference = "Stop"
$root = Join-Path $PSScriptRoot ".."

$acct = (aws sts get-caller-identity --query Account --output text).Trim()
$registry = "$acct.dkr.ecr.$Region.amazonaws.com"
$repo = "$registry/ecs-prod-platform-app"

Write-Host "== Build image (tag=$Tag) ==" -ForegroundColor Cyan
docker build -t "aws-ecs-app:$Tag" --build-arg APP_VERSION=$Tag $root

Write-Host "== ECR login ==" -ForegroundColor Cyan
$pw = (aws ecr get-login-password --region $Region)
docker login --username AWS --password $pw $registry | Out-Null

Write-Host "== Tag + push ==" -ForegroundColor Cyan
docker tag "aws-ecs-app:$Tag" "${repo}:$Tag"
docker push "${repo}:$Tag"

Write-Host "`nPushed ${repo}:$Tag" -ForegroundColor Green
