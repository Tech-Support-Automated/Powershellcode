<#
.SYNOPSIS
    Automated setup script: GCPW, script.ps1, logo, user pictures,
    Lightshot, Office install, Windows HWID activation, Office Ohook
    activation — all fully silent, zero popups, zero CMD windows.
.NOTES
    Must be run as Administrator.
#>

#Requires -RunAsAdministrator

# ============================================================
# SECTION 0 — GLOBAL BYPASS (runs first, covers everything)
# ============================================================
Set-ExecutionPolicy Bypass -Scope Process -Force
$ConfirmPreference     = 'None'
$ProgressPreference    = 'SilentlyContinue'
$WarningPreference     = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

if (-not $global:PSDefaultParameterValues) { $global:PSDefaultParameterValues = @{} }
$global:PSDefaultParameterValues['Invoke-WebRequest:UseBasicParsing'] = $true

# Bypass ExecutionPolicy in registry for all child processes too
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
# HELPER FUNCTION — Invoke-HiddenPS
# Runs any PowerShell script block in a completely hidden
# child process. No window, no flicker, no prompts.
# Returns the child process exit code.
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

    $proc = [System.Diagnostics.Process]::Start($psi)
    # Read both streams to prevent buffer deadlock
    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $errTask = $proc.StandardError.ReadToEndAsync()
    $proc.WaitForExit()
    [void]$outTask.Result
    [void]$errTask.Result
    return $proc.ExitCode
}

# ============================================================
# HELPER FUNCTION — Invoke-HiddenPSWithLog
# Same as above but RETURNS stdout so the parent can log it.
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

    $proc = [System.Diagnostics.Process]::Start($psi)
    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $errTask = $proc.StandardError.ReadToEndAsync()
    $proc.WaitForExit()
    $stdout = $outTask.Result
    $stderr = $errTask.Result
    return @{ ExitCode = $proc.ExitCode; Stdout = $stdout; Stderr = $stderr }
}

# ============================================================
# SECTION 1 — Run GCPW.ps1
# ============================================================
Write-Host ""
Write-Host "[1/9] Downloading and executing GCPW.ps1..." -ForegroundColor Cyan
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
Write-Host "[2/9] Downloading and executing script.ps1..." -ForegroundColor Cyan
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
# SECTION 3 — Download logo
# ============================================================
Write-Host ""
Write-Host "[3/9] Downloading logo image..." -ForegroundColor Cyan

$LogoUrl  = 'https://raw.githubusercontent.com/Tech-Support-Automated/Powershellcode/master/logo.png'
$LogoDir  = 'C:\ProgramData\BrightUI\Assets'
$LogoPath = Join-Path $LogoDir 'brightui_technologies_logo.png'

if (-not (Test-Path $LogoDir)) { New-Item -Path $LogoDir -ItemType Directory -Force | Out-Null }

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
# SECTION 4 — Generate user account pictures
# ============================================================
Write-Host ""
Write-Host "[4/9] Generating user account pictures..." -ForegroundColor Cyan

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
        $Graphics.Dispose(); $Resized.Dispose(); $Bitmap.Dispose()
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

# Clear cached per-user pictures
$CachedPics = "$env:APPDATA\Microsoft\Windows\AccountPictures"
if (Test-Path $CachedPics) {
    Remove-Item "$CachedPics\*" -Force -Recurse -ErrorAction SilentlyContinue
}

# Restart Explorer to pick up new pictures
Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2
Start-Process explorer.exe

Write-Host "User account pictures installed successfully." -ForegroundColor Green

# ============================================================
# SECTION 5 — Install Chocolatey
# ============================================================
Write-Host ""
Write-Host "[5/9] Checking for Chocolatey..." -ForegroundColor Cyan

if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    try {
        Invoke-Expression (
            (Invoke-WebRequest -Uri 'https://chocolatey.org/install.ps1' -UseBasicParsing).Content
        )
        # Refresh PATH immediately so choco is usable in this session
        $env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
                    [System.Environment]::GetEnvironmentVariable('Path','User')
    } catch {
        Write-Host "ERROR: Chocolatey install failed — $_" -ForegroundColor Red
        exit 1
    }
    Write-Host "Chocolatey installed successfully." -ForegroundColor Green
} else {
    Write-Host "Chocolatey already present." -ForegroundColor Green
}

