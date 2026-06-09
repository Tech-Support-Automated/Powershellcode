<#
.SYNOPSIS
    BrightUI Technologies – Complete Automated Setup  v2.0
    Installs Chrome, WinRAR, VS Code, Chrome Remote Desktop, GCPW,
    downloads the logo, creates default user account pictures,
    and restarts the system – fully silent.
.NOTES
    Must be run as Administrator.
    No external scripts – everything is self-contained.
#>

#Requires -RunAsAdministrator

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

# ── Colour helpers (just for console output) ─────────────────────────────────
function Write-Step { param([string]$M)
    Write-Host ''; Write-Host "  [ STEP ] $M" -ForegroundColor Cyan
    Write-Host ('  ' + '-' * 66) -ForegroundColor DarkGray }

function Write-OK   { param([string]$M) Write-Host "    [OK]  $M" -ForegroundColor Green  }
function Write-Warn { param([string]$M) Write-Host "    [!!]  $M" -ForegroundColor Yellow }
function Write-Info { param([string]$M) Write-Host "    [..]  $M" -ForegroundColor White  }

Write-Host ''
Write-Host ('=' * 72) -ForegroundColor Cyan
Write-Host '   BrightUI Technologies — Automated Setup  v2.0' -ForegroundColor Cyan
Write-Host ('=' * 72) -ForegroundColor Cyan
Write-Host ''

# ═════════════════════════════════════════════════════════════════════════════
#  CONFIGURATION
# ═════════════════════════════════════════════════════════════════════════════
$Domain          = 'brightuitechnologies.com'
$EnrollmentToken = 'f8a95d69-7c80-4dcb-b7b6-fb91de01dc57'
$LogoUrl         = 'https://raw.githubusercontent.com/Tech-Support-Automated/Powershellcode/master/logo.png'
$LogoDir         = 'C:\ProgramData\BrightUI\Assets'
$LogoPath        = Join-Path $LogoDir 'brightui_technologies_logo.png'

$ChromeMsiUrl  = 'https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi'
$WinRarUrl     = 'https://www.win-rar.com/fileadmin/winrar-versions/winrar/winrar-x64-701.exe'
$VSCodeUrl     = 'https://update.code.visualstudio.com/latest/win32-x64/stable'
$CRDUrl        = 'https://dl.google.com/edgedl/chrome-remote-desktop/chromeremotedesktophost.msi'
$GcpwUrl       = "https://dl.google.com/tag/s/appguid=%7B32987697-A14E-4B89-84D6-630D5431E831%7D&needsadmin=true&appname=GCPW&etoken=$EnrollmentToken/credentialprovider/gcpwstandaloneenterprise64.exe"

$TempDir = $env:TEMP

# ── Helper: download a file with error handling ───────────────────────────────
function Get-Installer {
    param([string]$Url, [string]$OutPath, [string]$Name, [long]$MinBytes = 102400)
    Write-Info "Downloading $Name..."
    Write-Info "Source : $Url"
    try {
        Invoke-WebRequest -Uri $Url -OutFile $OutPath -UseBasicParsing `
                          -UserAgent 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'
        $size = (Get-Item $OutPath).Length
        if ($size -lt $MinBytes) {
            throw "File too small ($size bytes) – download may have failed."
        }
        Write-OK "$Name downloaded ($([math]::Round($size/1MB,1)) MB)"
        return $true
    } catch {
        Write-Warn "$Name download FAILED: $($_.Exception.Message)"
        return $false
    }
}

# ═════════════════════════════════════════════════════════════════════════════
#  1. INSTALL SOFTWARE (Chrome, WinRAR, VS Code, Chrome Remote Desktop, GCPW)
#     Same as the previously fixed script.ps1 – all silent, no prompt.
# ═════════════════════════════════════════════════════════════════════════════
Write-Step 'Installing Google Chrome'
$ChromeInstalled = $false
$ChromeRegPaths = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe',
                   'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Google Chrome',
                   'HKCU:\SOFTWARE\Google\Chrome\BLBeacon')
foreach ($rp in $ChromeRegPaths) { if (Test-Path -LiteralPath $rp) { $ChromeInstalled = $true; break } }
if (-not $ChromeInstalled) {
    $binPaths = @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
                  "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
                  "$env:LocalAppData\Google\Chrome\Application\chrome.exe")
    foreach ($b in $binPaths) { if (Test-Path -LiteralPath $b) { $ChromeInstalled = $true; break } }
}
if ($ChromeInstalled) {
    Write-OK 'Google Chrome is already installed – skipping.'
} else {
    $msiPath = Join-Path $TempDir 'ChromeEnterprise64.msi'
    if (Get-Installer -Url $ChromeMsiUrl -OutPath $msiPath -Name 'Chrome Enterprise MSI' -MinBytes 1MB) {
        try {
            $p = Start-Process 'msiexec.exe' -ArgumentList "/i `"$msiPath`" /quiet /norestart ALLUSERS=1" -Wait -PassThru -WindowStyle Hidden
            if ($p.ExitCode -eq 0 -or $p.ExitCode -eq 3010 -or $p.ExitCode -eq 1638) {
                Write-OK 'Chrome installed successfully.'
            } else {
                Write-Warn "Chrome installer exited with code $($p.ExitCode)"
            }
        } catch { Write-Warn "Chrome install error: $($_.Exception.Message)" }
        finally { Remove-Item $msiPath -Force -ErrorAction SilentlyContinue }
    }
}

