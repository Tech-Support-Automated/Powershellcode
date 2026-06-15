<#
================================================================================
  BrightUI Technologies — Silent Software Installer (Lightshot EXCLUDED)
================================================================================
  HOW TO RUN:
    1. Open PowerShell as Administrator (right-click → Run as Administrator)
    2. .\Install_BrightUI_Software.ps1

  WHAT THIS INSTALLS (silently, skips if already installed):
    1. Google Chrome          — Enterprise 64-bit MSI
    2. WinRAR                 — 64-bit EXE (silent)
    3. Visual Studio Code     — System installer (silent)
    4. Chrome Remote Desktop  — Host MSI (silent)
    5. GCPW                   — Google Credential Provider for Windows

  GCPW REGISTRY KEYS WRITTEN:
    • Enrollment token
    • Allowed login domain  (brightuitechnologies.com)
    • Offline validity period  (5 days)
    • Hide last username on login screen

  REQUIREMENTS : Windows 10/11  |  Administrator rights  |  Internet access
  AFTER RUNNING: RESTART the computer for GCPW to appear on the login screen.
================================================================================
#>

# ── FIX: Disable QuickEdit mode to prevent console freeze on mouse click ──────
if ($Host.Name -eq 'ConsoleHost') {
    try {
        Add-Type -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)]
public static extern IntPtr GetStdHandle(int nStdHandle);

[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);

[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
'@ -Name 'Kernel32' -Namespace 'Win32' -ErrorAction Stop

        $handle = [Win32.Kernel32]::GetStdHandle(-10)
        $mode = 0
        if ([Win32.Kernel32]::GetConsoleMode($handle, [ref]$mode)) {
            $mode = $mode -band -bnot 0x40   # Clear QuickEdit flag (0x40)
            $mode = $mode -bor 0x80          # Set ExtendedFlags flag (required)
            [Win32.Kernel32]::SetConsoleMode($handle, $mode) | Out-Null
        }
    } catch {
        # If disabling fails for any reason, continue anyway
    }
}
# ── End of QuickEdit fix ──────────────────────────────────────────────────────

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
function Write-Skip { param([string]$M) Write-Host "    [--]  $M" -ForegroundColor DarkCyan }

# ── Enforce TLS 1.2 globally ──────────────────────────────────────────────────
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ── Configuration ─────────────────────────────────────────────────────────────
$Domain          = 'brightuitechnologies.com'
$EnrollmentToken = 'f8a95d69-7c80-4dcb-b7b6-fb91de01dc57'

# ── Download URLs (Lightshot URL completely removed) ──────────────────────────
$ChromeMsiUrl  = 'https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi'
$WinRarUrl     = 'https://www.win-rar.com/fileadmin/winrar-versions/winrar/winrar-x64-701.exe'
$VSCodeUrl     = 'https://update.code.visualstudio.com/latest/win32-x64/stable'
$CRDUrl        = 'https://dl.google.com/edgedl/chrome-remote-desktop/chromeremotedesktophost.msi'
$GcpwUrl       = "https://dl.google.com/tag/s/appguid=%7B32987697-A14E-4B89-84D6-630D5431E831%7D&needsadmin=true&appname=GCPW&etoken=$EnrollmentToken/credentialprovider/gcpwstandaloneenterprise64.exe"

# ── Temp installer paths ──────────────────────────────────────────────────────
$ChromeMsiPath  = "$env:TEMP\ChromeEnterprise64.msi"
$WinRarPath     = "$env:TEMP\winrar-x64.exe"
$VSCodePath     = "$env:TEMP\vscode-system-installer.exe"
$CRDPath        = "$env:TEMP\chromeremotedesktophost.msi"
$GcpwInstaller  = "$env:TEMP\gcpwstandaloneenterprise64.exe"

# ── Result tracking (Lightshot entry removed) ─────────────────────────────────
$Results = [ordered]@{
    'Google Chrome'          = 'Not attempted'
    'WinRAR'                 = 'Not attempted'
    'Visual Studio Code'     = 'Not attempted'
    'Chrome Remote Desktop'  = 'Not attempted'
    'GCPW'                   = 'Not attempted'
}