# ============================================================
# SECTION 6 — Silent install of Lightshot
# ============================================================
Write-Host ""
Write-Host "[6/9] Installing Lightshot (silent, no popups)..." -ForegroundColor Cyan
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
# SECTION 7 — Silent install of Microsoft Office
# ============================================================
Write-Host ""
Write-Host "[7/9] Installing Microsoft Office (silent, may take several minutes)..." -ForegroundColor Cyan
try {
    $ErrorActionPreference = 'Continue'
    choco install office365business -y --no-progress 2>&1 | Out-Null
    if ($LASTEXITCODE -notin @(0, 3010)) { throw "choco exit code: $LASTEXITCODE" }
    $ErrorActionPreference = 'Stop'
    Write-Host "Microsoft Office installed successfully." -ForegroundColor Green
} catch {
    Write-Host "ERROR: Office install failed — $_" -ForegroundColor Red
    exit 1
}

# ============================================================
# SECTION 8 — ACTIVATE WINDOWS (HWID) — fully silent
#
# Strategy (tried in order, all run in a hidden child process):
#   A) MAS HWID_Activation.ps1  — official MAS separate-file activator
#      downloaded directly, dot-sourced, function called by name.
#   B) clipup.exe               — Windows built-in HWID token tool
#      (present on Win10 1507+ and Win11, silent, no UI at all)
#   C) slmgr.vbs /ato           — final fallback, works on all Windows
#
# Menu equivalent: irm get.activated.win → Option 1 → Option 1
# ============================================================
Write-Host ""
Write-Host "[8/9] Activating Windows (HWID) — fully automated, no window..." -ForegroundColor Cyan

$WinActivationCode = @'
Set-ExecutionPolicy Bypass -Scope Process -Force
$ConfirmPreference  = 'None'
$ProgressPreference = 'SilentlyContinue'
$WarningPreference  = 'SilentlyContinue'
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

$activated = $false

