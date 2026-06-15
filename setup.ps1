<#
.SYNOPSIS
    Automated setup script: runs GCPW.ps1, script.ps1, downloads a logo,
    creates default user account pictures, installs required software (Lightshot,
    Office 2019, VS Code, SourceTree, Docker Desktop, GitHub Desktop) silently,
    creates VS Code desktop shortcut, suppresses auto-launch of installed apps,
    then restarts the system. No activation scripts are included.
.NOTES
    Must be run as Administrator.
#>

#Requires -RunAsAdministrator

# ------------------------------------------------------------
# Helper: Kill a process if it is running (case-insensitive)
# ------------------------------------------------------------
function Stop-ProcessIfRunning {
    param([string]$ProcessName)
    $proc = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
    if ($proc) {
        Write-Host "Stopping $ProcessName to prevent auto-launch..." -ForegroundColor Yellow
        Stop-Process -Name $ProcessName -Force -ErrorAction SilentlyContinue
    }
}

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
# 5. Install Chocolatey (if not already present) and enable global confirmation
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

# Enable global confirmation to avoid any YES/NO prompts
choco feature enable -n allowGlobalConfirmation

# ------------------------------------------------------------
# 6. Install all required software silently
# ------------------------------------------------------------
$packages = @(
    "lightshot",           # already present, will reinstall/upgrade if needed
    "office2019proplus",
    "vscode",
    "sourcetree",
    "docker-desktop",
    "github-desktop"
)

foreach ($pkg in $packages) {
    Write-Host "Installing $pkg (this may take a while)..." -ForegroundColor Cyan
    try {
        # Use --ignore-detected-reboot to avoid hanging
        choco install $pkg -y --limit-output --ignore-detected-reboot
    } catch {
        Write-Host "ERROR: $pkg installation failed. Continuing with next package. $_" -ForegroundColor Red
    }
}

# ------------------------------------------------------------
# 7. Prevent applications from auto-launching after installation
# ------------------------------------------------------------
Write-Host "Ensuring no installed applications open automatically..." -ForegroundColor Yellow

# Potential process names that might have started after install
$processesToKill = @(
    "Code",                # VS Code
    "SourceTree",
    "GitHubDesktop",
    "Docker Desktop",
    "Docker",
    "Lightshot"
)

foreach ($procName in $processesToKill) {
    Stop-ProcessIfRunning -ProcessName $procName
}

# ------------------------------------------------------------
# 8. Create desktop shortcut for VS Code
# ------------------------------------------------------------
Write-Host "Creating VS Code desktop shortcut..." -ForegroundColor Cyan
$vscodePaths = @(
    "$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe",
    "${env:ProgramFiles}\Microsoft VS Code\Code.exe",
    "${env:ProgramFiles(x86)}\Microsoft VS Code\Code.exe"
)

$vscodeExe = $null
foreach ($path in $vscodePaths) {
    if (Test-Path $path) {
        $vscodeExe = $path
        break
    }
}

if ($vscodeExe) {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $shortcutPath = Join-Path $desktop "Visual Studio Code.lnk"
    
    $WScriptShell = New-Object -ComObject WScript.Shell
    $shortcut = $WScriptShell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $vscodeExe
    $shortcut.WorkingDirectory = Split-Path $vscodeExe -Parent
    $shortcut.Save()
    
    Write-Host "VS Code desktop shortcut created at: $shortcutPath" -ForegroundColor Green
} else {
    Write-Host "VS Code executable not found. Shortcut not created." -ForegroundColor Red
}

# ------------------------------------------------------------
# 9. Restart the system
# ------------------------------------------------------------
Write-Host "All tasks completed. Restarting the system in 5 seconds..." -ForegroundColor Green
Start-Sleep -Seconds 5
Restart-Computer -Force