# ── Helper: download a file with error handling ───────────────────────────────
function Get-Installer {
    param(
        [string]$Url,
        [string]$OutPath,
        [string]$Name,
        [long]$MinBytes = 102400   # 100 KB default minimum
    )
    Write-Info "Downloading $Name..."
    Write-Info "Source : $Url"
    try {
        Invoke-WebRequest -Uri $Url -OutFile $OutPath -UseBasicParsing `
                          -UserAgent 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'
        $size = (Get-Item $OutPath).Length
        if ($size -lt $MinBytes) {
            throw "File too small ($size bytes) — download may have failed."
        }
        Write-OK "$Name downloaded ($([math]::Round($size/1MB,1)) MB)"
        return $true
    } catch {
        Write-Warn "$Name download FAILED: $($_.Exception.Message)"
        return $false
    }
}

# ── Helper: cleanup temp file silently ───────────────────────────────────────
function Remove-TempFile { param([string]$Path)
    try { Remove-Item -Path $Path -Force -ErrorAction SilentlyContinue } catch {}
}

# ═════════════════════════════════════════════════════════════════════════════
#  BANNER
# ═════════════════════════════════════════════════════════════════════════════
Write-Host ''
Write-Host ('=' * 72) -ForegroundColor Cyan
Write-Host '   BrightUI Technologies — Silent Software Installer' -ForegroundColor Cyan
Write-Host ('=' * 72) -ForegroundColor Cyan
Write-Host ''
Write-Host '  Softwares : Chrome, WinRAR, VS Code, Chrome Remote Desktop, GCPW' -ForegroundColor White
Write-Host '  Mode      : Silent install — already-installed apps are SKIPPED' -ForegroundColor White
Write-Host ''

# ═════════════════════════════════════════════════════════════════════════════
#  STEP 1 — GOOGLE CHROME
# ═════════════════════════════════════════════════════════════════════════════
Write-Step 'Google Chrome — Check & Install'

$ChromeInstalled = $false

$ChromeRegPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Google Chrome',
    'HKCU:\SOFTWARE\Google\Chrome\BLBeacon'
)
foreach ($rp in $ChromeRegPaths) {
    if (Test-Path -LiteralPath $rp) { $ChromeInstalled = $true; break }
}

if (-not $ChromeInstalled) {
    $ChromeBinPaths = @(
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:LocalAppData\Google\Chrome\Application\chrome.exe"
    )
    foreach ($bp in $ChromeBinPaths) {
        if (Test-Path -LiteralPath $bp) { $ChromeInstalled = $true; break }
    }
}

if ($ChromeInstalled) {
    Write-Skip 'Google Chrome is already installed — skipping.'
    $Results['Google Chrome'] = 'Already installed (skipped)'
} else {
    Write-Info 'Chrome not found. Downloading and installing...'
    if (Get-Installer -Url $ChromeMsiUrl -OutPath $ChromeMsiPath -Name 'Chrome Enterprise MSI' -MinBytes 1MB) {
        try {
            Write-Info 'Running silent MSI install...'
            $p = Start-Process 'msiexec.exe' `
                     -ArgumentList "/i `"$ChromeMsiPath`" /quiet /norestart ALLUSERS=1" `
                     -Wait -PassThru
            switch ($p.ExitCode) {
                0    { Write-OK 'Chrome installed successfully.';           $ChromeInstalled = $true; $Results['Google Chrome'] = 'Installed OK' }
                3010 { Write-OK 'Chrome installed (reboot suggested).';     $ChromeInstalled = $true; $Results['Google Chrome'] = 'Installed OK (reboot suggested)' }
                1638 { Write-Skip 'Chrome already at this/newer version.';  $ChromeInstalled = $true; $Results['Google Chrome'] = 'Already installed (skipped)' }
                default {
                    Write-Warn "msiexec exited $($p.ExitCode). Chrome may not have installed."
                    $Results['Google Chrome'] = "Install warning (exit $($p.ExitCode))"
                }
            }
        } catch {
            Write-Warn "Chrome install error: $($_.Exception.Message)"
            $Results['Google Chrome'] = 'Install error'
        } finally {
            Remove-TempFile $ChromeMsiPath
        }
    } else {
        $Results['Google Chrome'] = 'Download failed'
    }
}

