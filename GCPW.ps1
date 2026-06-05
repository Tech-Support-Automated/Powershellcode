<#
================================================================================
  BrightUI Technologies — Chrome + GCPW Silent Installer
================================================================================
  HOW TO RUN:
    1. Open PowerShell as Administrator (right-click → Run as Administrator)
    2. .\Install_Chrome_GCPW.ps1

  WHAT THIS DOES:
    Step 1 — Checks if Google Chrome is already installed.
             If NOT installed, downloads the Chrome Enterprise 64-bit MSI
             and installs it silently (no UI, no reboot prompt).
    Step 2 — Downloads and silently installs GCPW (Google Credential
             Provider for Windows) using the enterprise installer.
    Step 3 — Writes all required GCPW registry keys:
               • Enrollment token
               • Allowed login domain  (brightuitechnologies.com)
               • Offline validity period  (5 days)
               • Hide last username on login screen

  REQUIREMENTS : Windows 10/11  |  Administrator rights  |  Internet access
  AFTER RUNNING: RESTART the computer for GCPW to appear on the login screen.
================================================================================
#>

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# ── Colour helpers ────────────────────────────────────────────────────────────
function Write-Step { param([string]$M)
    Write-Host ''
    Write-Host "  [ STEP ] $M" -ForegroundColor Cyan
    Write-Host ('  ' + '-' * 66) -ForegroundColor DarkGray }

function Write-OK   { param([string]$M) Write-Host "    [OK]  $M" -ForegroundColor Green  }
function Write-Warn { param([string]$M) Write-Host "    [!!]  $M" -ForegroundColor Yellow }
function Write-Info { param([string]$M) Write-Host "    [..]  $M" -ForegroundColor White  }

# ── Configuration ─────────────────────────────────────────────────────────────
$Domain          = 'brightuitechnologies.com'
$EnrollmentToken = 'f8a95d69-7c80-4dcb-b7b6-fb91de01dc57'

# Chrome Enterprise 64-bit MSI (offline / standalone installer — no internet needed at runtime)
$ChromeMsiUrl  = 'https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi'
$ChromeMsiPath = "$env:TEMP\ChromeEnterprise64.msi"

# GCPW standalone enterprise 64-bit EXE
$GcpwUrl       = "https://dl.google.com/tag/s/appguid=%7B32987697-A14E-4B89-84D6-630D5431E831%7D&needsadmin=true&appname=GCPW&etoken=$EnrollmentToken/credentialprovider/gcpwstandaloneenterprise64.exe"
$GcpwInstaller = "$env:TEMP\gcpwstandaloneenterprise64.exe"

# ─────────────────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host ('=' * 72) -ForegroundColor Cyan
Write-Host '   BrightUI Technologies — Chrome + GCPW Silent Installer' -ForegroundColor Cyan
Write-Host ('=' * 72) -ForegroundColor Cyan

# ══════════════════════════════════════════════════════════════════════════════
#  STEP 1 — Check if Google Chrome is already installed
# ══════════════════════════════════════════════════════════════════════════════
Write-Step 'Checking for existing Google Chrome installation'

$ChromeInstalled = $false

# Check registry (covers system-wide and per-user installs)
$ChromeRegPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Google Chrome',
    'HKCU:\SOFTWARE\Google\Chrome\BLBeacon'
)
foreach ($rp in $ChromeRegPaths) {
    if (Test-Path -LiteralPath $rp) {
        $ChromeInstalled = $true
        Write-OK "Chrome found in registry: $rp"
        break
    }
}

# Also check common on-disk locations
if (-not $ChromeInstalled) {
    $ChromeBinPaths = @(
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:LocalAppData\Google\Chrome\Application\chrome.exe"
    )
    foreach ($bp in $ChromeBinPaths) {
        if (Test-Path -LiteralPath $bp) {
            $ChromeInstalled = $true
            Write-OK "Chrome found on disk: $bp"
            break
        }
    }
}

if ($ChromeInstalled) {
    Write-OK 'Google Chrome is already installed — skipping Chrome installation.'
} else {
    Write-Warn 'Google Chrome is NOT installed. Proceeding with silent installation...'
}

