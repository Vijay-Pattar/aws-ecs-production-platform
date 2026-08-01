<#
.SYNOPSIS
    Install the CLI tools this AWS project needs, then verify them.

.DESCRIPTION
    You already have: aws (AWS CLI v2), docker, git.
    This installs:      terraform.

    Free / open source. Run in a normal PowerShell window.
    After install, open a NEW window so PATH refreshes.
#>
$ErrorActionPreference = "Stop"

function Have($n){ [bool](Get-Command $n -ErrorAction SilentlyContinue) }

Write-Host "== AWS ECS Production Platform :: tool installer ==" -ForegroundColor Cyan

if (Have terraform) {
    Write-Host "[skip] terraform already installed" -ForegroundColor DarkGray
} else {
    Write-Host "[install] terraform via winget (Hashicorp.Terraform)" -ForegroundColor Yellow
    winget install --id Hashicorp.Terraform --exact --accept-package-agreements --accept-source-agreements
}

Write-Host "`n== Verification ==" -ForegroundColor Cyan
$ok = $true
foreach ($t in @("aws","terraform","docker","git")) {
    if (Have $t) { Write-Host ("  [ok]  {0}" -f $t) -ForegroundColor Green }
    else { Write-Host ("  [!!]  {0} NOT found" -f $t) -ForegroundColor Red; $ok = $false }
}

if ($ok) {
    Write-Host "`nAll tools present. Next: configure AWS credentials -> scripts/aws-setup.ps1" -ForegroundColor Green
} else {
    Write-Host "`nSome tools missing. If terraform was just installed, open a NEW PowerShell window." -ForegroundColor Yellow
}
