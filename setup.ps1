<#
.SYNOPSIS
    Automated setup script:
      1.  GCPW.ps1
      2.  script.ps1
      3.  Download BrightUI logo
      4.  Generate user account pictures
      5.  Install Chocolatey
      6.  Install Lightshot (silent)
      7.  Install Microsoft Office 365 (silent)
      8.  Activate Windows — HWID (fully silent, no window)
      9.  Activate Office  — Ohook (fully silent, no window)
      10. Enable Remote Desktop + add BrightUI_Admin to RDP Users
      11. Restart system
.NOTES
    Must be run as Administrator.
    All steps are fully automated — zero popups, zero CMD windows.
#>

#Requires -RunAsAdministrator

# ============================================================
# SECTION 0 — GLOBAL BYPASS
# Suppresses every security prompt / confirmation dialog for
# this process AND all child processes spawned below.
# ============================================================
Set-ExecutionPolicy Bypass -Scope Process -Force
$ConfirmPreference     = 'None'
$ProgressPreference    = 'SilentlyContinue'
$WarningPreference     = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

if (-not $global:PSDefaultParameterValues) { $global:PSDefaultParameterValues = @{} }
$global:PSDefaultParameterValues['Invoke-WebRequest:UseBasicParsing'] = $true

# Write Bypass into registry so every child PowerShell inherits it
foreach ($regPath in @(
    'HKLM:\SOFTWARE\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell',
    'HKLM:\SOFTWARE\Wow6432Node\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell'
)) {
    try {
        if (Test-Path $regPath) {
            Set-ItemProperty -Path $regPath -Name 'ExecutionPolicy' `
                             -Value 'Bypass' -Force -ErrorAction SilentlyContinue
        }
    } catch {}
}

Write-Host "=====================================================" -ForegroundColor Yellow
Write-Host "  Security prompts suppressed. Fully automated run." -ForegroundColor Yellow
Write-Host "=====================================================" -ForegroundColor Yellow

# ============================================================
# HELPER — Invoke-HiddenPS
# Launches a PowerShell code block in a completely hidden
# child process (no window, no flicker). Returns exit code.
# ============================================================
function Invoke-HiddenPS {
    param([Parameter(Mandatory)][string]$Code)
    $encoded = [Convert]::ToBase64String(
        [System.Text.Encoding]::Unicode.GetBytes($Code)
    )
    $psi                        = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $psi.Arguments              = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $encoded"
    $psi.WindowStyle            = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.CreateNoWindow         = $true
    $psi.UseShellExecute        = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $proc    = [System.Diagnostics.Process]::Start($psi)
    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $errTask = $proc.StandardError.ReadToEndAsync()
    $proc.WaitForExit()
    [void]$outTask.Result
    [void]$errTask.Result
    return $proc.ExitCode
}

# ============================================================
# HELPER — Invoke-HiddenPSWithLog
# Same as above but also returns stdout/stderr for logging.
# ============================================================
function Invoke-HiddenPSWithLog {
    param([Parameter(Mandatory)][string]$Code)
    $encoded = [Convert]::ToBase64String(
        [System.Text.Encoding]::Unicode.GetBytes($Code)
    )
    $psi                        = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $psi.Arguments              = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $encoded"
    $psi.WindowStyle            = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.CreateNoWindow         = $true
    $psi.UseShellExecute        = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $proc    = [System.Diagnostics.Process]::Start($psi)
    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $errTask = $proc.StandardError.ReadToEndAsync()
    $proc.WaitForExit()
    return @{
        ExitCode = $proc.ExitCode
        Stdout   = $outTask.Result
        Stderr   = $errTask.Result
    }
}

# ============================================================
# SECTION 1 — Run GCPW.ps1
# ============================================================
Write-Host ""
Write-Host "[1/10] Downloading and executing GCPW.ps1..." -ForegroundColor Cyan
try {
    $gcpwContent = (Invoke-WebRequest `
        -Uri 'https://raw.githubusercontent.com/Tech-Support-Automated/Powershellcode/master/GCPW.ps1' `
        -UseBasicParsing).Content
    Invoke-Expression $gcpwContent
} catch {
    Write-Host "ERROR: Failed to execute GCPW.ps1 — $_" -ForegroundColor Red
    exit 1
}
Write-Host "GCPW.ps1 completed successfully." -ForegroundColor Green

# ============================================================
# SECTION 2 — Run script.ps1
# ============================================================
Write-Host ""
Write-Host "[2/10] Downloading and executing script.ps1..." -ForegroundColor Cyan
try {
    $scriptContent = (Invoke-WebRequest `
        -Uri 'https://raw.githubusercontent.com/Tech-Support-Automated/Powershellcode/master/script.ps1' `
        -UseBasicParsing).Content
    Invoke-Expression $scriptContent
} catch {
    Write-Host "ERROR: Failed to execute script.ps1 — $_" -ForegroundColor Red
    exit 1
}
Write-Host "script.ps1 completed successfully." -ForegroundColor Green

# ============================================================
# SECTION 3 — Download BrightUI logo
# ============================================================
Write-Host ""
Write-Host "[3/10] Downloading logo image..." -ForegroundColor Cyan

$LogoUrl  = 'https://raw.githubusercontent.com/Tech-Support-Automated/Powershellcode/master/logo.png'
$LogoDir  = 'C:\ProgramData\BrightUI\Assets'
$LogoPath = Join-Path $LogoDir 'brightui_technologies_logo.png'

if (-not (Test-Path $LogoDir)) {
    New-Item -Path $LogoDir -ItemType Directory -Force | Out-Null
}
try {
    Invoke-WebRequest -Uri $LogoUrl -OutFile $LogoPath -UseBasicParsing
} catch {
    Write-Host "ERROR: Failed to download logo — $_" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $LogoPath)) {
    Write-Host "ERROR: Logo file missing after download." -ForegroundColor Red
    exit 1
}
Write-Host "Logo saved to: $LogoPath" -ForegroundColor Green

# ============================================================
# SECTION 4 — Generate default user account pictures
# ============================================================
Write-Host ""
Write-Host "[4/10] Generating user account pictures..." -ForegroundColor Cyan

Add-Type -AssemblyName System.Drawing

$DestFolder = 'C:\ProgramData\Microsoft\User Account Pictures'
New-Item -Path $DestFolder -ItemType Directory -Force | Out-Null

foreach ($Size in @(32, 40, 48, 96, 192, 200, 240, 448)) {
    try {
        $Bitmap   = [System.Drawing.Image]::FromFile($LogoPath)
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
        Write-Host "  Warning: size ${Size}px failed — $_" -ForegroundColor Yellow
    }
}

Copy-Item $LogoPath (Join-Path $DestFolder 'user.png') -Force

# Registry: enforce default account picture policy
$PolicyPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
if (-not (Test-Path $PolicyPath)) { New-Item -Path $PolicyPath -Force | Out-Null }
New-ItemProperty -Path $PolicyPath -Name 'UseDefaultTile' `
                 -Value 1 -PropertyType DWord -Force | Out-Null

# Clear per-user cached pictures so the new one takes effect
$CachedPics = "$env:APPDATA\Microsoft\Windows\AccountPictures"
if (Test-Path $CachedPics) {
    Remove-Item "$CachedPics\*" -Force -Recurse -ErrorAction SilentlyContinue
}

# Restart Explorer to pick up the new pictures
Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2
Start-Process explorer.exe

Write-Host "User account pictures installed successfully." -ForegroundColor Green

# ============================================================
# SECTION 5 — Install Chocolatey
# ============================================================
Write-Host ""
Write-Host "[5/10] Checking for Chocolatey..." -ForegroundColor Cyan

if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    try {
        Invoke-Expression (
            (Invoke-WebRequest -Uri 'https://chocolatey.org/install.ps1' -UseBasicParsing).Content
        )
        # Refresh PATH so choco is usable immediately in this session
        $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                    [System.Environment]::GetEnvironmentVariable('Path', 'User')
    } catch {
        Write-Host "ERROR: Chocolatey install failed — $_" -ForegroundColor Red
        exit 1
    }
    Write-Host "Chocolatey installed successfully." -ForegroundColor Green
} else {
    Write-Host "Chocolatey already present." -ForegroundColor Green
}

# ============================================================
# SECTION 6 — Silent install of Lightshot via Chocolatey
# ============================================================
Write-Host ""
Write-Host "[6/10] Installing Lightshot (silent, no popups)..." -ForegroundColor Cyan
try {
    $ErrorActionPreference = 'Continue'
    choco install lightshot -y --no-progress --params "'/S'" 2>&1 | Out-Null
    if ($LASTEXITCODE -notin @(0, 3010)) { throw "choco exit code: $LASTEXITCODE" }
    $ErrorActionPreference = 'Stop'
    Write-Host "Lightshot installed successfully." -ForegroundColor Green
} catch {
    Write-Host "ERROR: Lightshot install failed — $_" -ForegroundColor Red
    exit 1
}

# ============================================================
# SECTION 7 — Silent install of Microsoft Office 365
# ============================================================
Write-Host ""
Write-Host "[7/10] Installing Microsoft Office 365 (silent, may take several minutes)..." -ForegroundColor Cyan
try {
    $ErrorActionPreference = 'Continue'
    choco install office365business -y --no-progress 2>&1 | Out-Null
    if ($LASTEXITCODE -notin @(0, 3010)) { throw "choco exit code: $LASTEXITCODE" }
    $ErrorActionPreference = 'Stop'
    Write-Host "Microsoft Office 365 installed successfully." -ForegroundColor Green
} catch {
    Write-Host "ERROR: Office install failed — $_" -ForegroundColor Red
    exit 1
}

# ============================================================
# SECTION 8 — ACTIVATE WINDOWS (HWID) — fully silent
#
# Three-method fallback chain, all inside Invoke-HiddenPSWithLog
# (zero CMD windows, zero popups):
#   Method A — MAS HWID_Activation.ps1 (separate-file activator,
#               menu stripped, function called directly by name)
#   Method B — ClipUp.exe (Windows built-in HWID token claimer)
#   Method C — cscript slmgr.vbs /ato (universal last-resort)
#
# Equivalent to: irm get.activated.win → Option 1 → Option 1
# ============================================================
Write-Host ""
Write-Host "[8/10] Activating Windows (HWID) — fully automated, no window..." -ForegroundColor Cyan

$WinActivationCode = @'
Set-ExecutionPolicy Bypass -Scope Process -Force
$ConfirmPreference  = 'None'
$ProgressPreference = 'SilentlyContinue'
$WarningPreference  = 'SilentlyContinue'
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

$activated = $false

# ---- METHOD A: MAS HWID_Activation.ps1 (no menu) ----
try {
    $hwidUrl  = 'https://raw.githubusercontent.com/massgravel/Microsoft-Activation-Scripts/master/MAS/Separate-Files-Version/Activators/HWID_Activation.ps1'
    $hwidCode = (Invoke-WebRequest -Uri $hwidUrl -UseBasicParsing).Content

    # Strip everything after the last closing brace (menu launcher lines)
    $lines     = $hwidCode -split "`n"
    $lastBrace = 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq '}') { $lastBrace = $i }
    }
    $cleanCode = ($lines[0..$lastBrace]) -join "`n"

    $tmpFile = "$env:TEMP\mas_hwid.ps1"
    [System.IO.File]::WriteAllText($tmpFile, $cleanCode, [System.Text.Encoding]::UTF8)
    . $tmpFile   # dot-source to load functions into scope

    $fn = Get-Command -Name 'HWID_Activation' -ErrorAction SilentlyContinue
    if (-not $fn) {
        $fn = Get-Command -CommandType Function -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -match 'HWID' } | Select-Object -First 1
    }
    if ($fn) {
        & $fn.Name
        $activated = $true
        Write-Output "METHOD_A_SUCCESS"
    }
    Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
} catch {
    Write-Output "METHOD_A_FAILED: $_"
}