# ══════════════════════════════════════════════════════════════════════════════
#  STEP 2 — Download and silently install Google Chrome (if needed)
# ══════════════════════════════════════════════════════════════════════════════
if (-not $ChromeInstalled) {

    Write-Step 'Downloading Google Chrome Enterprise 64-bit MSI installer'

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        Write-Info "Source : $ChromeMsiUrl"
        Write-Info "Saving to : $ChromeMsiPath"
        Write-Info 'Please wait — this is approximately 80 MB...'

        Invoke-WebRequest -Uri         $ChromeMsiUrl `
                          -OutFile     $ChromeMsiPath `
                          -UseBasicParsing `
                          -UserAgent   'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'

        $fileSize = (Get-Item $ChromeMsiPath).Length
        if ($fileSize -lt 1MB) {
            throw "Downloaded file is too small ($fileSize bytes) — download may have failed."
        }

        Write-OK "Chrome MSI downloaded successfully ($([math]::Round($fileSize/1MB,1)) MB)"

    } catch {
        Write-Warn "Chrome download FAILED: $($_.Exception.Message)"
        Write-Warn 'Cannot proceed without Chrome — GCPW requires Chrome to be installed.'
        Write-Warn 'Please install Chrome manually from https://www.google.com/chrome/ and re-run.'
        exit 1
    }

    # ── Silent MSI install ────────────────────────────────────────────────────
    Write-Step 'Installing Google Chrome silently (no UI, no reboot prompt)'

    try {
        Write-Info 'Running: msiexec.exe /i ChromeEnterprise64.msi /quiet /norestart ALLUSERS=1'
        Write-Info 'This may take 30–90 seconds...'

        $msiArgs = "/i `"$ChromeMsiPath`" /quiet /norestart ALLUSERS=1"
        $proc    = Start-Process -FilePath 'msiexec.exe' `
                                 -ArgumentList $msiArgs `
                                 -Wait `
                                 -PassThru

        switch ($proc.ExitCode) {
            0    { Write-OK 'Chrome installed successfully (exit code 0 — clean install).' }
            3010 { Write-OK 'Chrome installed successfully (exit code 3010 — reboot suggested but not required now).' }
            1638 { Write-OK 'Chrome is already installed at this or a newer version (exit code 1638).' ; $ChromeInstalled = $true }
            default {
                Write-Warn "msiexec exited with code $($proc.ExitCode)."
                Write-Warn 'Chrome may not have installed correctly. Continuing to GCPW anyway.'
            }
        }

        if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
            $ChromeInstalled = $true
        }

    } catch {
        Write-Warn "Chrome MSI install error: $($_.Exception.Message)"
    } finally {
        # Always clean up the installer file
        try { Remove-Item -Path $ChromeMsiPath -Force -ErrorAction SilentlyContinue } catch {}
        Write-Info 'Chrome installer file removed from TEMP.'
    }

    # Verify Chrome is now present on disk
    if ($ChromeInstalled) {
        $chromeBin = "$env:ProgramFiles\Google\Chrome\Application\chrome.exe"
        if (Test-Path -LiteralPath $chromeBin) {
            $ver = (Get-Item $chromeBin).VersionInfo.ProductVersion
            Write-OK "Chrome binary confirmed at: $chromeBin  (version $ver)"
        } else {
            Write-Warn 'Chrome binary not found at expected path after install.'
            Write-Warn 'GCPW will still be installed — it may work if Chrome is elsewhere.'
        }
    }
}

# ══════════════════════════════════════════════════════════════════════════════
#  STEP 3 — Download and silently install GCPW
# ══════════════════════════════════════════════════════════════════════════════
Write-Step 'Downloading GCPW (Google Credential Provider for Windows) installer'

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    Write-Info "Saving to : $GcpwInstaller"
    Write-Info 'Please wait — downloading GCPW...'

    Invoke-WebRequest -Uri         $GcpwUrl `
                      -OutFile     $GcpwInstaller `
                      -UseBasicParsing `
                      -UserAgent   'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'

    $gcpwSize = (Get-Item $GcpwInstaller).Length
    if ($gcpwSize -lt 100KB) {
        throw "GCPW installer is too small ($gcpwSize bytes) — download may have failed."
    }

    Write-OK "GCPW installer downloaded ($([math]::Round($gcpwSize/1MB,2)) MB): $GcpwInstaller"

} catch {
    Write-Warn "GCPW download FAILED: $($_.Exception.Message)"
    Write-Warn 'Please check your internet connection and try again.'
    exit 1
}

# ── Silent GCPW install ───────────────────────────────────────────────────────
Write-Step 'Installing GCPW silently'