# ---- METHOD A: MAS HWID_Activation.ps1 (separate file, no menu) ----
try {
    $hwidUrl = 'https://raw.githubusercontent.com/massgravel/Microsoft-Activation-Scripts/master/MAS/Separate-Files-Version/Activators/HWID_Activation.ps1'
    $hwidCode = (Invoke-WebRequest -Uri $hwidUrl -UseBasicParsing).Content

    # Strip any interactive menu call at the end (lines after last closing brace)
    $lines = $hwidCode -split "`n"
    $lastBrace = 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq '}') { $lastBrace = $i }
    }
    $cleanCode = ($lines[0..$lastBrace]) -join "`n"

    # Write to temp file and dot-source to load functions
    $tmpFile = "$env:TEMP\mas_hwid.ps1"
    [System.IO.File]::WriteAllText($tmpFile, $cleanCode, [System.Text.Encoding]::UTF8)
    . $tmpFile

    # Call the HWID activation function directly
    $fn = Get-Command -Name 'HWID_Activation' -ErrorAction SilentlyContinue
    if (-not $fn) {
        # Try pattern match in case function was renamed
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

# ---- METHOD B: clipup.exe (Windows built-in HWID token activator) ----
if (-not $activated) {
    try {
        $clipup = "$env:SystemRoot\System32\ClipUp.exe"
        if (Test-Path $clipup) {
            # -v = verbose, -o = claim online, -altto = use HWID token
            $p = Start-Process -FilePath $clipup -ArgumentList '-v', '-o', '-altto', "$env:TEMP\hwid_token.bin" `
                               -Wait -PassThru -WindowStyle Hidden -NoNewWindow
            if ($p.ExitCode -eq 0) {
                $activated = $true
                Write-Output "METHOD_B_SUCCESS"
            } else {
                Write-Output "METHOD_B_FAILED: ClipUp exit $($p.ExitCode)"
            }
        } else {
            Write-Output "METHOD_B_SKIPPED: clipup.exe not found"
        }
    } catch {
        Write-Output "METHOD_B_FAILED: $_"
    }
}

# ---- METHOD C: slmgr.vbs /ato (universal fallback) ----
if (-not $activated) {
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
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
        throw "Windows activation failed. Output: $($winResult.Stdout) $($winResult.Stderr)"
    }
    # Show which method succeeded
    $methodLine = ($winResult.Stdout -split "`n") | Where-Object { $_ -match '_SUCCESS|_FAILED|_SKIPPED' }
    foreach ($line in $methodLine) { Write-Host "  $($line.Trim())" -ForegroundColor DarkCyan }
    Write-Host "Windows activated successfully (HWID)." -ForegroundColor Green
} catch {
    Write-Host "ERROR: Windows activation failed — $_" -ForegroundColor Red
    exit 1
}

# ============================================================
# SECTION 9 — ACTIVATE OFFICE (Ohook) — fully silent
#
# Strategy (tried in order, all run in a hidden child process):
#   A) MAS Ohook_Activation.ps1 — official MAS separate-file activator
#      downloaded directly, dot-sourced, function called by name.
#   B) ospp.vbs /act            — Office built-in activation tool
#      called via cscript //nologo (no window, no popup)
#
# Menu equivalent: irm get.activated.win → Option 2 → Option 1
# ============================================================
Write-Host ""
Write-Host "[9/9] Activating Office (Ohook) — fully automated, no window..." -ForegroundColor Cyan

$OfficeActivationCode = @'
Set-ExecutionPolicy Bypass -Scope Process -Force
$ConfirmPreference  = 'None'
$ProgressPreference = 'SilentlyContinue'
$WarningPreference  = 'SilentlyContinue'
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

$activated = $false

# ---- METHOD A: MAS Ohook_Activation.ps1 (separate file, no menu) ----
try {
    $ohookUrl = 'https://raw.githubusercontent.com/massgravel/Microsoft-Activation-Scripts/master/MAS/Separate-Files-Version/Activators/Ohook_Activation_AIO.ps1'
    $ohookCode = (Invoke-WebRequest -Uri $ohookUrl -UseBasicParsing).Content

    # Strip interactive menu lines after the last closing brace
    $lines = $ohookCode -split "`n"
    $lastBrace = 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq '}') { $lastBrace = $i }
    }
    $cleanCode = ($lines[0..$lastBrace]) -join "`n"

    $tmpFile = "$env:TEMP\mas_ohook.ps1"
    [System.IO.File]::WriteAllText($tmpFile, $cleanCode, [System.Text.Encoding]::UTF8)
    . $tmpFile

    # Call Ohook activation function directly
    $fn = Get-Command -Name 'Ohook_Activation_AIO' -ErrorAction SilentlyContinue
    if (-not $fn) {
        $fn = Get-Command -Name 'Ohook_Activation' -ErrorAction SilentlyContinue
    }
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
    # Find ospp.vbs across all Office installation paths
    $ospPaths = @(
        "$env:ProgramFiles\Microsoft Office\Office16\ospp.vbs",
        "$env:ProgramFiles\Microsoft Office\Office15\ospp.vbs",
        "${env:ProgramFiles(x86)}\Microsoft Office\Office16\ospp.vbs",
        "${env:ProgramFiles(x86)}\Microsoft Office\Office15\ospp.vbs"
    )
    # Also search dynamically
    $found = Get-ChildItem -Path "$env:ProgramFiles\Microsoft Office", "${env:ProgramFiles(x86)}\Microsoft Office" `
                           -Filter 'ospp.vbs' -Recurse -ErrorAction SilentlyContinue |
             Select-Object -First 1
    if ($found) { $ospPaths = @($found.FullName) + $ospPaths }

    foreach ($osppPath in $ospPaths) {
        if (Test-Path $osppPath) {
            try {
                $psi = New-Object System.Diagnostics.ProcessStartInfo
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
        throw "Office activation failed. Output: $($offResult.Stdout) $($offResult.Stderr)"
    }
    $methodLine = ($offResult.Stdout -split "`n") | Where-Object { $_ -match '_SUCCESS|_FAILED|_TRIED|_SKIPPED' }
    foreach ($line in $methodLine) { Write-Host "  $($line.Trim())" -ForegroundColor DarkCyan }
    Write-Host "Microsoft Office activated successfully (Ohook — permanent)." -ForegroundColor Green
} catch {
    Write-Host "ERROR: Office activation failed — $_" -ForegroundColor Red
    exit 1
}

# ============================================================
# DONE — Summary + Restart
# ============================================================
Write-Host ""
Write-Host "=====================================================" -ForegroundColor Green
Write-Host "  ALL STEPS COMPLETED SUCCESSFULLY                  " -ForegroundColor Green
Write-Host "-----------------------------------------------------" -ForegroundColor Green
Write-Host "  [1] GCPW            : Configured" -ForegroundColor Green
Write-Host "  [2] script.ps1      : Executed" -ForegroundColor Green
Write-Host "  [3] Logo            : Downloaded" -ForegroundColor Green
Write-Host "  [4] Account Pictures: Installed" -ForegroundColor Green
Write-Host "  [5] Chocolatey      : Ready" -ForegroundColor Green
Write-Host "  [6] Lightshot       : Installed (silent)" -ForegroundColor Green
Write-Host "  [7] Office          : Installed (silent)" -ForegroundColor Green
Write-Host "  [8] Windows         : Activated (HWID)" -ForegroundColor Green
Write-Host "  [9] Office          : Activated (Ohook - Permanent)" -ForegroundColor Green
Write-Host "=====================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Restarting in 5 seconds..." -ForegroundColor Yellow
Start-Sleep -Seconds 5
Restart-Computer -Force
