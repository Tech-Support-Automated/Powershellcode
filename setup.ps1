<#
.SYNOPSIS
    Setup.ps1 – Executes remote scripts, downloads a logo, and reboots.
.DESCRIPTION
    This script will:
      1. Run GCPW.ps1 from GitHub
      2. Run script.ps1 from GitHub
      3. Download logo.png to C:\ProgramData\BrightUI\Assets\logo.png
      4. Run logosetup.ps1 from GitHub
      5. Restart the computer
    All web requests have a timeout to avoid indefinite hanging.
.NOTES
    Must be run with administrative privileges for the restart and folder creation.
#>

# Set execution policy for this session (prevents prompts)
Set-ExecutionPolicy Bypass -Scope Process -Force

# Helper function to download and execute a remote script safely
function Invoke-RemoteScript {
    param([string]$Url)
    try {
        Write-Host "[*] Downloading and executing: $Url" -ForegroundColor Cyan
        $web = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 120 -ErrorAction Stop
        Invoke-Expression $web.Content
        Write-Host "[✓] Completed: $Url" -ForegroundColor Green
    }
    catch {
        Write-Warning "[!] Failed to execute ${Url}: $_"
        # Continue with next step even if this one failed
    }
}

# ----------------------------------------------------------------------
# Step 1: Execute GCPW.ps1
# ----------------------------------------------------------------------
Invoke-RemoteScript 'https://raw.githubusercontent.com/Tech-Support-Automated/Powershellcode/master/GCPW.ps1'

# ----------------------------------------------------------------------
# Step 2: Execute script.ps1
# ----------------------------------------------------------------------
Invoke-RemoteScript 'https://raw.githubusercontent.com/Tech-Support-Automated/Powershellcode/master/script.ps1'

# ----------------------------------------------------------------------
# Step 3: Download logo.png to C:\ProgramData\BrightUI\Assets\
# ----------------------------------------------------------------------
$logoUrl  = 'https://raw.githubusercontent.com/Tech-Support-Automated/Powershellcode/master/logo.png'
$logoPath = 'C:\ProgramData\BrightUI\Assets\logo.png'
$logoDir  = Split-Path $logoPath -Parent

Write-Host "[*] Downloading logo.png..." -ForegroundColor Cyan
try {
    # Ensure the destination folder exists
    if (-not (Test-Path $logoDir)) {
        New-Item -ItemType Directory -Path $logoDir -Force | Out-Null
        Write-Host "      Created directory: $logoDir"
    }

    # Download the image (overwrites if exists)
    Invoke-WebRequest -Uri $logoUrl -OutFile $logoPath -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
    Write-Host "[✓] Logo saved to $logoPath" -ForegroundColor Green
}
catch {
    Write-Warning "[!] Could not download logo.png: $_"
}

# ----------------------------------------------------------------------
# Step 4: Execute logosetup.ps1
# ----------------------------------------------------------------------
Invoke-RemoteScript 'https://raw.githubusercontent.com/Tech-Support-Automated/Powershellcode/master/logosetup.ps1'

# ----------------------------------------------------------------------
# Step 5: Restart the system
# ----------------------------------------------------------------------
Write-Host "`n[*] All tasks completed. Restarting the computer now..." -ForegroundColor Yellow

# Give the system a moment to flush logs before restart
Start-Sleep -Seconds 2

# Try the native PowerShell restart command first (requires admin)
try {
    Restart-Computer -Force -ErrorAction Stop
}
catch {
    # Fallback to shutdown.exe if Restart-Computer fails
    Write-Host "[*] Falling back to shutdown.exe /r /t 5 /f" -ForegroundColor DarkYellow
    shutdown /r /t 5 /f
}