# ═════════════════════════════════════════════════════════════════════════════
#  STEP 2 — WINRAR
# ═════════════════════════════════════════════════════════════════════════════
Write-Step 'WinRAR — Check & Install'

$WinRarInstalled = $false

$WinRarRegPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\WinRAR archiver',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\WinRAR archiver'
)
foreach ($rp in $WinRarRegPaths) {
    if (Test-Path -LiteralPath $rp) { $WinRarInstalled = $true; break }
}

if (-not $WinRarInstalled) {
    $WinRarBin = @(
        "$env:ProgramFiles\WinRAR\WinRAR.exe",
        "${env:ProgramFiles(x86)}\WinRAR\WinRAR.exe"
    )
    foreach ($b in $WinRarBin) {
        if (Test-Path -LiteralPath $b) { $WinRarInstalled = $true; break }
    }
}

if ($WinRarInstalled) {
    Write-Skip 'WinRAR is already installed — skipping.'
    $Results['WinRAR'] = 'Already installed (skipped)'
} else {
    Write-Info 'WinRAR not found. Downloading and installing...'
    if (Get-Installer -Url $WinRarUrl -OutPath $WinRarPath -Name 'WinRAR') {
        try {
            Write-Info 'Running WinRAR silent install (/S flag)...'
            $p = Start-Process -FilePath $WinRarPath -ArgumentList '/S' -Wait -PassThru
            if ($p.ExitCode -eq 0) {
                Write-OK 'WinRAR installed successfully.'
                $Results['WinRAR'] = 'Installed OK'
            } else {
                Write-Warn "WinRAR installer exited with code $($p.ExitCode)."
                $Results['WinRAR'] = "Install warning (exit $($p.ExitCode))"
            }
        } catch {
            Write-Warn "WinRAR install error: $($_.Exception.Message)"
            $Results['WinRAR'] = 'Install error'
        } finally {
            Remove-TempFile $WinRarPath
        }
    } else {
        $Results['WinRAR'] = 'Download failed'
    }
}

# ═════════════════════════════════════════════════════════════════════════════
#  STEP 3 — VISUAL STUDIO CODE
# ═════════════════════════════════════════════════════════════════════════════
Write-Step 'Visual Studio Code — Check & Install'

$VSCodeInstalled = $false

$VSCodeRegPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{EA457B21-F73E-494C-ACAB-524FDE069978}_is1',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{EA457B21-F73E-494C-ACAB-524FDE069978}_is1',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{771FD6B0-FA20-440A-A002-3B3BAC16DC50}_is1'
)
foreach ($rp in $VSCodeRegPaths) {
    if (Test-Path -LiteralPath $rp) { $VSCodeInstalled = $true; break }
}

if (-not $VSCodeInstalled) {
    $uninstallRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($root in $uninstallRoots) {
        if (Test-Path $root) {
            $keys = Get-ChildItem -Path $root -ErrorAction SilentlyContinue
            foreach ($k in $keys) {
                $dn = (Get-ItemProperty -Path $k.PSPath -Name 'DisplayName' -ErrorAction SilentlyContinue).DisplayName
                if ($dn -like '*Visual Studio Code*') { $VSCodeInstalled = $true; break }
            }
        }
        if ($VSCodeInstalled) { break }
    }
}

if (-not $VSCodeInstalled) {
    $vscodeBin = @(
        "$env:ProgramFiles\Microsoft VS Code\Code.exe",
        "$env:LocalAppData\Programs\Microsoft VS Code\Code.exe"
    )
    foreach ($b in $vscodeBin) {
        if (Test-Path -LiteralPath $b) { $VSCodeInstalled = $true; break }
    }
}

