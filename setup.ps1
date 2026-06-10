<#
.SYNOPSIS
    Automated setup script: runs GCPW.ps1, script.ps1, downloads a logo,
    creates default user account pictures, installs Lightshot & Office 2019 via Chocolatey,
    then restarts the system. No activation scripts are included.
.NOTES
    Must be run as Administrator.
#>

#Requires -RunAsAdministrator

# ------------------------------------------------------------
# 1. Run the first remote script (GCPW)
# ------------------------------------------------------------
Write-Host "Downloading and executing GCPW.ps1..." -ForegroundColor Cyan
try {
    iex (Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/Tech-Support-Automated/Powershellcode/master/GCPW.ps1' -UseBasicParsing).Content
} catch {
    Write-Host "ERROR: Failed to download or execute GCPW.ps1. $_" -ForegroundColor Red
    exit 1
}

if (-not $?) {
    Write-Host "Error: GCPW.ps1 failed to execute properly. The sequence has been stopped." -ForegroundColor Red
    exit 1
}
Write-Host "GCPW.ps1 completed successfully." -ForegroundColor Green

# ------------------------------------------------------------
# 2. Run the second remote script (script.ps1)
# ------------------------------------------------------------
Write-Host "Downloading and executing script.ps1..." -ForegroundColor Cyan
try {
    iex (Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/Tech-Support-Automated/Powershellcode/master/script.ps1' -UseBasicParsing).Content
} catch {
    Write-Host "ERROR: Failed to download or execute script.ps1. $_" -ForegroundColor Red
    exit 1
}

if (-not $?) {
    Write-Host "Error: script.ps1 failed to execute properly. The system will not restart." -ForegroundColor Red
    exit 1
}
Write-Host "script.ps1 completed successfully." -ForegroundColor Green

# ------------------------------------------------------------
# 3. Download the logo image and save to the required location
# ------------------------------------------------------------
$LogoUrl  = "https://raw.githubusercontent.com/Tech-Support-Automated/Powershellcode/master/logo.png"
$LogoDir  = "C:\ProgramData\BrightUI\Assets"
$LogoPath = Join-Path $LogoDir "brightui_technologies_logo.png"

Write-Host "Downloading logo image..." -ForegroundColor Cyan
if (-not (Test-Path $LogoDir)) {
    New-Item -Path $LogoDir -ItemType Directory -Force | Out-Null
}

try {
    Invoke-WebRequest -Uri $LogoUrl -OutFile $LogoPath -UseBasicParsing
} catch {
    Write-Host "ERROR: Failed to download logo.png. $_" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $LogoPath)) {
    Write-Host "ERROR: Logo file not found after download attempt." -ForegroundColor Red
    exit 1
}
Write-Host "Logo saved to: $LogoPath" -ForegroundColor Green

# ------------------------------------------------------------
# 4. Generate all default user account pictures from the logo
# ------------------------------------------------------------
Add-Type -AssemblyName System.Drawing

$SourceImage = $LogoPath
$DestFolder  = "C:\ProgramData\Microsoft\User Account Pictures"

if (-not (Test-Path $SourceImage)) {
    Write-Host "ERROR: Source image not found: $SourceImage" -ForegroundColor Red
    exit 1
}

New-Item -Path $DestFolder -ItemType Directory -Force | Out-Null

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
        Write-Host "Failed creating size $Size - $_" -ForegroundColor Red
    }
}

Copy-Item $SourceImage (Join-Path $DestFolder "user.png") -Force

$PolicyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
if (-not (Test-Path $PolicyPath)) {
    New-Item -Path $PolicyPath -Force | Out-Null
}

New-ItemProperty -Path $PolicyPath `
                 -Name "UseDefaultTile" `
                 -Value 1 `
                 -PropertyType DWord `
                 -Force | Out-Null

$AccountPictures = "$env:APPDATA\Microsoft\Windows\AccountPictures"
if (Test-Path $AccountPictures) {
    Remove-Item "$AccountPictures\*" -Force -Recurse -ErrorAction SilentlyContinue
}

Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Process explorer.exe

Write-Host ""
Write-Host "SUCCESS: BrightUI default account picture installed." -ForegroundColor Green
Write-Host "IMPORTANT: Sign out and sign back in (or restart Windows)." -ForegroundColor Yellow
Write-Host ""

# ------------------------------------------------------------
# 5. Install Chocolatey (if not already present)
# ------------------------------------------------------------
Write-Host "Checking for Chocolatey..." -ForegroundColor Cyan
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Chocolatey silently..." -ForegroundColor Yellow
    try {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    } catch {
        Write-Host "ERROR: Chocolatey installation failed. $_" -ForegroundColor Red
        exit 1
    }
    # Refresh environment so choco is immediately available
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path","User")
} else {
    Write-Host "Chocolatey is already installed." -ForegroundColor Green
}

# ------------------------------------------------------------
# 6. Install Lightshot silently
# ------------------------------------------------------------
Write-Host "Installing Lightshot silently via Chocolatey..." -ForegroundColor Cyan
try {
    choco install lightshot -y --limit-output
} catch {
    Write-Host "ERROR: Lightshot installation failed. $_" -ForegroundColor Red
    # Not critical; we continue
}
Write-Host "Lightshot installation complete." -ForegroundColor Green

# ------------------------------------------------------------
# 7. Install Microsoft Office 2019 Professional Plus silently
# ------------------------------------------------------------
Write-Host "Installing Microsoft Office 2019 Professional Plus (this may take several minutes)..." -ForegroundColor Cyan
try {
    choco install office2019proplus -y --limit-output
} catch {
    Write-Host "ERROR: Office 2019 installation failed. $_" -ForegroundColor Red
    exit 1
}
Write-Host "Office 2019 installation completed." -ForegroundColor Green

# ------------------------------------------------------------
# 8. Restart the system
# ------------------------------------------------------------
Write-Host "All tasks completed. Restarting the system in 5 seconds..." -ForegroundColor Green
Start-Sleep -Seconds 5
Restart-Computer -Force