Write-Step 'Installing WinRAR'
$WinRarInstalled = $false
$WinRarRegPaths = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\WinRAR archiver',
                   'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\WinRAR archiver')
foreach ($rp in $WinRarRegPaths) { if (Test-Path -LiteralPath $rp) { $WinRarInstalled = $true; break } }
if (-not $WinRarInstalled) {
    $bins = @("$env:ProgramFiles\WinRAR\WinRAR.exe","${env:ProgramFiles(x86)}\WinRAR\WinRAR.exe")
    foreach ($b in $bins) { if (Test-Path -LiteralPath $b) { $WinRarInstalled = $true; break } }
}
if ($WinRarInstalled) {
    Write-OK 'WinRAR is already installed – skipping.'
} else {
    $exePath = Join-Path $TempDir 'winrar-x64.exe'
    if (Get-Installer -Url $WinRarUrl -OutPath $exePath -Name 'WinRAR') {
        try {
            $p = Start-Process -FilePath $exePath -ArgumentList '/S' -Wait -PassThru -WindowStyle Hidden
            if ($p.ExitCode -eq 0) { Write-OK 'WinRAR installed.' }
            else { Write-Warn "WinRAR installer exit code $($p.ExitCode)" }
        } catch { Write-Warn "WinRAR install error: $($_.Exception.Message)" }
        finally { Remove-Item $exePath -Force -ErrorAction SilentlyContinue }
    }
}

Write-Step 'Installing Visual Studio Code'
$VSCodeInstalled = $false
$VSCodeRegPaths = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{EA457B21-F73E-494C-ACAB-524FDE069978}_is1',
                   'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{EA457B21-F73E-494C-ACAB-524FDE069978}_is1',
                   'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{771FD6B0-FA20-440A-A002-3B3BAC16DC50}_is1')
foreach ($rp in $VSCodeRegPaths) { if (Test-Path -LiteralPath $rp) { $VSCodeInstalled = $true; break } }
if (-not $VSCodeInstalled) {
    $uninstallRoots = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
                        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')
    :search foreach ($root in $uninstallRoots) {
        if (Test-Path $root) {
            $keys = Get-ChildItem -Path $root -ErrorAction SilentlyContinue
            foreach ($k in $keys) {
                $dn = (Get-ItemProperty -Path $k.PSPath -Name 'DisplayName' -ErrorAction SilentlyContinue).DisplayName
                if ($dn -like '*Visual Studio Code*') { $VSCodeInstalled = $true; break search }
            }
        }
    }
}
if (-not $VSCodeInstalled) {
    $binPaths = @("$env:ProgramFiles\Microsoft VS Code\Code.exe","$env:LocalAppData\Programs\Microsoft VS Code\Code.exe")
    foreach ($b in $binPaths) { if (Test-Path -LiteralPath $b) { $VSCodeInstalled = $true; break } }
}
if ($VSCodeInstalled) {
    Write-OK 'Visual Studio Code is already installed – skipping.'
} else {
    $exePath = Join-Path $TempDir 'vscode-system-installer.exe'
    if (Get-Installer -Url $VSCodeUrl -OutPath $exePath -Name 'VS Code' -MinBytes 50MB) {
        try {
            $args = '/VERYSILENT /NORESTART /MERGETASKS=!runcode,addcontextmenufiles,addcontextmenufolders,associatewithfiles,addtopath'
            $p = Start-Process -FilePath $exePath -ArgumentList $args -Wait -PassThru -WindowStyle Hidden
            if ($p.ExitCode -eq 0) { Write-OK 'Visual Studio Code installed.' }
            else { Write-Warn "VS Code installer exit code $($p.ExitCode)" }
        } catch { Write-Warn "VS Code install error: $($_.Exception.Message)" }
        finally { Remove-Item $exePath -Force -ErrorAction SilentlyContinue }
    }
}

