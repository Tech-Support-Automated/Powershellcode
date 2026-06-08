<#
.SYNOPSIS
    BrightUI full setup – downloads assets, runs configuration scripts,
    installs default account picture, and restarts.
.DESCRIPTION
    Run this script as Administrator. It will:
      1. Download the BrightUI logo to C:\ProgramData\BrightUI\Assets
      2. Execute GCPW.ps1 from GitHub
      3. Execute script.ps1 from GitHub
      4. Install the logo as the default account picture (all required sizes)
      5. Restart the system
.NOTES
    Requires PowerShell with Administrator privileges and an internet connection.
#>

#Requires -RunAsAdministrator

# ------------------------------------------------------------
# 1. DOWNLOAD THE BRIGHTUI LOGO
# ------------------------------------------------------------
$LogoUrl      = 'https://raw.githubusercontent.com/Tech-Support-Automated/Powershellcode/master/brightui_technologies_logo.jpg'
$LogoDestPath = 'C:\ProgramData\BrightUI\Assets\brightui_technologies_logo.jpg'
$LogoDestDir  = Split-Path $LogoDestPath -Parent

Write-Host "Creating directory: $LogoDestDir" -ForegroundColor Cyan
New-Item -Path $LogoDestDir -ItemType Directory -Force | Out-Null

Write-Host "Downloading BrightUI logo..." -ForegroundColor Cyan
try {
    Invoke-WebRequest -Uri $LogoUrl -OutFile $LogoDestPath -ErrorAction Stop
    Write-Host "Logo saved to: $LogoDestPath" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to download logo. $_" -ForegroundColor Red
    exit 1
}

# ------------------------------------------------------------
# 2. RUN GCPW SCRIPT
# ------------------------------------------------------------
Write-Host "Downloading and executing GCPW.ps1..." -ForegroundColor Cyan
try {
    $gcpwScript = Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/Tech-Support-Automated/Powershellcode/master/GCPW.ps1'
    Invoke-Expression $gcpwScript
    if (-not $?) {
        throw "GCPW.ps1 execution reported failure."
    }
    Write-Host "GCPW.ps1 completed successfully." -ForegroundColor Green
} catch {
    Write-Host "ERROR: GCPW.ps1 failed. $_" -ForegroundColor Red
    exit 1
}

# ------------------------------------------------------------
# 3. RUN MAIN SETUP SCRIPT
# ------------------------------------------------------------
Write-Host "Downloading and executing script.ps1..." -ForegroundColor Cyan
try {
    $mainScript = Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/Tech-Support-Automated/Powershellcode/master/script.ps1'
    Invoke-Expression $mainScript
    if (-not $?) {
        throw "script.ps1 execution reported failure."
    }
    Write-Host "script.ps1 completed successfully." -ForegroundColor Green
} catch {
    Write-Host "ERROR: script.ps1 failed. $_" -ForegroundColor Red
    exit 1
}

# ------------------------------------------------------------
# 4. INSTALL DEFAULT ACCOUNT PICTURE (from Setuplogo.sp1)
# ------------------------------------------------------------
Write-Host "Installing BrightUI default account picture..." -ForegroundColor Cyan

Add-Type -AssemblyName System.Drawing

$SourceImage = $LogoDestPath
$DestFolder  = 'C:\ProgramData\Microsoft\User Account Pictures'

if (-not (Test-Path $SourceImage)) {
    Write-Host "ERROR: Source image not found: $SourceImage" -ForegroundColor Red
    exit 1
}

# Create destination folder
New-Item -Path $DestFolder -ItemType Directory -Force | Out-Null

# Generate all required sizes
$Sizes = @(32, 40, 48, 96, 192, 200, 240, 448)

foreach ($Size in $Sizes) {
    try {
        $Bitmap   = [System.Drawing.Image]::FromFile($SourceImage)
        $Resized  = New-Object System.Drawing.Bitmap $Size, $Size
        $Graphics = [System.Drawing.Graphics]::FromImage($Resized)
        $Graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $Graphics.DrawImage($Bitmap, 0, 0, $Size, $Size)

        $Resized.Save(
            (Join-Path $DestFolder "user-$Size.png"),
            [System.Drawing.Imaging.ImageFormat]::Png
        )

        $Graphics.Dispose()
        $Resized.Dispose()
        $Bitmap.Dispose()
    } catch {
        Write-Host "Failed creating size $Size" -ForegroundColor Red
    }
}

# Create main user.png
Copy-Item $SourceImage "$DestFolder\user.png" -Force

# Enable default account picture policy
$PolicyPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
if (-not (Test-Path $PolicyPath)) {
    New-Item -Path $PolicyPath -Force | Out-Null
}
New-ItemProperty -Path $PolicyPath -Name 'UseDefaultTile' -Value 1 -PropertyType DWord -Force | Out-Null

# Remove current user's cached account pictures
$AccountPictures = "$env:APPDATA\Microsoft\Windows\AccountPictures"
if (Test-Path $AccountPictures) {
    Remove-Item "$AccountPictures\*" -Force -Recurse -ErrorAction SilentlyContinue
}

# Refresh Explorer so changes take effect immediately
Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Process explorer.exe

Write-Host "Account picture installation complete." -ForegroundColor Green

# ------------------------------------------------------------
# 5. RESTART THE COMPUTER
# ------------------------------------------------------------
Write-Host "Restarting the system in 5 seconds..." -ForegroundColor Yellow
Start-Sleep -Seconds 5
Restart-Computer -Force