if ($VSCodeInstalled) {
    Write-Skip 'Visual Studio Code is already installed — skipping.'
    $Results['Visual Studio Code'] = 'Already installed (skipped)'
} else {
    Write-Info 'VS Code not found. Downloading and installing...'
    if (Get-Installer -Url $VSCodeUrl -OutPath $VSCodePath -Name 'VS Code' -MinBytes 50MB) {
        try {
            Write-Info 'Running VS Code silent install...'
            $vscArgs = '/VERYSILENT /NORESTART /MERGETASKS=!runcode,addcontextmenufiles,addcontextmenufolders,associatewithfiles,addtopath'
            $p = Start-Process -FilePath $VSCodePath -ArgumentList $vscArgs -Wait -PassThru
            if ($p.ExitCode -eq 0) {
                Write-OK 'Visual Studio Code installed successfully.'
                $Results['Visual Studio Code'] = 'Installed OK'
            } else {
                Write-Warn "VS Code installer exited with code $($p.ExitCode)."
                $Results['Visual Studio Code'] = "Install warning (exit $($p.ExitCode))"
            }
        } catch {
            Write-Warn "VS Code install error: $($_.Exception.Message)"
            $Results['Visual Studio Code'] = 'Install error'
        } finally {
            Remove-TempFile $VSCodePath
        }
    } else {
        $Results['Visual Studio Code'] = 'Download failed'
    }
}

# ═════════════════════════════════════════════════════════════════════════════
#  STEP 4 — CHROME REMOTE DESKTOP HOST
# ═════════════════════════════════════════════════════════════════════════════
Write-Step 'Chrome Remote Desktop Host — Check & Install'

$CRDInstalled = $false

$CRDRegPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{40FF9932-4B3C-4B0F-8B97-51EB88A28B14}',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{40FF9932-4B3C-4B0F-8B97-51EB88A28B14}'
)
foreach ($rp in $CRDRegPaths) {
    if (Test-Path -LiteralPath $rp) { $CRDInstalled = $true; break }
}

if (-not $CRDInstalled) {
    $uninstallRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($root in $uninstallRoots) {
        if (Test-Path $root) {
            $keys = Get-ChildItem -Path $root -ErrorAction SilentlyContinue
            foreach ($k in $keys) {
                $dn = (Get-ItemProperty -Path $k.PSPath -Name 'DisplayName' -ErrorAction SilentlyContinue).DisplayName
                if ($dn -like '*Chrome Remote Desktop*') { $CRDInstalled = $true; break }
            }
        }
        if ($CRDInstalled) { break }
    }
}

if (-not $CRDInstalled) {
    $crdBin = "$env:ProgramFiles\Google\Chrome Remote Desktop\CurrentVersion\remoting_host.exe"
    if (Test-Path -LiteralPath $crdBin) { $CRDInstalled = $true }
}

if ($CRDInstalled) {
    Write-Skip 'Chrome Remote Desktop is already installed — skipping.'
    $Results['Chrome Remote Desktop'] = 'Already installed (skipped)'
} else {
    Write-Info 'Chrome Remote Desktop not found. Downloading and installing...'
    if (Get-Installer -Url $CRDUrl -OutPath $CRDPath -Name 'Chrome Remote Desktop Host MSI' -MinBytes 10MB) {
        try {
            Write-Info 'Running Chrome Remote Desktop silent MSI install...'
            $p = Start-Process 'msiexec.exe' `
                     -ArgumentList "/i `"$CRDPath`" /quiet /norestart" `
                     -Wait -PassThru
            switch ($p.ExitCode) {
                0    { Write-OK 'Chrome Remote Desktop installed successfully.'; $Results['Chrome Remote Desktop'] = 'Installed OK' }
                3010 { Write-OK 'Chrome Remote Desktop installed (reboot suggested).'; $Results['Chrome Remote Desktop'] = 'Installed OK (reboot suggested)' }
                1638 { Write-Skip 'Chrome Remote Desktop already at this/newer version.'; $Results['Chrome Remote Desktop'] = 'Already installed (skipped)' }
                default {
                    Write-Warn "msiexec exited $($p.ExitCode)."
                    $Results['Chrome Remote Desktop'] = "Install warning (exit $($p.ExitCode))"
                }
            }
        } catch {
            Write-Warn "Chrome Remote Desktop install error: $($_.Exception.Message)"
            $Results['Chrome Remote Desktop'] = 'Install error'
        } finally {
            Remove-TempFile $CRDPath
        }
    } else {
        $Results['Chrome Remote Desktop'] = 'Download failed'
    }
}