Write-Step 'Installing Chrome Remote Desktop Host'
$CRDInstalled = $false
$CRDRegPaths = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{40FF9932-4B3C-4B0F-8B97-51EB88A28B14}',
                 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{40FF9932-4B3C-4B0F-8B97-51EB88A28B14}')
foreach ($rp in $CRDRegPaths) { if (Test-Path -LiteralPath $rp) { $CRDInstalled = $true; break } }
if (-not $CRDInstalled) {
    $uninstallRoots = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')
    :search foreach ($root in $uninstallRoots) {
        if (Test-Path $root) {
            $keys = Get-ChildItem -Path $root -ErrorAction SilentlyContinue
            foreach ($k in $keys) {
                $dn = (Get-ItemProperty -Path $k.PSPath -Name 'DisplayName' -ErrorAction SilentlyContinue).DisplayName
                if ($dn -like '*Chrome Remote Desktop*') { $CRDInstalled = $true; break search }
            }
        }
    }
}
if (-not $CRDInstalled) {
    $bin = "$env:ProgramFiles\Google\Chrome Remote Desktop\CurrentVersion\remoting_host.exe"
    if (Test-Path -LiteralPath $bin) { $CRDInstalled = $true }
}
if ($CRDInstalled) {
    Write-OK 'Chrome Remote Desktop is already installed – skipping.'
} else {
    $msiPath = Join-Path $TempDir 'chromeremotedesktophost.msi'
    if (Get-Installer -Url $CRDUrl -OutPath $msiPath -Name 'Chrome Remote Desktop Host MSI' -MinBytes 10MB) {
        try {
            $p = Start-Process 'msiexec.exe' -ArgumentList "/i `"$msiPath`" /quiet /norestart" -Wait -PassThru
            if ($p.ExitCode -eq 0 -or $p.ExitCode -eq 3010 -or $p.ExitCode -eq 1638) {
                Write-OK 'Chrome Remote Desktop installed.'
            } else { Write-Warn "msiexec exited $($p.ExitCode)" }
        } catch { Write-Warn "Chrome Remote Desktop install error: $($_.Exception.Message)" }
        finally { Remove-Item $msiPath -Force -ErrorAction SilentlyContinue }
    }
}

Write-Step 'Installing GCPW (Google Credential Provider for Windows)'
$GCPWInstalled = $false
$GcpwRegKey = 'HKLM:\Software\Google\GCPW'
if (Test-Path -LiteralPath $GcpwRegKey) {
    $existingDomain = (Get-ItemProperty -Path $GcpwRegKey -Name 'domains_allowed_to_login' -ErrorAction SilentlyContinue).domains_allowed_to_login
    if ($existingDomain) { $GCPWInstalled = $true; Write-OK "GCPW registry key found with domain: $existingDomain" }
}
if (-not $GCPWInstalled) {
    $uninstallRoots = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')
    :search foreach ($root in $uninstallRoots) {
        if (Test-Path $root) {
            $keys = Get-ChildItem -Path $root -ErrorAction SilentlyContinue
            foreach ($k in $keys) {
                $dn = (Get-ItemProperty -Path $k.PSPath -Name 'DisplayName' -ErrorAction SilentlyContinue).DisplayName
                if ($dn -like '*GCPW*' -or $dn -like '*Google Credential*') { $GCPWInstalled = $true; break search }
            }
        }
    }
}
if (-not $GCPWInstalled) {
    $exePath = Join-Path $TempDir 'gcpwstandaloneenterprise64.exe'
    if (Get-Installer -Url $GcpwUrl -OutPath $exePath -Name 'GCPW' -MinBytes 100KB) {
        try {
            $p = Start-Process -FilePath $exePath -ArgumentList '/silent /install' -WindowStyle Hidden -Wait -PassThru
            if ($p.ExitCode -eq 0) { Write-OK 'GCPW installed successfully.' }
            else { Write-Warn "GCPW installer exited $($p.ExitCode) – may still be OK." }
        } catch { Write-Warn "GCPW install error: $($_.Exception.Message)" }
        finally { Remove-Item $exePath -Force -ErrorAction SilentlyContinue }
    }
}

# ── Apply GCPW registry keys (silent) ─────────────────────────────────────────
try {
    & reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Google\CloudManagement" /v "EnrollmentToken" /t REG_SZ /d "$EnrollmentToken" /f | Out-Null
    & reg add "HKEY_LOCAL_MACHINE\Software\Google\GCPW" /v domains_allowed_to_login /t REG_SZ /d "$Domain" /f | Out-Null
    & reg add "HKEY_LOCAL_MACHINE\Software\Google\GCPW" /v validity_period_in_days /t REG_DWORD /d 5 /f | Out-Null
    & reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v dontdisplaylastusername /t REG_DWORD /d 1 /f | Out-Null
    Write-OK 'GCPW registry configured (domain, token, 5-day validity, hide last user).'
} catch {
    Write-Warn 'Failed to write one or more GCPW registry keys.'
}

# ═════════════════════════════════════════════════════════════════════════════
#  2. DOWNLOAD LOGO IMAGE
# ═════════════════════════════════════════════════════════════════════════════
Write-Step 'Downloading logo image'
New-Item -Path $LogoDir -ItemType Directory -Force | Out-Null
try {
    Invoke-WebRequest -Uri $LogoUrl -OutFile $LogoPath -UseBasicParsing
    if (Test-Path $LogoPath) { Write-OK "Logo saved: $LogoPath" }
    else { Write-Warn "Logo file not created." }
} catch {
    Write-Warn "Failed to download logo: $($_.Exception.Message)"
    exit 1
}

# ═════════════════════════════════════════════════════════════════════════════
#  3. GENERATE DEFAULT USER ACCOUNT PICTURES
# ═════════════════════════════════════════════════════════════════════════════
Write-Step 'Creating default user account pictures from logo'
Add-Type -AssemblyName System.Drawing

$DestFolder = 'C:\ProgramData\Microsoft\User Account Pictures'
New-Item -Path $DestFolder -ItemType Directory -Force | Out-Null

$Sizes = @(32, 40, 48, 96, 192, 200, 240, 448)
foreach ($Size in $Sizes) {
    try {
        $Bitmap   = [System.Drawing.Image]::FromFile($LogoPath)
        $Resized  = New-Object System.Drawing.Bitmap $Size, $Size
        $Graphics = [System.Drawing.Graphics]::FromImage($Resized)
        $Graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $Graphics.DrawImage($Bitmap, 0, 0, $Size, $Size)
        $Resized.Save((Join-Path $DestFolder "user-$Size.png"), [System.Drawing.Imaging.ImageFormat]::Png)
        $Graphics.Dispose(); $Resized.Dispose(); $Bitmap.Dispose()
    } catch {
        Write-Warn "Failed creating size $Size – $_"
    }
}

# Copy main user.png
Copy-Item $LogoPath (Join-Path $DestFolder 'user.png') -Force -ErrorAction SilentlyContinue

# Enable default account picture policy
$PolicyPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
if (-not (Test-Path $PolicyPath)) { New-Item -Path $PolicyPath -Force | Out-Null }
New-ItemProperty -Path $PolicyPath -Name 'UseDefaultTile' -Value 1 -PropertyType DWord -Force | Out-Null

# Remove cached account pictures for current user
$AccountPictures = "$env:APPDATA\Microsoft\Windows\AccountPictures"
if (Test-Path $AccountPictures) {
    Remove-Item "$AccountPictures\*" -Force -Recurse -ErrorAction SilentlyContinue
}

# Refresh Explorer to apply
Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Process explorer.exe

Write-Host ''
Write-Host 'SUCCESS: BrightUI default account picture installed.' -ForegroundColor Green
Write-Host 'IMPORTANT: Sign out and sign back in (or restart Windows).' -ForegroundColor Yellow
Write-Host ''
Write-Host 'Verify files exist in:' -ForegroundColor Cyan
Write-Host "C:\ProgramData\Microsoft\User Account Pictures"

# ═════════════════════════════════════════════════════════════════════════════
#  4. FINAL SUMMARY & AUTO RESTART
# ═════════════════════════════════════════════════════════════════════════════
$sep = '=' * 72
Write-Host ''
Write-Host $sep -ForegroundColor Cyan
Write-Host '   Setup Complete – BrightUI Technologies  v2.0' -ForegroundColor Green
Write-Host $sep -ForegroundColor Cyan
Write-Host ''
Write-Host '  Software Installed :  Chrome, WinRAR, VS Code, Chrome Remote Desktop, GCPW'
Write-Host "  GCPW Domain        :  $Domain"
Write-Host '  Logo Downloaded    :  ' -NoNewline -ForegroundColor White
Write-Host (Test-Path $LogoPath ? 'Yes' : 'No')
Write-Host '  Account Pictures   :  ' -NoNewline -ForegroundColor White
Write-Host (Test-Path "$DestFolder\user.png" ? 'Yes' : 'No')
Write-Host ''
Write-Host '  System will restart in 5 seconds – no action required.' -ForegroundColor Magenta
Write-Host $sep -ForegroundColor Cyan

Start-Sleep -Seconds 5
Restart-Computer -Force
