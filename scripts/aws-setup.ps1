<#
.SYNOPSIS
    Verify your AWS credentials and show which account/region you're pointed at.

.DESCRIPTION
    This does NOT store secrets. It just checks that `aws` can talk to your
    account and prints who you are — so we never build against the wrong account.

    IF YOU HAVEN'T CONFIGURED CREDENTIALS YET:
      Run this once in your terminal (interactive — it asks for your keys):
        aws configure
      You'll be prompted for:
        - AWS Access Key ID       (from IAM → Users → Security credentials)
        - AWS Secret Access Key
        - Default region name     (suggest: ap-south-1  = Mumbai)
        - Default output format   (suggest: json)

    SECURITY NOTE: never paste those keys into chat or commit them. `aws configure`
    stores them locally in %USERPROFILE%\.aws\credentials (git-ignored here).
    Best practice = create an IAM user with only the access it needs, or use SSO.
#>
$ErrorActionPreference = "Stop"

Write-Host "== Checking AWS credentials ==" -ForegroundColor Cyan
try {
    $id = aws sts get-caller-identity --output json | ConvertFrom-Json
    Write-Host "  [ok] Authenticated." -ForegroundColor Green
    Write-Host ("       Account : {0}" -f $id.Account)
    Write-Host ("       User/ARN: {0}" -f $id.Arn)
    $region = aws configure get region
    if (-not $region) { $region = $env:AWS_REGION }
    Write-Host ("       Region  : {0}" -f ($(if($region){$region}else{"<not set — run: aws configure set region ap-south-1>"})))
    Write-Host "`nReady. Next: cd terraform; terraform init" -ForegroundColor Green
} catch {
    Write-Host "  [!!] Not authenticated." -ForegroundColor Red
    Write-Host "       Run:  aws configure   (see the notes at the top of this script)" -ForegroundColor Yellow
}