# ═════════════════════════════════════════════════════════════════════════════
#  STEP 5 — GCPW (Google Credential Provider for Windows)
# ═════════════════════════════════════════════════════════════════════════════
Write-Step 'GCPW — Check & Install'

$GCPWInstalled = $false

$GcpwRegKey = 'HKLM:\Software\Google\GCPW'
if (Test-Path -LiteralPath $GcpwRegKey) {
    $existingDomain = (Get-ItemProperty -Path $GcpwRegKey -Name 'domains_allowed_to_login' -ErrorAction SilentlyContinue).domains_allowed_to_login
    if ($existingDomain) {
        $GCPWInstalled = $true
        Write-Skip "GCPW registry key found with domain: $existingDomain"
    }
}

if (-not $GCPWInstalled) {
    $uninstallRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($root in $uninstallRoots) {
        if (Test-Path $root) {
            $keys = Get-ChildItem -Path $root -ErrorAction SilentlyContinue
            foreach ($k in $keys) {
                $dn = (Get-ItemProperty -Path $k.PSPath -Name 'DisplayName' -ErrorAction SilentlyContinue).DisplayName
                if ($dn -like '*GCPW*' -or $dn -like '*Google Credential*') { $GCPWInstalled = $true; break }
            }
        }
        if ($GCPWInstalled) { break }
    }
}

if ($GCPWInstalled) {
    Write-Skip 'GCPW appears already installed — will still re-apply registry configuration.'
    $Results['GCPW'] = 'Already installed — registry updated'
} else {
    Write-Info 'GCPW not found. Downloading and installing...'
    if (Get-Installer -Url $GcpwUrl -OutPath $GcpwInstaller -Name 'GCPW' -MinBytes 100KB) {
        try {
            Write-Info 'Running GCPW silent install...'
            $p = Start-Process -FilePath $GcpwInstaller `
                               -ArgumentList '/silent /install' `
                               -WindowStyle Hidden -Wait -PassThru
            if ($p.ExitCode -eq 0) {
                Write-OK "GCPW installed successfully (exit 0)."
                $Results['GCPW'] = 'Installed OK'
            } else {
                Write-Warn "GCPW installer exited $($p.ExitCode) — may still be OK. Continuing..."
                $Results['GCPW'] = "Installed (exit $($p.ExitCode)) — check registry below"
            }
        } catch {
            Write-Warn "GCPW install error: $($_.Exception.Message)"
            $Results['GCPW'] = 'Install error'
        } finally {
            Remove-TempFile $GcpwInstaller
        }
    } else {
        $Results['GCPW'] = 'Download failed'
    }
}

# ═════════════════════════════════════════════════════════════════════════════
#  STEP 6 — GCPW Registry Configuration
# ═════════════════════════════════════════════════════════════════════════════
Write-Step 'Writing GCPW configuration to registry'

function Set-RegValue {
    param([string]$Path, [string]$Name, [string]$Value, [string]$Type = 'REG_SZ')
    try {
        & reg add $Path /v $Name /t $Type /d $Value /f 2>&1 | Out-Null
        Write-OK "Registry: $Path\$Name = $Value"
    } catch {
        Write-Warn "Registry write failed for ${Name}: $($_.Exception.Message)"
    }
}

