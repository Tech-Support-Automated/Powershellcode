<#
.SYNOPSIS
    Automated setup script: runs GCPW.ps1, script.ps1, downloads a logo,
    creates default user account pictures, and restarts the system.
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
# Create directory if it doesn't exist
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

$SourceImage = $LogoPath   # Use the file we just saved
$DestFolder  = "C:\ProgramData\Microsoft\User Account Pictures"

if (-not (Test-Path $SourceImage)) {
    Write-Host "ERROR: Source image not found: $SourceImage" -ForegroundColor Red
    exit 1
}

# Create destination folder
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

# Create main user.png
Copy-Item $SourceImage (Join-Path $DestFolder "user.png") -Force

# Enable default account picture policy
$PolicyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
if (-not (Test-Path $PolicyPath)) {
    New-Item -Path $PolicyPath -Force | Out-Null
}

New-ItemProperty -Path $PolicyPath `
                 -Name "UseDefaultTile" `
                 -Value 1 `
                 -PropertyType DWord `
                 -Force | Out-Null

# Remove current user's cached account pictures
$AccountPictures = "$env:APPDATA\Microsoft\Windows\AccountPictures"
if (Test-Path $AccountPictures) {
    Remove-Item "$AccountPictures\*" -Force -Recurse -ErrorAction SilentlyContinue
}

# Refresh Explorer to apply changes
Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Process explorer.exe

Write-Host ""
Write-Host "SUCCESS: BrightUI default account picture installed." -ForegroundColor Green
Write-Host "IMPORTANT: Sign out and sign back in (or restart Windows)." -ForegroundColor Yellow
Write-Host ""
Write-Host "Verify files exist in:" -ForegroundColor Cyan
Write-Host "C:\ProgramData\Microsoft\User Account Pictures"

# ------------------------------------------------------------
# 5. Restart the system after a short delay
# ------------------------------------------------------------
Write-Host "Restarting the system in 5 seconds..." -ForegroundColor Green
Start-Sleep -Seconds 5
Restart-Computer -Force