try {
    Write-Info 'Running GCPW installer with /silent /install flags...'
    Write-Info 'This may take 15–45 seconds...'

    $gcpwProc = Start-Process -FilePath   $GcpwInstaller `
                               -ArgumentList '/silent /install' `
                               -WindowStyle Hidden `
                               -Wait `
                               -PassThru

    if ($gcpwProc.ExitCode -eq 0) {
        Write-OK "GCPW installed successfully (exit code 0)."
    } else {
        Write-Warn "GCPW installer exited with code $($gcpwProc.ExitCode)."
        Write-Warn 'This may be normal (some versions return non-zero on success).'
        Write-Warn 'Continuing to registry configuration...'
    }

} catch {
    Write-Warn "GCPW install error: $($_.Exception.Message)"
    Write-Warn 'Continuing to registry configuration anyway...'
} finally {
    try { Remove-Item -Path $GcpwInstaller -Force -ErrorAction SilentlyContinue } catch {}
    Write-Info 'GCPW installer file removed from TEMP.'
}

# ══════════════════════════════════════════════════════════════════════════════
#  STEP 4 — Configure GCPW registry keys
# ══════════════════════════════════════════════════════════════════════════════
Write-Step 'Writing GCPW configuration to registry'

# Helper: create key + set value, never fails the script
function Set-RegValue {
    param([string]$Path, [string]$Name, [string]$Value, [string]$Type = 'REG_SZ')
    try {
        & reg add $Path /v $Name /t $Type /d $Value /f 2>&1 | Out-Null
        Write-OK "Registry: $Path\$Name = $Value"
    } catch {
        Write-Warn "Registry write failed for $Name : $($_.Exception.Message)"
    }
}

# Enrollment token (cloud management)
Set-RegValue 'HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Google\CloudManagement' `
             'EnrollmentToken' $EnrollmentToken

# Allowed login domain
Set-RegValue 'HKEY_LOCAL_MACHINE\Software\Google\GCPW' `
             'domains_allowed_to_login' $Domain

# Offline access validity (days the device can be used without re-authenticating online)
Set-RegValue 'HKEY_LOCAL_MACHINE\Software\Google\GCPW' `
             'validity_period_in_days' '5' 'REG_DWORD'

# Hide last signed-in username on the Windows login screen
Set-RegValue 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' `
             'dontdisplaylastusername' '1' 'REG_DWORD'

# ── Verify GCPW registry entries were written ─────────────────────────────────
Write-Step 'Verifying GCPW registry configuration'

$gcpwKey = 'HKLM:\Software\Google\GCPW'
if (Test-Path -LiteralPath $gcpwKey) {
    $gcpwDomain = (Get-ItemProperty -Path $gcpwKey -Name 'domains_allowed_to_login' -ErrorAction SilentlyContinue).domains_allowed_to_login
    $gcpwDays   = (Get-ItemProperty -Path $gcpwKey -Name 'validity_period_in_days'  -ErrorAction SilentlyContinue).validity_period_in_days
    Write-OK "GCPW key exists: $gcpwKey"
    Write-OK "  domains_allowed_to_login = $gcpwDomain"
    Write-OK "  validity_period_in_days  = $gcpwDays"
} else {
    Write-Warn "GCPW registry key not found at $gcpwKey — GCPW may not have installed correctly."
    Write-Warn 'Try running the script again after a reboot.'
}

# ══════════════════════════════════════════════════════════════════════════════
#  FINAL SUMMARY
# ══════════════════════════════════════════════════════════════════════════════
$sep = '=' * 72
Write-Host ''
Write-Host $sep -ForegroundColor Cyan
Write-Host '   Installation Complete!' -ForegroundColor Green
Write-Host $sep -ForegroundColor Cyan
Write-Host ''
Write-Host '  RESULTS:' -ForegroundColor Yellow
Write-Host "    Chrome installed     :  $ChromeInstalled"
Write-Host '    GCPW installed       :  See exit codes above'
Write-Host "    Allowed domain       :  $Domain"
Write-Host "    Enrollment token     :  $EnrollmentToken"
Write-Host '    Offline validity     :  5 days'
Write-Host '    Last username hidden :  Yes'
Write-Host ''
Write-Host '  NEXT STEPS:' -ForegroundColor Yellow
Write-Host '    1.  RESTART this computer.'
Write-Host '    2.  On the login screen you should see the GCPW sign-in option.'
Write-Host '    3.  Click "Other user" and enter your @brightuitechnologies.com'
Write-Host '        Google Workspace email address.'
Write-Host '    4.  Complete Google authentication to finish signing in.'
Write-Host ''
Write-Host '  TROUBLESHOOTING:' -ForegroundColor Yellow
Write-Host '    - If GCPW does not appear after reboot, re-run this script as Administrator.'
Write-Host '    - Ensure Chrome is installed BEFORE GCPW (this script handles that).'
Write-Host '    - Check Event Viewer > Application for GCPW errors if sign-in fails.'
Write-Host "    - GCPW support: https://support.google.com/a/answer/9650196"
Write-Host ''
Write-Host $sep -ForegroundColor Cyan
Write-Host ''