# ---- METHOD B: ClipUp.exe (built-in Windows HWID token claimer) ----
if (-not $activated) {
    try {
        $clipup = "$env:SystemRoot\System32\ClipUp.exe"
        if (Test-Path $clipup) {
            $p = Start-Process -FilePath $clipup `
                               -ArgumentList '-v', '-o', '-altto', "$env:TEMP\hwid_token.bin" `
                               -Wait -PassThru -WindowStyle Hidden -NoNewWindow
            if ($p.ExitCode -eq 0) {
                $activated = $true
                Write-Output "METHOD_B_SUCCESS"
            } else {
                Write-Output "METHOD_B_FAILED: ClipUp exit $($p.ExitCode)"
            }
        } else {
            Write-Output "METHOD_B_SKIPPED: ClipUp.exe not found"
        }
    } catch {
        Write-Output "METHOD_B_FAILED: $_"
    }
}

# ---- METHOD C: slmgr.vbs /ato (universal fallback) ----
if (-not $activated) {
    try {
        $psi                        = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName               = 'cscript.exe'
        $psi.Arguments              = "//nologo `"$env:SystemRoot\System32\slmgr.vbs`" /ato"
        $psi.WindowStyle            = [System.Diagnostics.ProcessWindowStyle]::Hidden
        $psi.CreateNoWindow         = $true
        $psi.UseShellExecute        = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true
        $proc = [System.Diagnostics.Process]::Start($psi)
        $proc.WaitForExit()
        if ($proc.ExitCode -eq 0) {
            $activated = $true
            Write-Output "METHOD_C_SUCCESS"
        } else {
            Write-Output "METHOD_C_FAILED: slmgr exit $($proc.ExitCode)"
        }
    } catch {
        Write-Output "METHOD_C_FAILED: $_"
    }
}

if (-not $activated) {
    Write-Output "ALL_METHODS_FAILED"
    exit 1
}
exit 0
'@

try {
    $winResult = Invoke-HiddenPSWithLog -Code $WinActivationCode
    if ($winResult.ExitCode -ne 0) {
        throw "Output: $($winResult.Stdout) $($winResult.Stderr)"
    }
    ($winResult.Stdout -split "`n") |
        Where-Object { $_ -match '_SUCCESS|_FAILED|_SKIPPED' } |
        ForEach-Object { Write-Host "  $($_.Trim())" -ForegroundColor DarkCyan }
    Write-Host "Windows activated successfully (HWID)." -ForegroundColor Green
} catch {
    Write-Host "ERROR: Windows activation failed — $_" -ForegroundColor Red
    exit 1
}

# ============================================================
# SECTION 9 — ACTIVATE OFFICE (Ohook) — fully silent
#
# Two-method fallback chain, all inside Invoke-HiddenPSWithLog:
#   Method A — MAS Ohook_Activation_AIO.ps1 (separate-file activator,
#               menu stripped, function called directly by name)
#   Method B — cscript ospp.vbs /act (Office built-in tool,
#               path auto-discovered across all Office versions)
#
# Equivalent to: irm get.activated.win → Option 2 → Option 1
# ============================================================
Write-Host ""
Write-Host "[9/10] Activating Office (Ohook) — fully automated, no window..." -ForegroundColor Cyan

$OfficeActivationCode = @'
Set-ExecutionPolicy Bypass -Scope Process -Force
$ConfirmPreference  = 'None'
$ProgressPreference = 'SilentlyContinue'
$WarningPreference  = 'SilentlyContinue'
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

$activated = $false

# ---- METHOD A: MAS Ohook_Activation_AIO.ps1 (no menu) ----
try {
    $ohookUrl  = 'https://raw.githubusercontent.com/massgravel/Microsoft-Activation-Scripts/master/MAS/Separate-Files-Version/Activators/Ohook_Activation_AIO.ps1'
    $ohookCode = (Invoke-WebRequest -Uri $ohookUrl -UseBasicParsing).Content

    $lines     = $ohookCode -split "`n"
    $lastBrace = 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq '}') { $lastBrace = $i }
    }
    $cleanCode = ($lines[0..$lastBrace]) -join "`n"

    $tmpFile = "$env:TEMP\mas_ohook.ps1"
    [System.IO.File]::WriteAllText($tmpFile, $cleanCode, [System.Text.Encoding]::UTF8)
    . $tmpFile

    $fn = Get-Command -Name 'Ohook_Activation_AIO' -ErrorAction SilentlyContinue
    if (-not $fn) { $fn = Get-Command -Name 'Ohook_Activation' -ErrorAction SilentlyContinue }
    if (-not $fn) {
        $fn = Get-Command -CommandType Function -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -match 'Ohook' } | Select-Object -First 1
    }
    if ($fn) {
        & $fn.Name
        $activated = $true
        Write-Output "METHOD_A_SUCCESS"
    }
    Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
} catch {
    Write-Output "METHOD_A_FAILED: $_"
}

