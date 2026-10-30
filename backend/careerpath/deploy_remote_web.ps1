# ==============================================================================
# CareerPath - Remote Testing Deployment Script (Cloudflare Tunnel + Firebase)
# Usage:
#   .\deploy_remote_web.ps1 -BackendUrl "https://<tunnel-id>.trycloudflare.com"
# ==============================================================================
param (
    [Parameter(Mandatory = $true)]
    [string]$BackendUrl
)

# Normalize URL (remove trailing slash)
$BackendUrl = $BackendUrl.TrimEnd('/')

Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host "   CareerPath Remote Web Deployment (Stage 13)" -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "Target Backend URL : $BackendUrl" -ForegroundColor Yellow
Write-Host "Target Frontend    : https://careerpath-26fa0.web.app" -ForegroundColor Yellow
Write-Host "Firebase Project   : careerpath-26fa0" -ForegroundColor Yellow
Write-Host "=======================================================`n" -ForegroundColor Cyan

# Step 1: Health check against the tunnel URL
Write-Host "[1/3] Testing backend health over Cloudflare Tunnel..." -ForegroundColor Green
try {
    $health = Invoke-RestMethod -Uri "$BackendUrl/" -Method Get -TimeoutSec 10 -ErrorAction Stop
    Write-Host "      Backend responded: $($health.app) (Status: $($health.status))" -ForegroundColor Green
} catch {
    Write-Host "      WARNING: Could not connect to $BackendUrl/. Ensure Cloudflare Tunnel is running." -ForegroundColor Red
    Write-Host "      Details: $_" -ForegroundColor Red
    $confirm = Read-Host "Proceed with build anyway? (y/N)"
    if ($confirm -ne 'y' -and $confirm -ne 'Y') {
        Write-Host "Deployment aborted." -ForegroundColor Red
        exit 1
    }
}

# Step 2: Build Flutter Web in Release Mode
Write-Host "`n[2/3] Building Flutter Web in Release Mode (Production)..." -ForegroundColor Green
flutter build web --release --dart-define="BACKEND_URL=$BackendUrl"
if ($LASTEXITCODE -ne 0) {
    Write-Host "Flutter Web build failed." -ForegroundColor Red
    exit $LASTEXITCODE
}

# Step 3: Deploy to Firebase Hosting
Write-Host "`n[3/3] Deploying build/web to Firebase Hosting..." -ForegroundColor Green
firebase.cmd deploy --only hosting --project careerpath-26fa0
if ($LASTEXITCODE -ne 0) {
    Write-Host "Firebase deployment failed." -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host "`n=======================================================" -ForegroundColor Green
Write-Host "   DEPLOYMENT COMPLETE & LIVE!" -ForegroundColor Green
Write-Host "=======================================================" -ForegroundColor Green
Write-Host "Shareable Website URL: https://careerpath-26fa0.web.app" -ForegroundColor Cyan
Write-Host "Students can open this link from any device or network." -ForegroundColor White
Write-Host "Ensure Cloudflare Tunnel remains open while testing.`n" -ForegroundColor Yellow
