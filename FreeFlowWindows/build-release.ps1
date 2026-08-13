# FreeFlow Windows - Release Build Script
# Creates self-contained single-file executables for distribution

param(
    [string]$Version = "1.0.0",
    [switch]$SkipTests,
    [switch]$Arm64Only,
    [switch]$X64Only
)

$ErrorActionPreference = "Stop"

Write-Host "======================================" -ForegroundColor Cyan
Write-Host "  FreeFlow Windows - Release Build" -ForegroundColor Cyan
Write-Host "  Version: $Version" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""

# Set working directory to script location
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

# Clean previous builds
Write-Host "[1/5] Cleaning previous builds..." -ForegroundColor Yellow
if (Test-Path "FreeFlowWindows.App\bin\Release\publish") {
    Remove-Item -Recurse -Force "FreeFlowWindows.App\bin\Release\publish"
}

# Restore packages
Write-Host "[2/5] Restoring NuGet packages..." -ForegroundColor Yellow
dotnet restore FreeFlowWindows.sln
if ($LASTEXITCODE -ne 0) { 
    Write-Host "ERROR: Package restore failed!" -ForegroundColor Red
    exit 1 
}

# Run tests (unless skipped)
if (-not $SkipTests) {
    Write-Host "[3/5] Running tests..." -ForegroundColor Yellow
    dotnet test FreeFlowWindows.Tests --configuration Release --verbosity minimal
    if ($LASTEXITCODE -ne 0) { 
        Write-Host "ERROR: Tests failed!" -ForegroundColor Red
        exit 1 
    }
} else {
    Write-Host "[3/5] Skipping tests..." -ForegroundColor Yellow
}

# Build and publish
Write-Host "[4/5] Building and publishing..." -ForegroundColor Yellow

$publishTargets = @()
if (-not $Arm64Only) { $publishTargets += "win-x64" }
if (-not $X64Only) { $publishTargets += "win-arm64" }

foreach ($rid in $publishTargets) {
    Write-Host "  Publishing for $rid..." -ForegroundColor Gray
    dotnet publish FreeFlowWindows.App `
        --configuration Release `
        --runtime $rid `
        --self-contained true `
        -p:PublishSingleFile=true `
        -p:PublishReadyToRun=true `
        -p:IncludeNativeLibrariesForSelfExtract=true `
        -p:EnableCompressionInSingleFile=true `
        -p:Version=$Version `
        -p:FileVersion="$Version.0" `
        -p:AssemblyVersion="$Version.0" `
        --output "FreeFlowWindows.App\bin\Release\publish\$rid"
    
    if ($LASTEXITCODE -ne 0) { 
        Write-Host "ERROR: Publish failed for $rid!" -ForegroundColor Red
        exit 1 
    }
}

# Create release archives
Write-Host "[5/5] Creating release archives..." -ForegroundColor Yellow
$releaseDir = "releases\v$Version"
New-Item -ItemType Directory -Path $releaseDir -Force | Out-Null

foreach ($rid in $publishTargets) {
    $publishDir = "FreeFlowWindows.App\bin\Release\publish\$rid"
    $zipName = "FreeFlow-Windows-$Version-$rid.zip"
    
    Write-Host "  Creating $zipName..." -ForegroundColor Gray
    
    # Create zip archive
    Compress-Archive -Path "$publishDir\*" -DestinationPath "$releaseDir\$zipName" -Force
}

# Display results
Write-Host ""
Write-Host "======================================" -ForegroundColor Green
Write-Host "  Build completed successfully!" -ForegroundColor Green
Write-Host "======================================" -ForegroundColor Green
Write-Host ""
Write-Host "Release files created in: $releaseDir" -ForegroundColor Cyan
Write-Host ""

Get-ChildItem $releaseDir | ForEach-Object {
    $size = [math]::Round($_.Length / 1MB, 2)
    Write-Host "  $($_.Name) ($size MB)" -ForegroundColor White
}

Write-Host ""
Write-Host "To install:" -ForegroundColor Yellow
Write-Host "  1. Extract the ZIP file to a folder of your choice" -ForegroundColor Gray
Write-Host "  2. Run FreeFlow.exe" -ForegroundColor Gray
Write-Host "  3. The app will appear in your system tray" -ForegroundColor Gray
Write-Host ""