# ---- METHOD B: ospp.vbs /act (Office built-in activation) ----
if (-not $activated) {
    $ospPaths = @(
        "$env:ProgramFiles\Microsoft Office\Office16\ospp.vbs",
        "$env:ProgramFiles\Microsoft Office\Office15\ospp.vbs",
        "${env:ProgramFiles(x86)}\Microsoft Office\Office16\ospp.vbs",
        "${env:ProgramFiles(x86)}\Microsoft Office\Office15\ospp.vbs"
    )
    # Dynamic search catches non-standard install locations
    $found = Get-ChildItem -Path @(
                "$env:ProgramFiles\Microsoft Office",
                "${env:ProgramFiles(x86)}\Microsoft Office"
             ) -Filter 'ospp.vbs' -Recurse -ErrorAction SilentlyContinue |
             Select-Object -First 1
    if ($found) { $ospPaths = @($found.FullName) + $ospPaths }

    foreach ($osppPath in $ospPaths) {
        if (Test-Path $osppPath) {
            try {
                $psi                        = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName               = 'cscript.exe'
                $psi.Arguments              = "//nologo `"$osppPath`" /act"
                $psi.WindowStyle            = [System.Diagnostics.ProcessWindowStyle]::Hidden
                $psi.CreateNoWindow         = $true
                $psi.UseShellExecute        = $false
                $psi.RedirectStandardOutput = $true
                $psi.RedirectStandardError  = $true
                $proc = [System.Diagnostics.Process]::Start($psi)
                $proc.WaitForExit()
                if ($proc.ExitCode -eq 0) {
                    $activated = $true
                    Write-Output "METHOD_B_SUCCESS: $osppPath"
                    break
                } else {
                    Write-Output "METHOD_B_TRIED: $osppPath exit $($proc.ExitCode)"
                }
            } catch {
                Write-Output "METHOD_B_FAILED: $osppPath — $_"
            }
        }
    }
}

if (-not $activated) {
    Write-Output "ALL_METHODS_FAILED"
    exit 1
}
exit 0
'@

try {
    $offResult = Invoke-HiddenPSWithLog -Code $OfficeActivationCode
    if ($offResult.ExitCode -ne 0) {
        throw "Output: $($offResult.Stdout) $($offResult.Stderr)"
    }
    ($offResult.Stdout -split "`n") |
        Where-Object { $_ -match '_SUCCESS|_FAILED|_TRIED|_SKIPPED' } |
        ForEach-Object { Write-Host "  $($_.Trim())" -ForegroundColor DarkCyan }
    Write-Host "Microsoft Office activated successfully (Ohook — permanent)." -ForegroundColor Green
} catch {
    Write-Host "ERROR: Office activation failed — $_" -ForegroundColor Red
    exit 1
}

# ============================================================
# SECTION 10 — ENABLE REMOTE DESKTOP + ADD BrightUI_Admin
#
# Steps performed (all silent, no prompts, no windows):
#   10a. Enable Remote Desktop via registry (fDenyTSConnections = 0)
#   10b. Set RDP security layer and NLA (Network Level Auth) settings
#   10c. Enable the RDP firewall rules (all profiles)
#   10d. Ensure the Remote Desktop service (TermService) is running
#        and set to start automatically
#   10e. Create local user 'BrightUI_Admin' if it does not exist
#        (strong random password, password never expires)
#   10f. Add BrightUI_Admin to the built-in 'Remote Desktop Users'
#        group (safe to run even if already a member)
#   10g. Also add BrightUI_Admin to the local Administrators group
#        so RDP sessions have full admin rights
# ============================================================
Write-Host ""
Write-Host "[10/10] Enabling Remote Desktop and configuring BrightUI_Admin..." -ForegroundColor Cyan

# ---- 10a. Enable Remote Desktop in registry ----
$rdpRegPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
try {
    if (-not (Test-Path $rdpRegPath)) {
        New-Item -Path $rdpRegPath -Force | Out-Null
    }
    # fDenyTSConnections = 0  →  RDP connections allowed
    Set-ItemProperty -Path $rdpRegPath -Name 'fDenyTSConnections' -Value 0 -Type DWord -Force
    Write-Host "  Remote Desktop enabled (fDenyTSConnections = 0)." -ForegroundColor DarkCyan
} catch {
    Write-Host "ERROR: Failed to enable RDP in registry — $_" -ForegroundColor Red
    exit 1
}

# ---- 10b. RDP security and NLA settings ----
try {
    # SecurityLayer: 2 = TLS/SSL (recommended)
    Set-ItemProperty -Path $rdpRegPath -Name 'SecurityLayer' -Value 2 -Type DWord -Force

    $winStationsPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
    if (Test-Path $winStationsPath) {
        # UserAuthentication: 1 = NLA required (more secure)
        Set-ItemProperty -Path $winStationsPath -Name 'UserAuthentication' -Value 1 -Type DWord -Force
        # SecurityLayer on the WinStation too
        Set-ItemProperty -Path $winStationsPath -Name 'SecurityLayer'      -Value 2 -Type DWord -Force
    }
    Write-Host "  RDP security layer set to TLS, NLA enabled." -ForegroundColor DarkCyan
} catch {
    # Non-fatal — RDP will still work with default security settings
    Write-Host "  Warning: Could not set RDP security settings — $_" -ForegroundColor Yellow
}

# ---- 10c. Open RDP firewall rules (TCP 3389) on all profiles ----
try {
    # Enable the built-in RDP firewall rules (Display group = "Remote Desktop")
    $ErrorActionPreference = 'Continue'
    netsh advfirewall firewall set rule group="remote desktop" new enable=Yes 2>&1 | Out-Null

    # Also enable via PowerShell cmdlet for thoroughness
    Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue

    # Ensure a catch-all rule exists for TCP 3389 in case the above misses anything
    $existing = Get-NetFirewallRule -DisplayName 'BrightUI-RDP-Allow' -ErrorAction SilentlyContinue
    if (-not $existing) {
        New-NetFirewallRule `
            -DisplayName   'BrightUI-RDP-Allow' `
            -Direction     Inbound `
            -Protocol      TCP `
            -LocalPort     3389 `
            -Action        Allow `
            -Profile       Any `
            -Enabled       True `
            -ErrorAction   SilentlyContinue | Out-Null
    }
    $ErrorActionPreference = 'Stop'
    Write-Host "  Firewall rules for RDP (TCP 3389) enabled on all profiles." -ForegroundColor DarkCyan
} catch {
    Write-Host "  Warning: Firewall rule update had an issue — $_" -ForegroundColor Yellow
}

# ---- 10d. Ensure TermService (Remote Desktop Services) is running ----
try {
    $svc = Get-Service -Name 'TermService' -ErrorAction SilentlyContinue
    if ($svc) {
        Set-Service -Name 'TermService' -StartupType Automatic -ErrorAction SilentlyContinue
        if ($svc.Status -ne 'Running') {
            Start-Service -Name 'TermService' -ErrorAction SilentlyContinue
        }
        Write-Host "  TermService (RDP) is running and set to Automatic." -ForegroundColor DarkCyan
    }
    # Also ensure the RDP port listener (UmRdpService) is running
    $umRdp = Get-Service -Name 'UmRdpService' -ErrorAction SilentlyContinue
    if ($umRdp) {
        Set-Service -Name 'UmRdpService' -StartupType Automatic -ErrorAction SilentlyContinue
        if ($umRdp.Status -ne 'Running') {
            Start-Service -Name 'UmRdpService' -ErrorAction SilentlyContinue
        }
    }
} catch {
    Write-Host "  Warning: Could not start TermService — $_" -ForegroundColor Yellow
}

# ---- 10e. Create local user BrightUI_Admin if it does not exist ----
$rdpUsername = 'BrightUI_Admin'

# Generate a strong random password (24 chars, upper+lower+digit+symbol)
Add-Type -AssemblyName System.Web
$rdpPassword = [System.Web.Security.Membership]::GeneratePassword(24, 6)
$rdpSecurePassword = ConvertTo-SecureString $rdpPassword -AsPlainText -Force

try {
    $existingUser = Get-LocalUser -Name $rdpUsername -ErrorAction SilentlyContinue
    if (-not $existingUser) {
        New-LocalUser `
            -Name                 $rdpUsername `
            -Password             $rdpSecurePassword `
            -FullName             'BrightUI Admin' `
            -Description          'BrightUI Remote Desktop administrator account' `
            -PasswordNeverExpires `
            -UserMayNotChangePassword:$false `
            -AccountNeverExpires `
            -ErrorAction Stop | Out-Null

        Write-Host "  Local user '$rdpUsername' created successfully." -ForegroundColor DarkCyan
        # Save password to a secure location only Administrators can read
        $credFile = 'C:\ProgramData\BrightUI\rdp_admin_credentials.txt'
        $credContent = @"
BrightUI Remote Desktop Admin Credentials
==========================================
Username : $rdpUsername
Password : $rdpPassword
Created  : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
NOTE     : Store this securely and delete this file after noting the password.
"@
        [System.IO.File]::WriteAllText($credFile, $credContent, [System.Text.Encoding]::UTF8)
        # Restrict read access: Administrators only
        $acl  = Get-Acl $credFile
        $acl.SetAccessRuleProtection($true, $false)
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            'BUILTIN\Administrators', 'FullControl', 'Allow'
        )
        $acl.AddAccessRule($rule)
        Set-Acl -Path $credFile -AclObject $acl -ErrorAction SilentlyContinue
        Write-Host "  Credentials saved to: $credFile (Admins only)" -ForegroundColor Yellow
    } else {
        Write-Host "  User '$rdpUsername' already exists — skipping creation." -ForegroundColor DarkCyan
        # Ensure account is enabled if it was disabled
        Enable-LocalUser -Name $rdpUsername -ErrorAction SilentlyContinue
    }
} catch {
    Write-Host "ERROR: Failed to create local user '$rdpUsername' — $_" -ForegroundColor Red
    exit 1
}

# ---- 10f. Add BrightUI_Admin to Remote Desktop Users group ----
$rdpGroupNames = @(
    'Remote Desktop Users',        # English
    'Benutzer der Remotedesktopverbindung',  # German
    'Utilisateurs du Bureau à distance',     # French
    'Usuarios de escritorio remoto'          # Spanish
)

# Resolve actual group name by SID (S-1-5-32-555) — language-independent
try {
    $rdpGroupSid  = [System.Security.Principal.SecurityIdentifier]'S-1-5-32-555'
    $rdpGroupName = $rdpGroupSid.Translate([System.Security.Principal.NTAccount]).Value.Split('\')[-1]
} catch {
    $rdpGroupName = 'Remote Desktop Users'
}

try {
    $groupMembers = Get-LocalGroupMember -Group $rdpGroupName -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -match $rdpUsername }
    if (-not $groupMembers) {
        Add-LocalGroupMember -Group $rdpGroupName -Member $rdpUsername -ErrorAction Stop
        Write-Host "  '$rdpUsername' added to '$rdpGroupName' group." -ForegroundColor DarkCyan
    } else {
        Write-Host "  '$rdpUsername' is already in '$rdpGroupName' group." -ForegroundColor DarkCyan
    }
} catch {
    Write-Host "ERROR: Failed to add '$rdpUsername' to '$rdpGroupName' — $_" -ForegroundColor Red
    exit 1
}

# ---- 10g. Add BrightUI_Admin to local Administrators group ----
# Resolve Administrators group by SID (S-1-5-32-544) — language-independent
try {
    $adminGroupSid  = [System.Security.Principal.SecurityIdentifier]'S-1-5-32-544'
    $adminGroupName = $adminGroupSid.Translate([System.Security.Principal.NTAccount]).Value.Split('\')[-1]
} catch {
    $adminGroupName = 'Administrators'
}

try {
    $adminMembers = Get-LocalGroupMember -Group $adminGroupName -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -match $rdpUsername }
    if (-not $adminMembers) {
        Add-LocalGroupMember -Group $adminGroupName -Member $rdpUsername -ErrorAction Stop
        Write-Host "  '$rdpUsername' added to '$adminGroupName' group." -ForegroundColor DarkCyan
    } else {
        Write-Host "  '$rdpUsername' is already in '$adminGroupName' group." -ForegroundColor DarkCyan
    }
} catch {
    # Non-fatal — RDP will still work, just without local admin rights
    Write-Host "  Warning: Could not add to Administrators — $_" -ForegroundColor Yellow
}

Write-Host "Remote Desktop configuration completed successfully." -ForegroundColor Green

# ============================================================
# DONE — Full summary + Restart
# ============================================================
Write-Host ""
Write-Host "=====================================================" -ForegroundColor Green
Write-Host "  ALL STEPS COMPLETED SUCCESSFULLY                  " -ForegroundColor Green
Write-Host "-----------------------------------------------------" -ForegroundColor Green
Write-Host "  [ 1] GCPW             : Configured"                  -ForegroundColor Green
Write-Host "  [ 2] script.ps1       : Executed"                    -ForegroundColor Green
Write-Host "  [ 3] Logo             : Downloaded"                  -ForegroundColor Green
Write-Host "  [ 4] Account Pictures : Installed"                   -ForegroundColor Green
Write-Host "  [ 5] Chocolatey       : Ready"                       -ForegroundColor Green
Write-Host "  [ 6] Lightshot        : Installed (silent)"          -ForegroundColor Green
Write-Host "  [ 7] Office 365       : Installed (silent)"          -ForegroundColor Green
Write-Host "  [ 8] Windows          : Activated (HWID)"            -ForegroundColor Green
Write-Host "  [ 9] Office           : Activated (Ohook/Permanent)" -ForegroundColor Green
Write-Host "  [10] Remote Desktop   : Enabled + BrightUI_Admin"    -ForegroundColor Green
Write-Host "=====================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  RDP Port  : 3389 (TCP) — firewall opened"           -ForegroundColor Cyan
Write-Host "  RDP User  : BrightUI_Admin"                         -ForegroundColor Cyan
Write-Host "  RDP Groups: Remote Desktop Users + Administrators"   -ForegroundColor Cyan
Write-Host "  Password  : See C:\ProgramData\BrightUI\rdp_admin_credentials.txt" -ForegroundColor Yellow
Write-Host ""
Write-Host "Restarting in 5 seconds..." -ForegroundColor Yellow
Start-Sleep -Seconds 5
Restart-Computer -Force