# Enrollment token (cloud management)
Set-RegValue 'HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Google\CloudManagement' `
             'EnrollmentToken' $EnrollmentToken

# Allowed login domain
Set-RegValue 'HKEY_LOCAL_MACHINE\Software\Google\GCPW' `
             'domains_allowed_to_login' $Domain

# Offline access validity (days)
Set-RegValue 'HKEY_LOCAL_MACHINE\Software\Google\GCPW' `
             'validity_period_in_days' '5' 'REG_DWORD'

# Hide last signed-in username on the Windows login screen
Set-RegValue 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' `
             'dontdisplaylastusername' '1' 'REG_DWORD'

# ── Verify GCPW registry ──────────────────────────────────────────────────────
Write-Step 'Verifying GCPW registry configuration'

if (Test-Path -LiteralPath $GcpwRegKey) {
    $gcpwDomain = (Get-ItemProperty -Path $GcpwRegKey -Name 'domains_allowed_to_login' -ErrorAction SilentlyContinue).domains_allowed_to_login
    $gcpwDays   = (Get-ItemProperty -Path $GcpwRegKey -Name 'validity_period_in_days'  -ErrorAction SilentlyContinue).validity_period_in_days
    Write-OK "GCPW key confirmed: $GcpwRegKey"
    Write-OK "  domains_allowed_to_login = $gcpwDomain"
    Write-OK "  validity_period_in_days  = $gcpwDays"
} else {
    Write-Warn "GCPW registry key NOT found at $GcpwRegKey"
    Write-Warn 'GCPW may not have installed correctly. Try rebooting and re-running.'
}

# ═════════════════════════════════════════════════════════════════════════════
#  FINAL SUMMARY
# ═════════════════════════════════════════════════════════════════════════════
$sep = '=' * 72
Write-Host ''
Write-Host $sep -ForegroundColor Cyan
Write-Host '   Installation Complete! — Summary' -ForegroundColor Green
Write-Host $sep -ForegroundColor Cyan
Write-Host ''
Write-Host '  SOFTWARE RESULTS:' -ForegroundColor Yellow

foreach ($item in $Results.GetEnumerator()) {
    $color = switch -Wildcard ($item.Value) {
        'Installed OK*'           { 'Green'    }
        'Already installed*'      { 'DarkCyan' }
        '*error*'                 { 'Red'      }
        '*failed*'                { 'Red'      }
        '*warning*'               { 'Yellow'   }
        default                   { 'White'    }
    }
    $label = $item.Key.PadRight(26)
    Write-Host "    $label : " -NoNewline -ForegroundColor White
    Write-Host $item.Value -ForegroundColor $color
}

Write-Host ''
Write-Host '  GCPW CONFIGURATION:' -ForegroundColor Yellow
Write-Host "    Allowed domain       :  $Domain"
Write-Host "    Enrollment token     :  $EnrollmentToken"
Write-Host '    Offline validity     :  5 days'
Write-Host '    Last username hidden :  Yes'
Write-Host ''
Write-Host '  NEXT STEPS:' -ForegroundColor Yellow
Write-Host '    1.  RESTART this computer.'
Write-Host '    2.  On the login screen you should see the GCPW sign-in option.'
Write-Host '    3.  Click "Other user" and sign in with your @brightuitechnologies.com'
Write-Host '        Google Workspace email address.'
Write-Host '    4.  Complete Google authentication to finish signing in.'
Write-Host ''
Write-Host '  TROUBLESHOOTING:' -ForegroundColor Yellow
Write-Host '    - If GCPW does not appear after reboot, re-run this script as Administrator.'
Write-Host '    - Ensure Chrome is installed BEFORE GCPW (this script handles that order).'
Write-Host '    - Check Event Viewer > Application for GCPW errors if sign-in fails.'
Write-Host '    - WinRAR: default trial — purchase licence if required by policy.'
Write-Host "    - GCPW support: https://support.google.com/a/answer/9650196"
Write-Host ''
Write-Host $sep -ForegroundColor Cyan
Write-Host ''
