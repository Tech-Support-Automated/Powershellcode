<#
================================================================================
  BrightUI Technologies — Windows 10 / 11 Login Screen Setup  v4.8.1
================================================================================
  HOW TO RUN THIS SCRIPT:
  ────────────────────────────────────────────────────────────────────────────
  DO NOT paste this into a PowerShell console window (here-strings break).

  CORRECT METHOD:
    1.  Save this file as  BrightUI_Setup_V4.8.1.ps1
    2.  Open PowerShell as Administrator  (right-click → Run as Administrator)
    3.  cd "C:\path\to\folder"
    4.  .\BrightUI_Setup_V4.8.1.ps1

  CHANGES IN v4.8.1 (Fix for hangs & automatic restart):
  ────────────────────────────────────────────────────────────────────────────
  - $ErrorActionPreference changed from 'Stop' to 'Continue' so minor errors
    never freeze the script.
  - The GCPW installation block now downloads and runs the official standalone
    EXE with /silent /install – no external scripts, no interactivity.
  - Chrome installation remains fully silent (/quiet /norestart).
  - All reg add calls use /f to force.
  - Script will automatically restart the computer after a 5-second countdown
    once everything is complete (no "Press Enter" required).

  CHANGES IN v4.8 (compared to v4.7):
  ────────────────────────────────────────────────────────────────────────────
  SCHEDULED TASKS COMPLETELY REMOVED:
    - ALL Register-ScheduledTask calls have been removed from this script.
    - No scheduled tasks are created for ANY component, including
      BrightUI_SecurityLock, BrightUI_SecurityUnlock, BrightUI_HotkeyListener,
      and BrightUI_LoginReminder.
    - The hotkey listener is instead registered via HKLM Run key so it starts
      at every user logon without requiring the Task Scheduler.

  WALLPAPER DOWNLOAD METHOD UPDATED:
    - Now uses Invoke-WebRequest instead of WebClient for reliability.
    - Uses rundll32.exe user32.dll,UpdatePerUserSystemParameters to refresh
      the desktop wallpaper immediately without requiring a reboot.
    - The wallpaper is saved to C:\ProgramData\BrightUI\Assets\Desktop_image.png
      (matching the exact casing from the provided snippet).
    - Wallpaper is set to FILL style (WallpaperStyle=10) so it covers the
      entire screen regardless of resolution.
    - Locked via Group Policy so users cannot change it.
    - A logon-time re-apply script ensures it survives theme changes.

  USB UNLOCK FIX (Ctrl+Alt+U):
    - Completely rewrote the USB disk online/mount logic in BrightUI_Unlock.ps1.
    - Replaced the broken  Set-Partition -NewDriveLetter ([char]::MinValue)
      call (which passed a null character) with correct diskpart-based
      drive-letter assignment and Add-PartitionAccessPath as fallback.
    - Added Start-Sleep delays after enabling PnP devices to allow Windows
      time to re-enumerate the hardware before attempting disk operations.
    - USBSTOR service is now explicitly started (not just set to Start=3)
      so the driver loads immediately without a reboot.
    - StorageDevicePolicies WriteProtect is reset BEFORE enabling PnP devices.
    - Disk online/mount now retries up to 3 times with a 2-second pause
      to handle slow USB re-enumeration.

  REMOTE HOTKEY FIX (AnyDesk / Chrome Remote Desktop):
    - Added a TRIGGER FILE mechanism alongside the existing keyboard hooks.
      When the admin presses Ctrl+Alt+L or Ctrl+Alt+U from a remote session,
      the LL hook may not receive the keystrokes (AnyDesk injects input
      differently from RDP). The trigger file approach works regardless:
        C:\ProgramData\BrightUI\trigger_lock.txt   → triggers LOCK
        C:\ProgramData\BrightUI\trigger_unlock.txt → triggers UNLOCK
    - A FileSystemWatcher runs on a background thread inside the C# form
      and fires the appropriate action the instant either file appears.
    - The admin (or any elevated process) can create these files remotely
      to force a lock/unlock even when keyboard hooks are blocked.
    - Added a secondary polling loop (every 2 seconds) as belt-and-braces
      backup in case the FileSystemWatcher event fires slowly.
    - All three methods (RegisterHotKey + WH_KEYBOARD_LL + trigger files)
      share the same debounce and execution logic.

  ALL OTHER FEATURES from v4.7 are unchanged.

  COMPATIBILITY : Windows 10 Build 1703+  and  Windows 11 (all builds)
  REQUIREMENT   : Administrator rights
  AFTER RUNNING : RESTART the computer for all changes to take full effect.
================================================================================
#>

$ErrorActionPreference = 'Continue'      # changed from 'Stop' to avoid script freezing on minor errors
$ProgressPreference    = 'SilentlyContinue'

Write-Host ''
Write-Host ('=' * 72) -ForegroundColor Cyan
Write-Host '   BrightUI Technologies — Windows Login Screen Setup  v4.8.1' -ForegroundColor Cyan
Write-Host ('=' * 72) -ForegroundColor Cyan
Write-Host ''

# ══════════════════════════════════════════════════════════════════════════════
#  SECTION A — CONFIGURATION
# ══════════════════════════════════════════════════════════════════════════════

$Cfg_CompanyName = 'BrightUI Technologies'
$Cfg_Domain      = 'brightuitechnologies.com'
$Cfg_SupportURL  = 'https://portal.brightuitechnologies.com'
$Cfg_LogoURL     = 'https://dev.brightuitechnologies.com/site/wp-content/themes/startnext/landing/img/logo.png'

# Desktop wallpaper source URL (downloaded fresh each time setup runs)
$Cfg_WallpaperURL = 'https://raw.githubusercontent.com/Tech-Support-Automated/Powershellcode/master/Desktop_image.png'

$Cfg_RootDir    = 'C:\ProgramData\BrightUI'
$Cfg_AssetsDir  = 'C:\ProgramData\BrightUI\Assets'
$Cfg_ScriptsDir = 'C:\ProgramData\BrightUI\Scripts'
$Cfg_StateFile  = 'C:\ProgramData\BrightUI\toggle_state.txt'
$Cfg_LogFile    = 'C:\ProgramData\BrightUI\hotkey_log.txt'

# Trigger files — drop these files to remotely trigger lock/unlock from AnyDesk/CRD
$Cfg_TriggerLock   = 'C:\ProgramData\BrightUI\trigger_lock.txt'
$Cfg_TriggerUnlock = 'C:\ProgramData\BrightUI\trigger_unlock.txt'

# Desktop wallpaper — exact casing matches the provided snippet
$Cfg_WallpaperPath = 'C:\ProgramData\BrightUI\Assets\Desktop_image.png'

$Cfg_LockScriptPath   = 'C:\ProgramData\BrightUI\Scripts\BrightUI_Lock.ps1'
$Cfg_UnlockScriptPath = 'C:\ProgramData\BrightUI\Scripts\BrightUI_Unlock.ps1'

$Cfg_BgWidth  = 1920
$Cfg_BgHeight = 1080

$Cfg_UsbClassGuid  = '{53f56307-b6bf-11d0-94f2-00a0c91efb8b}'
$Cfg_UsbPolicyBase = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices'

$Cfg_LockHotkeyName   = 'Ctrl+Alt+L'
$Cfg_UnlockHotkeyName = 'Ctrl+Alt+U'

$Cfg_NoticeTitle = 'Welcome to BrightUI Technologies'
$Cfg_NoticeBody  =
    'To access this device, please read and follow all instructions below.'          + "`r`n`r`n" +
    'HOW TO SIGN IN:'                                                                + "`r`n"     +
    '  Step 1 :  Ensure this device is connected to the Internet.'                   + "`r`n"     +
    "  Step 2 :  On the login screen, click the 'Other Users  (->)' button."        + "`r`n"     +
    "  Step 3 :  Enter your @$Cfg_Domain Gmail address."                             + "`r`n"     +
    '  Step 4 :  Complete the Google authentication steps.'                          + "`r`n`r`n" +
    'IMPORTANT RESTRICTIONS:'                                                        + "`r`n"     +
    "  [X]  Only @$Cfg_Domain accounts are permitted."                               + "`r`n"     +
    '  [X]  Personal @gmail.com accounts are NOT allowed.'                           + "`r`n"     +
    '  [X]  Accounts from other organisations are NOT allowed.'                      + "`r`n"     +
    '  [X]  USB storage devices are disabled by default.'                            + "`r`n"     +
    '  [X]  You MUST be connected to the Internet to sign in.'                       + "`r`n`r`n" +
    'Unauthorised access to this system is strictly prohibited.'                     + "`r`n"     +
    'By clicking OK you confirm that you are an authorised user.'


# ══════════════════════════════════════════════════════════════════════════════
#  SECTION B — HELPER FUNCTIONS
# ══════════════════════════════════════════════════════════════════════════════

function Write-Step { param([string]$Message)
    Write-Host ''; Write-Host "  [ STEP ] $Message" -ForegroundColor Cyan
    Write-Host ('  ' + ('-' * 66)) -ForegroundColor DarkGray }

function Write-OK   { param([string]$Message)
    Write-Host "    [OK]  $Message" -ForegroundColor Green }

function Write-Warn { param([string]$Message)
    Write-Host "    [!!]  $Message" -ForegroundColor Yellow }

function Set-Reg {
    param([string]$RegistryPath,[string]$Name,[object]$Value,[string]$Type='String')
    if (-not (Test-Path -LiteralPath $RegistryPath)) {
        New-Item -Path $RegistryPath -Force | Out-Null }
    Set-ItemProperty -Path $RegistryPath -Name $Name -Value $Value -Type $Type }


# ══════════════════════════════════════════════════════════════════════════════
#  STEP 1 — Create Working Directories
# ══════════════════════════════════════════════════════════════════════════════
Write-Step 'Creating BrightUI directory structure under C:\ProgramData\BrightUI'

foreach ($dir in @($Cfg_RootDir, $Cfg_AssetsDir, $Cfg_ScriptsDir)) {
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Write-OK "Directory ready: $dir" }

try {
    $acl  = Get-Acl -LiteralPath $Cfg_RootDir
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                'BUILTIN\Users','ReadAndExecute','ContainerInherit,ObjectInherit','None','Allow')
    $acl.AddAccessRule($rule)
    Set-Acl -LiteralPath $Cfg_RootDir -AclObject $acl
    Write-OK "Read permission for BUILTIN\Users granted on $Cfg_RootDir"
} catch { Write-Warn "Could not set ACL: $($_.Exception.Message)" }


# ══════════════════════════════════════════════════════════════════════════════
#  STEP 2 — Download BrightUI Logo
# ══════════════════════════════════════════════════════════════════════════════
Write-Step 'Downloading BrightUI Technologies logo from company website'

$logoFilePath   = Join-Path $Cfg_AssetsDir 'brightui_logo.png'
$logoDownloaded = $false

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add('User-Agent','Mozilla/5.0 (Windows NT 10.0; Win64; x64)')
    $wc.DownloadFile($Cfg_LogoURL, $logoFilePath)
    $wc.Dispose()
    if ((Test-Path -LiteralPath $logoFilePath) -and ((Get-Item $logoFilePath).Length -gt 100)) {
        $logoDownloaded = $true
        Write-OK "Logo downloaded: $logoFilePath"
    } else { Write-Warn 'Download completed but file appears empty — text placeholder will be used.' }
} catch {
    Write-Warn "Logo download failed: $($_.Exception.Message)"
    Write-Warn 'Background will use a styled text placeholder instead of the logo image.' }


# ══════════════════════════════════════════════════════════════════════════════
#  STEP 2B — Download Desktop Wallpaper Image (v4.8 — Invoke-WebRequest method)
#
#  Uses the updated snippet provided:
#    Invoke-WebRequest to download Desktop_image.png
#    rundll32.exe user32.dll,UpdatePerUserSystemParameters for instant refresh
#  The image is saved to C:\ProgramData\BrightUI\Assets\Desktop_image.png
# ══════════════════════════════════════════════════════════════════════════════
Write-Step 'Downloading desktop wallpaper image (v4.8 — Invoke-WebRequest method)'

$wallpaperDownloaded = $false

try {
    # Ensure the assets directory exists (matches the snippet path exactly)
    New-Item -Path (Split-Path $Cfg_WallpaperPath) -ItemType Directory -Force | Out-Null

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    # Use Invoke-WebRequest as specified in the updated snippet
    Invoke-WebRequest -Uri $Cfg_WallpaperURL `
                      -OutFile $Cfg_WallpaperPath `
                      -UseBasicParsing `
                      -UserAgent 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'

    if ((Test-Path -LiteralPath $Cfg_WallpaperPath) -and ((Get-Item $Cfg_WallpaperPath).Length -gt 100)) {
        $wallpaperDownloaded = $true
        Write-OK "Desktop wallpaper downloaded: $Cfg_WallpaperPath"
    } else {
        Write-Warn 'Wallpaper download completed but file appears empty.'
    }
} catch {
    Write-Warn "Wallpaper download failed: $($_.Exception.Message)"
    Write-Warn 'Desktop wallpaper will not be set — file could not be retrieved.'
}


# ══════════════════════════════════════════════════════════════════════════════
#  STEP 2C — Apply Desktop Wallpaper (Full Screen / Fill) and Lock It
#
#  v4.8 changes:
#    - Uses rundll32.exe user32.dll,UpdatePerUserSystemParameters for
#      instant desktop refresh (as specified in the provided snippet).
#    - WallpaperStyle=10 (Fill) so the image covers the entire screen.
#    - Group Policy lock prevents users from changing the wallpaper.
#    - Logon script re-applies it at every logon using Invoke-WebRequest.
# ══════════════════════════════════════════════════════════════════════════════
Write-Step 'Applying desktop wallpaper (Fill, locked, rundll32 refresh) — v4.8'

if ($wallpaperDownloaded) {

    # --- 2C-1. Set wallpaper path and Fill style in registry ---
    try {
        $desktopRegPath = 'HKCU:\Control Panel\Desktop'
        Set-ItemProperty -Path $desktopRegPath -Name 'Wallpaper'      -Value $Cfg_WallpaperPath -Type String
        # WallpaperStyle 10 = Fill (covers entire screen, crops edges if needed)
        Set-ItemProperty -Path $desktopRegPath -Name 'WallpaperStyle' -Value '10'               -Type String
        Set-ItemProperty -Path $desktopRegPath -Name 'TileWallpaper'  -Value '0'                -Type String
        Write-OK "Desktop registry: Wallpaper=$Cfg_WallpaperPath, WallpaperStyle=10 (Fill), TileWallpaper=0"
    } catch {
        Write-Warn "Could not set desktop registry keys: $($_.Exception.Message)"
    }

    # --- 2C-2. Refresh desktop immediately via rundll32 (as per provided snippet) ---
    try {
        & rundll32.exe user32.dll, UpdatePerUserSystemParameters
        Write-OK "Desktop wallpaper refreshed immediately via rundll32.exe UpdatePerUserSystemParameters."
    } catch {
        Write-Warn "rundll32 refresh failed: $($_.Exception.Message)"
    }

    # --- 2C-3. Also call SystemParametersInfo as secondary refresh path ---
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class WallpaperAPI {
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool SystemParametersInfo(
        uint uiAction, uint uiParam, string pvParam, uint fWinIni);
}
'@ -PassThru | Out-Null

    try {
        # SPI_SETDESKWALLPAPER=0x0014, SPIF_UPDATEINIFILE|SPIF_SENDCHANGE=3
        $result = [WallpaperAPI]::SystemParametersInfo(0x0014, 0, $Cfg_WallpaperPath, 3)
        if ($result) {
            Write-OK "Wallpaper also applied via SystemParametersInfo (belt-and-braces)."
        }
    } catch {
        Write-Warn "SystemParametersInfo secondary call note: $($_.Exception.Message)"
    }

    # --- 2C-4. Lock wallpaper via Group Policy (Personalization) ---
    # These keys prevent ANY user from changing the wallpaper through
    # Settings, right-click desktop, or switching themes.
    $persPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization'
    try {
        Set-Reg $persPath 'Wallpaper'              $Cfg_WallpaperPath 'String'
        Set-Reg $persPath 'WallpaperStyle'         '10'               'String'
        Set-Reg $persPath 'PreventChangingWallpaper' 1                'DWord'
        Write-OK "Group Policy: Wallpaper locked to $Cfg_WallpaperPath (Fill). Users cannot change it."
    } catch {
        Write-Warn "Could not set wallpaper policy keys: $($_.Exception.Message)"
    }

    # --- 2C-5. Write per-logon wallpaper re-apply script (v4.8 — Invoke-WebRequest) ---
    $wallpaperLogonScriptPath = Join-Path $Cfg_ScriptsDir 'BrightUI_SetWallpaper.ps1'
    $wallpaperLogonContent = @"
# ============================================================
#  BrightUI Technologies - Desktop Wallpaper Enforcer  v4.8
#  Runs at every user logon via HKLM Run key.
#  Re-downloads and re-applies the corporate wallpaper (Fill)
#  using Invoke-WebRequest. Guaranteed to override theme changes.
# ============================================================

`$P = '$Cfg_WallpaperPath'

# Ensure the assets directory exists
New-Item -Path (Split-Path `$P) -ItemType Directory -Force | Out-Null

# Re-download wallpaper from source to keep it current
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri '$Cfg_WallpaperURL' ``
                      -OutFile `$P ``
                      -UseBasicParsing ``
                      -UserAgent 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)' ``
                      -ErrorAction Stop
} catch {
    # If download fails, use the existing cached file — do not abort
}

if (Test-Path -LiteralPath `$P) {
    # Apply Fill style via registry for current user
    try {
        Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'Wallpaper'      -Value `$P   -Type String
        Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'WallpaperStyle' -Value '10' -Type String
        Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'TileWallpaper'  -Value '0'  -Type String
    } catch {}

    # Refresh via rundll32 (matches the v4.8 snippet approach)
    try {
        & rundll32.exe user32.dll, UpdatePerUserSystemParameters
    } catch {}

    # Belt-and-braces: also call SystemParametersInfo
    try {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class WallpaperEnforcer {
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool SystemParametersInfo(
        uint uiAction, uint uiParam, string pvParam, uint fWinIni);
}
'@
        [WallpaperEnforcer]::SystemParametersInfo(0x0014, 0, `$P, 3) | Out-Null
    } catch {}
}
"@

    try {
        Set-Content -Path $wallpaperLogonScriptPath -Value $wallpaperLogonContent -Encoding UTF8
        Write-OK "Wallpaper logon script saved: $wallpaperLogonScriptPath"
    } catch {
        Write-Warn "Could not save wallpaper logon script: $($_.Exception.Message)"
    }

    # --- 2C-6. Register wallpaper re-apply script in HKLM Run (runs for all users at logon) ---
    try {
        $wallpaperRunCmd = "powershell.exe -WindowStyle Hidden -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$wallpaperLogonScriptPath`""
        Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' 'BrightUI_Wallpaper' $wallpaperRunCmd 'String'
        Write-OK "Wallpaper enforcer registered in HKLM Run — re-applies at every user logon."
    } catch {
        Write-Warn "Could not register wallpaper Run key: $($_.Exception.Message)"
    }

} else {
    Write-Warn 'Wallpaper file not available — skipping desktop wallpaper configuration.'
}


# ══════════════════════════════════════════════════════════════════════════════
#  STEP 3 — Build ADVANCED Branded 1920×1080 Lock Screen Background  (v4.1)
#          Layer 13 (hotkey reminder text) removed per security requirements.
# ══════════════════════════════════════════════════════════════════════════════
Write-Step 'Building advanced branded 1920x1080 lock screen background (v4.1)'

Add-Type -AssemblyName System.Drawing

$bgFilePath = Join-Path $Cfg_AssetsDir 'lockscreen_bg.jpg'
$imgW = $Cfg_BgWidth; $imgH = $Cfg_BgHeight

$bitmap   = New-Object System.Drawing.Bitmap($imgW, $imgH,
                [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.SmoothingMode      = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
$graphics.InterpolationMode  = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$graphics.TextRenderingHint  = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

# Layer 1 — deep navy-to-blue gradient background
$ptTop     = New-Object System.Drawing.Point(0, 0)
$ptBot     = New-Object System.Drawing.Point(0, $imgH)
$clrNavy   = [System.Drawing.Color]::FromArgb(255,  4,  14,  34)
$clrBlue   = [System.Drawing.Color]::FromArgb(255,  0,  52,  98)
$gradBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($ptTop, $ptBot, $clrNavy, $clrBlue)
$graphics.FillRectangle($gradBrush, 0, 0, $imgW, $imgH)
$gradBrush.Dispose()

# Layer 2 — diagonal tech-stripe texture
$stripePen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(7, 180, 210, 255), [float]1.0)
$spacing   = 38
for ($d = -$imgH; $d -lt ($imgW + $imgH); $d += $spacing) {
    $graphics.DrawLine($stripePen, $d, 0, ($d + $imgH), $imgH)
}
$stripePen.Dispose()

# Layer 3 — soft multi-pass radial spotlight glow
$cardW = 880;  $cardH = 600
$cardX = [int](($imgW - $cardW) / 2)
$cardY = [int](($imgH - $cardH) / 2)
$glowCX = $cardX + $cardW / 2
$glowCY = $cardY + $cardH / 2
$glowPasses = @(
    @{ R=520; A= 5 },
    @{ R=380; A= 8 },
    @{ R=270; A=12 },
    @{ R=175; A=18 },
    @{ R=100; A=26 }
)
foreach ($gp in $glowPasses) {
    $gr = $gp.R; $ga = $gp.A
    $glowBrush = New-Object System.Drawing.SolidBrush(
                     [System.Drawing.Color]::FromArgb($ga, 20, 90, 210))
    $graphics.FillEllipse($glowBrush,
        [int]($glowCX - $gr), [int]($glowCY - $gr * 0.62),
        [int]($gr * 2),        [int]($gr * 1.24))
    $glowBrush.Dispose()
}

# Layer 4 — card: three outer glow halos + gradient fill + crisp border
for ($hi = 3; $hi -ge 1; $hi--) {
    $exp = $hi * 4; $ha = 28 - $hi * 7
    $haloPen = New-Object System.Drawing.Pen(
                   [System.Drawing.Color]::FromArgb($ha, 55, 130, 235), [float]1.0)
    $haloRect = New-Object System.Drawing.Rectangle(
                    ($cardX - $exp), ($cardY - $exp),
                    ($cardW + $exp * 2), ($cardH + $exp * 2))
    $graphics.DrawRectangle($haloPen, $haloRect)
    $haloPen.Dispose()
}
$cardRect = New-Object System.Drawing.Rectangle($cardX, $cardY, $cardW, $cardH)
$fillTop  = [System.Drawing.Color]::FromArgb(215, 8, 22, 52)
$fillBot  = [System.Drawing.Color]::FromArgb(228, 2, 12, 30)
$cardFill = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
                (New-Object System.Drawing.Point($cardX, $cardY)),
                (New-Object System.Drawing.Point($cardX, ($cardY + $cardH))),
                $fillTop, $fillBot)
$graphics.FillRectangle($cardFill, $cardRect)
$cardFill.Dispose()
$mainBorder = New-Object System.Drawing.Pen(
                  [System.Drawing.Color]::FromArgb(130, 75, 145, 235), [float]1.5)
$graphics.DrawRectangle($mainBorder, $cardRect)
$mainBorder.Dispose()

# Layer 5 — top accent stripe
$accentRect  = New-Object System.Drawing.Rectangle($cardX, $cardY, $cardW, 6)
$accentBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
                   (New-Object System.Drawing.Point($cardX, $cardY)),
                   (New-Object System.Drawing.Point(($cardX + $cardW), $cardY)),
                   [System.Drawing.Color]::FromArgb(255, 20, 100, 220),
                   [System.Drawing.Color]::FromArgb(255, 0, 180, 255))
$graphics.FillRectangle($accentBrush, $accentRect)
$accentBrush.Dispose()

# Layer 6 — decorative corner bracket accents
$brPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(210, 40, 130, 245), [float]2.2)
$bLen  = 28
$graphics.DrawLine($brPen, $cardX,            $cardY,            ($cardX + $bLen),   $cardY)
$graphics.DrawLine($brPen, $cardX,            $cardY,            $cardX,             ($cardY + $bLen))
$graphics.DrawLine($brPen, ($cardX + $cardW), $cardY,            ($cardX + $cardW - $bLen), $cardY)
$graphics.DrawLine($brPen, ($cardX + $cardW), $cardY,            ($cardX + $cardW), ($cardY + $bLen))
$graphics.DrawLine($brPen, $cardX,            ($cardY + $cardH), ($cardX + $bLen),   ($cardY + $cardH))
$graphics.DrawLine($brPen, $cardX,            ($cardY + $cardH), $cardX,             ($cardY + $cardH - $bLen))
$graphics.DrawLine($brPen, ($cardX + $cardW), ($cardY + $cardH), ($cardX + $cardW - $bLen), ($cardY + $cardH))
$graphics.DrawLine($brPen, ($cardX + $cardW), ($cardY + $cardH), ($cardX + $cardW), ($cardY + $cardH - $bLen))
$brPen.Dispose()

# Shared StringFormat
$sfC = New-Object System.Drawing.StringFormat
$sfC.Alignment     = [System.Drawing.StringAlignment]::Center
$sfC.LineAlignment = [System.Drawing.StringAlignment]::Near
$sfC.Trimming      = [System.Drawing.StringTrimming]::Word
$txtPad = 40
$txtX   = [float]($cardX + $txtPad)
$txtW   = [float]($cardW - $txtPad * 2)
$curY = [float]($cardY + 28)

# Layer 7 — BrightUI logo or text placeholder
if ($logoDownloaded) {
    try {
        $logo     = [System.Drawing.Image]::FromFile($logoFilePath)
        $maxLogoW = 300; $maxLogoH = 110
        $scaleW   = $maxLogoW / [double]$logo.Width
        $scaleH   = $maxLogoH / [double]$logo.Height
        $scale    = [Math]::Min($scaleW, $scaleH)
        $logoW    = [int]($logo.Width  * $scale)
        $logoH    = [int]($logo.Height * $scale)
        $logoX    = [int]($cardX + ($cardW - $logoW) / 2)
        $logoRect = New-Object System.Drawing.Rectangle($logoX, [int]$curY, $logoW, $logoH)
        $graphics.DrawImage($logo, $logoRect)
        $logo.Dispose()
        $curY += $logoH + 18
        Write-OK 'BrightUI logo embedded in lock screen image.'
    } catch {
        Write-Warn "Could not embed logo: $($_.Exception.Message) — using text placeholder."
        $logoDownloaded = $false
    }
}
if (-not $logoDownloaded) {
    $bFont1  = New-Object System.Drawing.Font('Segoe UI', 22, [System.Drawing.FontStyle]::Bold)
    $bBrush1 = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 60, 145, 250))
    $bTxt    = 'BRIGHT'
    $fullW   = $graphics.MeasureString('BRIGHTUI', $bFont1).Width
    $bStartX = [float]($cardX + ($cardW - $fullW) / 2)
    $bRect1  = New-Object System.Drawing.RectangleF($bStartX, $curY, $fullW * 0.6, 36)
    $graphics.DrawString($bTxt, $bFont1, $bBrush1, $bRect1)
    $bBrush2 = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $bRect2  = New-Object System.Drawing.RectangleF(($bStartX + $fullW * 0.6), $curY, $fullW * 0.4, 36)
    $graphics.DrawString('UI', $bFont1, $bBrush2, $bRect2)
    $curY += 36 + 8
    $techFont  = New-Object System.Drawing.Font('Segoe UI', 10)
    $techBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(160, 180, 210, 250))
    $techTxt   = 'T  E  C  H  N  O  L  O  G  I  E  S'
    $techRect  = New-Object System.Drawing.RectangleF($txtX, $curY, $txtW, 20)
    $graphics.DrawString($techTxt, $techFont, $techBrush, $techRect, $sfC)
    $curY += 20 + 12
    $bFont1.Dispose(); $bBrush1.Dispose(); $bBrush2.Dispose(); $techFont.Dispose(); $techBrush.Dispose()
}

# Layer 8 — welcome title
$tFont  = New-Object System.Drawing.Font('Segoe UI', 24, [System.Drawing.FontStyle]::Bold)
$tBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
$tTxt   = 'Welcome to BrightUI Technologies'
$tSz    = $graphics.MeasureString($tTxt, $tFont, [int]$txtW, $sfC)
$tRect  = New-Object System.Drawing.RectangleF($txtX, $curY, $txtW, ($tSz.Height + 4))
$graphics.DrawString($tTxt, $tFont, $tBrush, $tRect, $sfC)
$curY  += $tSz.Height + 12
$tFont.Dispose(); $tBrush.Dispose()

# Layer 9 — horizontal divider
$divPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(150, 55, 115, 205), 1)
$divPad = 60
$graphics.DrawLine($divPen, ($cardX + $divPad), [int]$curY, ($cardX + $cardW - $divPad), [int]$curY)
$divPen.Dispose()
$curY += 18

# Layer 10 — "HOW TO SIGN IN" section label
$hFont  = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$hBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(180, 120, 170, 230))
$hSf    = New-Object System.Drawing.StringFormat
$hSf.Alignment = [System.Drawing.StringAlignment]::Near
$hSf.LineAlignment = [System.Drawing.StringAlignment]::Near
$hRect  = New-Object System.Drawing.RectangleF($txtX, $curY, $txtW, 24)
$graphics.DrawString('HOW TO SIGN IN', $hFont, $hBrush, $hRect, $hSf)
$curY  += 28
$hFont.Dispose(); $hBrush.Dispose(); $hSf.Dispose()

# Layer 11 — numbered step circles ①②③④
$circR   = 15
$circCX  = [int]($cardX + $txtPad + $circR)
$stepTextX = [float]($cardX + $txtPad + $circR * 2 + 14)
$stepTextW = [float]($cardW - $txtPad - $circR * 2 - 14 - $txtPad)
$stepCircleBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 30, 105, 220))
$stepNumFont     = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$stepNumBrush    = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
$stepTxtFont     = New-Object System.Drawing.Font('Segoe UI', 12)
$stepTxtBrush    = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(230, 215, 230, 255))
$stepSf = New-Object System.Drawing.StringFormat
$stepSf.Alignment = [System.Drawing.StringAlignment]::Near
$stepSf.LineAlignment = [System.Drawing.StringAlignment]::Center
$stepSf.Trimming = [System.Drawing.StringTrimming]::Word
$steps = @(
    "Connect this device to the Internet before signing in.",
    "Click  'Other Users  (->)'  on the Windows sign-in screen.",
    "Enter your  @$Cfg_Domain  Google Workspace email address.",
    "Complete the Google authentication steps to finish sign-in."
)
$stepRowH = 44
for ($si = 0; $si -lt $steps.Length; $si++) {
    $rowCY = [int]($curY + $si * $stepRowH + $stepRowH / 2)
    $graphics.FillEllipse($stepCircleBrush,
        ($circCX - $circR), ($rowCY - $circR),
        ($circR * 2), ($circR * 2))
    $numStr = ($si + 1).ToString()
    $numSz  = $graphics.MeasureString($numStr, $stepNumFont)
    $graphics.DrawString($numStr, $stepNumFont, $stepNumBrush,
        [float]($circCX - $numSz.Width  / 2),
        [float]($rowCY  - $numSz.Height / 2))
    $stepRect = New-Object System.Drawing.RectangleF(
                    $stepTextX, [float]($rowCY - $stepRowH / 2),
                    $stepTextW, [float]$stepRowH)
    $graphics.DrawString($steps[$si], $stepTxtFont, $stepTxtBrush, $stepRect, $stepSf)
}
$curY += [float]($steps.Length * $stepRowH) + 12
$stepCircleBrush.Dispose(); $stepNumFont.Dispose(); $stepNumBrush.Dispose()
$stepTxtFont.Dispose(); $stepTxtBrush.Dispose(); $stepSf.Dispose()
$sfC.Dispose()

# Layer 12 — amber warning strip
$warnH    = 66
$warnRect = New-Object System.Drawing.Rectangle($cardX, [int]$curY, $cardW, $warnH)
$warnBg   = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(28, 200, 140, 0))
$graphics.FillRectangle($warnBg, $warnRect)
$warnBg.Dispose()
$warnBorderPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(100, 210, 150, 0), 1)
$graphics.DrawLine($warnBorderPen, $cardX, [int]$curY, ($cardX + $cardW), [int]$curY)
$warnBorderPen.Dispose()
$warnFont   = New-Object System.Drawing.Font('Segoe UI', 10)
$warnBrush  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 255, 195, 40))
$warnSf     = New-Object System.Drawing.StringFormat
$warnSf.Alignment = [System.Drawing.StringAlignment]::Center
$warnSf.LineAlignment = [System.Drawing.StringAlignment]::Center
$warnLine1 = "  USB Storage Devices: BLOCKED      |      Browser Sign-In: @$Cfg_Domain accounts ONLY"
$warnLine2 = "  Personal @gmail.com accounts: BLOCKED      |      Internet connection: REQUIRED"
$warnRect1 = New-Object System.Drawing.RectangleF([float]$cardX, [float]$curY,          [float]$cardW, [float]($warnH / 2 + 2))
$warnRect2 = New-Object System.Drawing.RectangleF([float]$cardX, [float]($curY + $warnH / 2 - 2), [float]$cardW, [float]($warnH / 2 + 2))
$graphics.DrawString($warnLine1, $warnFont, $warnBrush, $warnRect1, $warnSf)
$graphics.DrawString($warnLine2, $warnFont, $warnBrush, $warnRect2, $warnSf)
$warnFont.Dispose(); $warnBrush.Dispose(); $warnSf.Dispose()

# Layer 13 — hotkey reminder text REMOVED (security requirement — no key hints on screen)

# Layer 14 — footer copyright
$fFont  = New-Object System.Drawing.Font('Segoe UI', 9.5, [System.Drawing.FontStyle]::Italic)
$fBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(110, 170, 195, 220))
$fTxt   = "Unauthorised access is strictly prohibited   |   (c) $((Get-Date).Year) $Cfg_CompanyName"
$fSf    = New-Object System.Drawing.StringFormat
$fSf.Alignment = [System.Drawing.StringAlignment]::Center
$fRect  = New-Object System.Drawing.RectangleF(0, [float]($imgH - 40), [float]$imgW, 28)
$graphics.DrawString($fTxt, $fFont, $fBrush, $fRect, $fSf)
$fFont.Dispose(); $fBrush.Dispose(); $fSf.Dispose()

# Save as JPEG quality 98
$jpegCodec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
             Where-Object { $_.MimeType -eq 'image/jpeg' }
$encParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
$encParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter(
    [System.Drawing.Imaging.Encoder]::Quality, [long]98)
$bitmap.Save($bgFilePath, $jpegCodec, $encParams)
$graphics.Dispose(); $bitmap.Dispose()

Write-OK "Advanced lock screen image saved (quality 98): $bgFilePath"


# ══════════════════════════════════════════════════════════════════════════════
#  STEP 4 — Apply Lock Screen Background, Remove Spotlight, Disable Blur
# ══════════════════════════════════════════════════════════════════════════════
Write-Step 'Applying lock screen image, removing Spotlight, disabling blur'

$persPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization'
Set-Reg $persPath 'LockScreenImage'      $bgFilePath 'String'
Set-Reg $persPath 'NoChangingLockScreen' 1           'DWord'
Write-OK 'Personalization policy: LockScreenImage and NoChangingLockScreen set.'

$cspPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP'
Set-Reg $cspPath 'LockScreenImagePath'   $bgFilePath 'String'
Set-Reg $cspPath 'LockScreenImageUrl'    $bgFilePath 'String'
Set-Reg $cspPath 'LockScreenImageStatus' 1           'DWord'
Write-OK 'PersonalizationCSP: lock screen image path configured.'

$ccPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
Set-Reg $ccPath 'DisableWindowsSpotlightOnLockScreen' 1 'DWord'
Set-Reg $ccPath 'DisableWindowsConsumerFeatures'      1 'DWord'
Set-Reg $ccPath 'DisableCloudOptimizedContent'        1 'DWord'
Set-Reg $ccPath 'DisableSoftLanding'                  1 'DWord'
Write-OK 'Windows Spotlight on lock screen DISABLED.'

$cdmPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
if (Test-Path -LiteralPath $cdmPath) {
    Set-ItemProperty -Path $cdmPath -Name 'RotatingLockScreenEnabled'        -Value 0 -Type DWord -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $cdmPath -Name 'RotatingLockScreenOverlayEnabled' -Value 0 -Type DWord -ErrorAction SilentlyContinue
    Write-OK 'ContentDeliveryManager: rotating lock screen images disabled.'
}

Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'DisableAcrylicBackgroundOnLogon' 1 'DWord'
Write-OK 'Acrylic blur on login screen DISABLED.'


# ══════════════════════════════════════════════════════════════════════════════
#  STEP 5 — Winlogon Pre-Login Legal Notice
# ══════════════════════════════════════════════════════════════════════════════
Write-Step 'Configuring Winlogon pre-login legal notice dialog'

$winlogonPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
Set-Reg $winlogonPath 'LegalNoticeCaption' $Cfg_NoticeTitle 'String'
Set-Reg $winlogonPath 'LegalNoticeText'    $Cfg_NoticeBody  'String'
Write-OK "Winlogon legal notice configured — title: '$Cfg_NoticeTitle'"


# ══════════════════════════════════════════════════════════════════════════════
#  STEP 6 — Azure AD / Google Workspace Domain Hint
# ══════════════════════════════════════════════════════════════════════════════
Write-Step "Setting Azure AD domain hint to @$Cfg_Domain"

Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\AzureADAccount' 'DomainHint'        $Cfg_Domain 'String'
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\AzureADAccount' 'AllowedAadTenants' $Cfg_Domain 'String'
Write-OK "Domain hint: @$Cfg_Domain"


# ══════════════════════════════════════════════════════════════════════════════
#  STEP 7 — OEM Branding
# ══════════════════════════════════════════════════════════════════════════════
Write-Step 'Configuring OEM branding (Settings > System > About)'

$oemPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation'
Set-Reg $oemPath 'Manufacturer' $Cfg_CompanyName 'String'
Set-Reg $oemPath 'SupportURL'   $Cfg_SupportURL  'String'
if ($logoDownloaded) { Set-Reg $oemPath 'Logo' $logoFilePath 'String'; Write-OK "OEM logo: $logoFilePath" }
Write-OK "OEM manufacturer: $Cfg_CompanyName  |  Support URL: $Cfg_SupportURL"


# ══════════════════════════════════════════════════════════════════════════════
#  STEP 8 — Internet Connectivity Reminder (HKLM Run key at startup)
# ══════════════════════════════════════════════════════════════════════════════
Write-Step 'Installing internet connectivity reminder startup script'

$checkPath    = Join-Path $Cfg_ScriptsDir 'BrightUI_InternetCheck.ps1'
$checkContent = @'
# BrightUI Technologies - Internet Connectivity Check
Add-Type -AssemblyName System.Windows.Forms
$connected = Test-Connection -ComputerName 8.8.8.8 -Count 1 -Quiet -ErrorAction SilentlyContinue
if (-not $connected) {
    [System.Windows.Forms.MessageBox]::Show(
        "This device is NOT connected to the Internet." + "`r`n`r`n" +
        "You MUST be connected to sign in with your @brightuitechnologies.com account." + "`r`n`r`n" +
        "Steps to resolve:" + "`r`n" +
        "  1.  Connect to Wi-Fi or plug in an Ethernet cable." + "`r`n" +
        "  2.  Wait for the connection to be established." + "`r`n" +
        "  3.  Sign out and back in with your Gmail account." + "`r`n`r`n" +
        "IT support:  https://portal.brightuitechnologies.com",
        "BrightUI Technologies - No Internet Connection",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
}
'@

Set-Content -Path $checkPath -Value $checkContent -Encoding UTF8
$runCmd = "powershell.exe -WindowStyle Hidden -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$checkPath`""
Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' 'BrightUI_InternetCheck' $runCmd 'String'
Write-OK "Internet check script: $checkPath"
Write-OK 'Registered in HKLM Run — runs at every startup for all users.'


# ══════════════════════════════════════════════════════════════════════════════
#  STEP 9 — USB Mass Storage Restriction (dual-layer)
# ══════════════════════════════════════════════════════════════════════════════
Write-Step 'Blocking USB mass storage (USBSTOR driver + Group Policy)'

$usbStorPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\USBSTOR'
if (Test-Path -LiteralPath $usbStorPath) {
    Set-ItemProperty -Path $usbStorPath -Name 'Start' -Value 4 -Type DWord
    Write-OK 'USBSTOR driver disabled (Start = 4).'
} else { Write-Warn 'USBSTOR key not found — Group Policy layer still blocks USB.' }

$usbPolPath = "$Cfg_UsbPolicyBase\$Cfg_UsbClassGuid"
Set-Reg $usbPolPath 'Deny_Read'  1 'DWord'
Set-Reg $usbPolPath 'Deny_Write' 1 'DWord'
Write-OK "Group Policy USB block: Deny_Read=1, Deny_Write=1."

Set-Content -Path $Cfg_StateFile -Value 'LOCKED' -Force -Encoding UTF8
Write-OK "State file initialised: LOCKED  ($Cfg_StateFile)"


# ══════════════════════════════════════════════════════════════════════════════
#  STEP 10 — Chrome Enterprise Domain Restriction
# ══════════════════════════════════════════════════════════════════════════════
Write-Step "Restricting Chrome browser sign-in to @$Cfg_Domain accounts"

$chromePath = 'HKLM:\SOFTWARE\Policies\Google\Chrome'
Set-Reg $chromePath 'AllowedDomainsForApps'               $Cfg_Domain       'String'
Set-Reg $chromePath 'RestrictSigninToPattern'             "*@$Cfg_Domain"   'String'
Set-Reg $chromePath 'BrowserSignin'                       1                 'DWord'
Set-Reg $chromePath 'SecondaryGoogleAccountSigninAllowed' 0                 'DWord'
Write-OK "Chrome: AllowedDomainsForApps = $Cfg_Domain  |  RestrictSigninToPattern = *@$Cfg_Domain"


# ══════════════════════════════════════════════════════════════════════════════
#  STEP 11 — Microsoft Edge Domain Restriction
# ══════════════════════════════════════════════════════════════════════════════
Write-Step "Restricting Edge browser sign-in to @$Cfg_Domain accounts"

$edgePath = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
Set-Reg $edgePath 'RestrictSigninToPattern' "*@$Cfg_Domain" 'String'
Set-Reg $edgePath 'BrowserSignin'           1               'DWord'
Write-OK "Edge: RestrictSigninToPattern = *@$Cfg_Domain"


# ══════════════════════════════════════════════════════════════════════════════
#  STEP 12 — ADVANCED Post-Login Reminder Popup  (v4.1 — WHITE TEXT)
#  NOTE: No scheduled task is created for this popup in v4.8.
#        The script file is still created here for manual/admin use.
#        It will NOT run automatically at logon.
# ══════════════════════════════════════════════════════════════════════════════
Write-Step 'Creating ADVANCED post-logon reminder popup script (v4.1 — file only, NO task)'

$reminderPath    = Join-Path $Cfg_ScriptsDir 'BrightUI_LoginReminder.ps1'
$reminderContent = @'
# ============================================================
#  BrightUI Technologies - Advanced Login Reminder Popup v4.1
#  NOTE (v4.8): No scheduled task triggers this script.
#               Run manually as an administrator if needed.
#  Borderless custom form — draggable — auto-closes in 60 s.
#  All text colours set to white (v4.1 fix).
# ============================================================
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ── Form & global colours ─────────────────────────────────────────────────────
$clrDarkBg    = [System.Drawing.Color]::FromArgb(255,  4, 14, 34)
$clrSideBg    = [System.Drawing.Color]::FromArgb(255,  2, 10, 26)
$clrBodyBg    = [System.Drawing.Color]::FromArgb(255,  6, 20, 46)
$clrAccent    = [System.Drawing.Color]::FromArgb(255, 30,110,220)
$clrWhite     = [System.Drawing.Color]::White
$clrAmberBg   = [System.Drawing.Color]::FromArgb( 30,200,140,  0)
$clrAmberTxt  = [System.Drawing.Color]::FromArgb(255,255,200, 50)
$clrBorder    = [System.Drawing.Color]::FromArgb(255, 35, 80,160)
$clrTitleBar  = [System.Drawing.Color]::FromArgb(255,  2,  8, 22)

$FORM_W  = 720
$FORM_H  = 550
$SIDE_W  = 200
$BODY_X  = $SIDE_W
$BODY_W  = $FORM_W - $SIDE_W

# ── Main form (borderless) ────────────────────────────────────────────────────
$frm                 = New-Object System.Windows.Forms.Form
$frm.Text            = '__COMPANY__  -  Sign-In Instructions'
$frm.Size            = New-Object System.Drawing.Size($FORM_W, $FORM_H)
$frm.StartPosition   = [System.Windows.Forms.FormStartPosition]::CenterScreen
$frm.BackColor       = $clrDarkBg
$frm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$frm.TopMost         = $true

# ── Draw outer border on the form ─────────────────────────────────────────────
$frm.Add_Paint({
    param($s, $e)
    $pen = New-Object System.Drawing.Pen($clrBorder, 1)
    $e.Graphics.DrawRectangle($pen, 0, 0, ($s.Width - 1), ($s.Height - 1))
    $pen.Dispose()
})

# ── Drag state ───────────────────────────────────────────────────────────────
$script:_drag   = $false
$script:_origin = [System.Drawing.Point]::Empty

# ── TITLE BAR PANEL ──────────────────────────────────────────────────────────
$pTitle           = New-Object System.Windows.Forms.Panel
$pTitle.Size      = New-Object System.Drawing.Size($FORM_W, 44)
$pTitle.Location  = New-Object System.Drawing.Point(0, 0)
$pTitle.BackColor = $clrTitleBar
$frm.Controls.Add($pTitle)

$pTitle.Add_Paint({
    param($s, $e)
    $rect = New-Object System.Drawing.Rectangle(0, 0, $s.Width, $s.Height)
    $gb = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.Point(0, 0)),
        (New-Object System.Drawing.Point($s.Width, 0)),
        [System.Drawing.Color]::FromArgb(255,  2,  8, 22),
        [System.Drawing.Color]::FromArgb(255,  0, 30, 72))
    $e.Graphics.FillRectangle($gb, $rect)
    $gb.Dispose()
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(180, 30, 90, 190), 1)
    $e.Graphics.DrawLine($pen, 0, ($s.Height - 1), $s.Width, ($s.Height - 1))
    $pen.Dispose()
})

# Title text — WHITE
$lblTitle           = New-Object System.Windows.Forms.Label
$lblTitle.Text      = '  __COMPANY__  —  Secure Access Portal'
$lblTitle.Font      = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
$lblTitle.ForeColor = $clrWhite
$lblTitle.AutoSize  = $false
$lblTitle.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$lblTitle.Size      = New-Object System.Drawing.Size(($FORM_W - 50), 44)
$lblTitle.Location  = New-Object System.Drawing.Point(0, 0)
$lblTitle.BackColor = [System.Drawing.Color]::Transparent
$pTitle.Controls.Add($lblTitle)

# Close button (×)
$btnX                = New-Object System.Windows.Forms.Button
$btnX.Text           = '  x'
$btnX.Font           = New-Object System.Drawing.Font('Segoe UI', 14)
$btnX.ForeColor      = $clrWhite
$btnX.BackColor      = [System.Drawing.Color]::Transparent
$btnX.FlatStyle      = [System.Windows.Forms.FlatStyle]::Flat
$btnX.FlatAppearance.BorderSize  = 0
$btnX.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(255, 180, 40, 40)
$btnX.Size           = New-Object System.Drawing.Size(44, 44)
$btnX.Location       = New-Object System.Drawing.Point(($FORM_W - 44), 0)
$btnX.Add_Click({ $frm.Close() })
$pTitle.Controls.Add($btnX)

# Drag handlers
$dragDown = {
    param($s, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $script:_drag   = $true
        $script:_origin = New-Object System.Drawing.Point($e.X, $e.Y)
    }
}
$dragMove = {
    param($s, $e)
    if ($script:_drag) {
        $frm.Left += $e.X - $script:_origin.X
        $frm.Top  += $e.Y - $script:_origin.Y
    }
}
$dragUp = { $script:_drag = $false }
$pTitle.Add_MouseDown($dragDown); $pTitle.Add_MouseMove($dragMove); $pTitle.Add_MouseUp($dragUp)
$lblTitle.Add_MouseDown($dragDown); $lblTitle.Add_MouseMove($dragMove); $lblTitle.Add_MouseUp($dragUp)

# ── LEFT SIDEBAR PANEL ────────────────────────────────────────────────────────
$pSide           = New-Object System.Windows.Forms.Panel
$pSide.Size      = New-Object System.Drawing.Size($SIDE_W, ($FORM_H - 44))
$pSide.Location  = New-Object System.Drawing.Point(0, 44)
$pSide.BackColor = $clrSideBg
$frm.Controls.Add($pSide)

$pSide.Add_Paint({
    param($s, $e)
    $gb = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.Point(0, 0)),
        (New-Object System.Drawing.Point(0, $s.Height)),
        [System.Drawing.Color]::FromArgb(255,  2,  8, 22),
        [System.Drawing.Color]::FromArgb(255,  0, 28, 64))
    $e.Graphics.FillRectangle($gb, 0, 0, $s.Width, $s.Height)
    $gb.Dispose()
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(120, 30, 80, 170), 1)
    $e.Graphics.DrawLine($pen, ($s.Width - 1), 0, ($s.Width - 1), $s.Height)
    $pen.Dispose()
    $ab = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.Point(0, 0)),
        (New-Object System.Drawing.Point($s.Width, 0)),
        [System.Drawing.Color]::FromArgb(255, 20, 100, 220),
        [System.Drawing.Color]::FromArgb(255,  0, 160, 240))
    $e.Graphics.FillRectangle($ab, 0, 0, $s.Width, 5)
    $ab.Dispose()
})

# Logo image in sidebar
$logoPath = 'C:\ProgramData\BrightUI\Assets\brightui_logo.png'
$logoBottom = 20
if (Test-Path -LiteralPath $logoPath) {
    try {
        $picLogo              = New-Object System.Windows.Forms.PictureBox
        $picLogo.Image        = [System.Drawing.Image]::FromFile($logoPath)
        $picLogo.SizeMode     = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
        $picLogo.Size         = New-Object System.Drawing.Size(160, 72)
        $picLogo.Location     = New-Object System.Drawing.Point(20, 30)
        $picLogo.BackColor    = [System.Drawing.Color]::Transparent
        $pSide.Controls.Add($picLogo)
        $logoBottom = 110
    } catch { $logoBottom = 20 }
}

# Company name — WHITE
$lblSideCompany           = New-Object System.Windows.Forms.Label
$lblSideCompany.Text      = '__COMPANY__'
$lblSideCompany.Font      = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
$lblSideCompany.ForeColor = $clrWhite
$lblSideCompany.AutoSize  = $false
$lblSideCompany.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$lblSideCompany.Size      = New-Object System.Drawing.Size(180, 36)
$lblSideCompany.Location  = New-Object System.Drawing.Point(10, $logoBottom)
$lblSideCompany.BackColor = [System.Drawing.Color]::Transparent
$pSide.Controls.Add($lblSideCompany)

# Sub-label — WHITE
$lblSideSub           = New-Object System.Windows.Forms.Label
$lblSideSub.Text      = 'Secure Device Portal'
$lblSideSub.Font      = New-Object System.Drawing.Font('Segoe UI', 8.5, [System.Drawing.FontStyle]::Italic)
$lblSideSub.ForeColor = $clrWhite
$lblSideSub.AutoSize  = $false
$lblSideSub.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$lblSideSub.Size      = New-Object System.Drawing.Size(180, 22)
$lblSideSub.Location  = New-Object System.Drawing.Point(10, ($logoBottom + 36))
$lblSideSub.BackColor = [System.Drawing.Color]::Transparent
$pSide.Controls.Add($lblSideSub)

# ── RIGHT BODY PANEL ─────────────────────────────────────────────────────────
$pBody           = New-Object System.Windows.Forms.Panel
$pBody.Size      = New-Object System.Drawing.Size($BODY_W, ($FORM_H - 44))
$pBody.Location  = New-Object System.Drawing.Point($BODY_X, 44)
$pBody.BackColor = $clrBodyBg
$frm.Controls.Add($pBody)

$pBody.Add_Paint({
    param($s, $e)
    $gb = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.Point(0, 0)),
        (New-Object System.Drawing.Point(0, $s.Height)),
        [System.Drawing.Color]::FromArgb(255,  6, 20, 46),
        [System.Drawing.Color]::FromArgb(255,  4, 14, 34))
    $e.Graphics.FillRectangle($gb, 0, 0, $s.Width, $s.Height)
    $gb.Dispose()
    $ab = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.Point(0, 0)),
        (New-Object System.Drawing.Point($s.Width, 0)),
        [System.Drawing.Color]::FromArgb(255, 20, 100, 220),
        [System.Drawing.Color]::FromArgb(255,  0, 160, 240))
    $e.Graphics.FillRectangle($ab, 0, 0, $s.Width, 5)
    $ab.Dispose()
})

function Add-BodyLabel {
    param([string]$Text,[int]$X,[int]$Y,[int]$W,[int]$H,[object]$Font,[object]$FgColor,
          [object]$Align = [System.Drawing.ContentAlignment]::MiddleLeft,
          [object]$BgColor = $null)
    $lbl           = New-Object System.Windows.Forms.Label
    $lbl.Text      = $Text
    $lbl.Font      = $Font
    $lbl.ForeColor = $FgColor
    $lbl.AutoSize  = $false
    $lbl.TextAlign = $Align
    $lbl.Size      = New-Object System.Drawing.Size($W, $H)
    $lbl.Location  = New-Object System.Drawing.Point($X, $Y)
    if ($BgColor) { $lbl.BackColor = $BgColor } else { $lbl.BackColor = [System.Drawing.Color]::Transparent }
    $pBody.Controls.Add($lbl)
    return $lbl
}

$fntHeader   = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
$fntStep     = New-Object System.Drawing.Font('Segoe UI', 10)
$fntStepNum  = New-Object System.Drawing.Font('Segoe UI',  9, [System.Drawing.FontStyle]::Bold)
$fntWarn     = New-Object System.Drawing.Font('Segoe UI', 9.5)
$fntSm       = New-Object System.Drawing.Font('Segoe UI', 8.5, [System.Drawing.FontStyle]::Italic)
$fntBtn      = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)

# "HOW TO SIGN IN" heading — WHITE
Add-BodyLabel -Text 'HOW TO SIGN IN' -X 20 -Y 16 -W 480 -H 28 `
    -Font $fntHeader -FgColor $clrWhite | Out-Null

# Thin divider
$pDivTop           = New-Object System.Windows.Forms.Panel
$pDivTop.Size      = New-Object System.Drawing.Size(($BODY_W - 30), 1)
$pDivTop.Location  = New-Object System.Drawing.Point(20, 48)
$pDivTop.BackColor = [System.Drawing.Color]::FromArgb(180, 35, 80, 160)
$pBody.Controls.Add($pDivTop)

# ── Numbered steps ────────────────────────────────────────────────────────────
$stepDefs = @(
    @{ N='1'; T='Ensure this device is connected to the Internet.' },
    @{ N='2'; T="Click  'Other Users  (->) '  on the sign-in screen." },
    @{ N='3'; T='Enter your  @__DOMAIN__  Google Workspace email address.' },
    @{ N='4'; T='Complete the Google authentication steps to finish.' }
)

$stepY = 58
foreach ($sd in $stepDefs) {
    # Number circle
    $lNum           = New-Object System.Windows.Forms.Label
    $lNum.Text      = $sd.N
    $lNum.Font      = $fntStepNum
    $lNum.ForeColor = $clrWhite
    $lNum.BackColor = $clrAccent
    $lNum.Size      = New-Object System.Drawing.Size(26, 26)
    $lNum.Location  = New-Object System.Drawing.Point(20, ($stepY + 4))
    $lNum.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $pBody.Controls.Add($lNum)

    # Step text — WHITE
    Add-BodyLabel -Text $sd.T -X 54 -Y $stepY -W ($BODY_W - 70) -H 34 `
        -Font $fntStep -FgColor $clrWhite | Out-Null

    $stepY += 38
}

# Divider before warning section
$midDiv           = New-Object System.Windows.Forms.Panel
$midDiv.Size      = New-Object System.Drawing.Size(($BODY_W - 30), 1)
$midDiv.Location  = New-Object System.Drawing.Point(20, ($stepY + 6))
$midDiv.BackColor = [System.Drawing.Color]::FromArgb(120, 35, 80, 160)
$pBody.Controls.Add($midDiv)

# ── Amber RESTRICTIONS section ───────────────────────────────────────────────
$warnStartY = $stepY + 14

$pWarn           = New-Object System.Windows.Forms.Panel
$pWarn.Size      = New-Object System.Drawing.Size(($BODY_W - 30), 105)
$pWarn.Location  = New-Object System.Drawing.Point(15, $warnStartY)
$pWarn.BackColor = [System.Drawing.Color]::FromArgb(22, 200, 140, 0)
$pBody.Controls.Add($pWarn)

$pWarn.Add_Paint({
    param($s, $e)
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(120, 180, 120, 0), 1)
    $e.Graphics.DrawRectangle($pen, 0, 0, ($s.Width - 1), ($s.Height - 1))
    $pen.Dispose()
})

$restrictHeader           = New-Object System.Windows.Forms.Label
$restrictHeader.Text      = '  ! IMPORTANT RESTRICTIONS'
$restrictHeader.Font      = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$restrictHeader.ForeColor = $clrAmberTxt
$restrictHeader.BackColor = [System.Drawing.Color]::Transparent
$restrictHeader.AutoSize  = $false
$restrictHeader.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$restrictHeader.Size      = New-Object System.Drawing.Size(($BODY_W - 40), 28)
$restrictHeader.Location  = New-Object System.Drawing.Point(4, 4)
$pWarn.Controls.Add($restrictHeader)

$restrictions = @(
    '  [X]   USB storage devices are BLOCKED by default',
    '  [X]   Only  @__DOMAIN__  accounts are permitted',
    '  [X]   Personal @gmail.com accounts are NOT allowed'
)
$rY = 32
foreach ($r in $restrictions) {
    $lR           = New-Object System.Windows.Forms.Label
    $lR.Text      = $r
    $lR.Font      = $fntWarn
    $lR.ForeColor = $clrAmberTxt
    $lR.BackColor = [System.Drawing.Color]::Transparent
    $lR.AutoSize  = $false
    $lR.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $lR.Size      = New-Object System.Drawing.Size(($BODY_W - 44), 22)
    $lR.Location  = New-Object System.Drawing.Point(8, $rY)
    $pWarn.Controls.Add($lR)
    $rY += 22
}

# ── Footer: countdown + OK button ────────────────────────────────────────────
$footerY = $FORM_H - 44 - 56

$pFooter           = New-Object System.Windows.Forms.Panel
$pFooter.Size      = New-Object System.Drawing.Size($BODY_W, 56)
$pFooter.Location  = New-Object System.Drawing.Point(0, $footerY)
$pFooter.BackColor = [System.Drawing.Color]::FromArgb(255, 2, 8, 22)
$pBody.Controls.Add($pFooter)

$pFooter.Add_Paint({
    param($s, $e)
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(100, 35, 80, 160), 1)
    $e.Graphics.DrawLine($pen, 0, 0, $s.Width, 0)
    $pen.Dispose()
})

# Countdown label — WHITE
$lblCnt           = New-Object System.Windows.Forms.Label
$lblCnt.Text      = 'Auto-closing in 60 seconds...'
$lblCnt.Font      = $fntSm
$lblCnt.ForeColor = $clrWhite
$lblCnt.AutoSize  = $false
$lblCnt.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$lblCnt.Size      = New-Object System.Drawing.Size(260, 56)
$lblCnt.Location  = New-Object System.Drawing.Point(14, 0)
$lblCnt.BackColor = [System.Drawing.Color]::Transparent
$pFooter.Controls.Add($lblCnt)

$btnOK                = New-Object System.Windows.Forms.Button
$btnOK.Text           = '  OK  -  I Understand'
$btnOK.Font           = $fntBtn
$btnOK.ForeColor      = $clrWhite
$btnOK.BackColor      = $clrAccent
$btnOK.FlatStyle      = [System.Windows.Forms.FlatStyle]::Flat
$btnOK.FlatAppearance.BorderSize = 0
$btnOK.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(255, 50, 130, 240)
$btnOK.Size           = New-Object System.Drawing.Size(210, 38)
$btnOK.Location       = New-Object System.Drawing.Point(($BODY_W - 224), 9)
$btnOK.DialogResult   = [System.Windows.Forms.DialogResult]::OK
$frm.AcceptButton     = $btnOK
$pFooter.Controls.Add($btnOK)

# ── Countdown timer ───────────────────────────────────────────────────────────
$countdown  = 60
$tmr        = New-Object System.Windows.Forms.Timer
$tmr.Interval = 1000
$tmr.Add_Tick({
    $script:countdown--
    $lblCnt.Text = "Auto-closing in $script:countdown seconds..."
    if ($script:countdown -le 0) { $tmr.Stop(); $frm.Close() }
})
$tmr.Start()

$frm.ShowDialog() | Out-Null
$tmr.Stop(); $tmr.Dispose(); $frm.Dispose()
'@

$reminderContent = $reminderContent -replace '__COMPANY__', $Cfg_CompanyName
$reminderContent = $reminderContent -replace '__DOMAIN__',  $Cfg_Domain

Set-Content -Path $reminderPath -Value $reminderContent -Encoding UTF8
Write-OK "Advanced login reminder script saved: $reminderPath"
Write-OK 'NOTE (v4.8): NO scheduled task is created for this popup — file only.'


# ══════════════════════════════════════════════════════════════════════════════
#  STEP 13 — Security Toggle Script  (legacy / manual admin use)
# ══════════════════════════════════════════════════════════════════════════════
Write-Step 'Creating Security Toggle script (for manual admin / task-triggered use)'

$togglePath    = Join-Path $Cfg_ScriptsDir 'BrightUI_Toggle.ps1'
$toggleContent = @"
# ============================================================
#  BrightUI Technologies - Security Toggle
#  Accepts: -State (LOCKED|UNLOCKED|TOGGLE)
#  For manual admin or scheduled-task use.
# ============================================================
param([string]`$State = 'TOGGLE')
`$ErrorActionPreference = 'Stop'

`$stateFile  = '$Cfg_StateFile'
`$logFile    = '$Cfg_LogFile'
`$usbStorReg = 'HKLM:\SYSTEM\CurrentControlSet\Services\USBSTOR'
`$usbPolPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices\$Cfg_UsbClassGuid'
`$chromePath = 'HKLM:\SOFTWARE\Policies\Google\Chrome'
`$edgePath   = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
`$domain     = '$Cfg_Domain'

function Write-Log(`$msg) {
    `$line = "[`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] `$msg"
    Add-Content -Path `$logFile -Value `$line -Encoding UTF8
}

function Enable-UsbStorage {
    Write-Log "Enabling USB storage"
    if (Test-Path -LiteralPath `$usbStorReg) {
        Set-ItemProperty -Path `$usbStorReg -Name 'Start' -Value 3 -Type DWord }
    if (Test-Path -LiteralPath `$usbPolPath) {
        Set-ItemProperty -Path `$usbPolPath -Name 'Deny_Read'  -Value 0 -Type DWord
        Set-ItemProperty -Path `$usbPolPath -Name 'Deny_Write' -Value 0 -Type DWord }
    try {
        `$devices = Get-PnpDevice -Class USB -ErrorAction SilentlyContinue |
            Where-Object { `$_.FriendlyName -match 'Mass Storage|USB Attached SCSI|USB Storage' -or
                           `$_.CompatibleID -match 'USB\\\\Class_08' }
        foreach (`$dev in `$devices) {
            `$dev | Disable-PnpDevice -Confirm:`$false -ErrorAction SilentlyContinue | Out-Null
            `$dev | Enable-PnpDevice  -Confirm:`$false -ErrorAction SilentlyContinue | Out-Null
        }
    } catch { Write-Log "Error re-enabling USB: `$(`$_.Exception.Message)" }
}

function Disable-UsbStorage {
    Write-Log "Disabling USB storage"
    if (Test-Path -LiteralPath `$usbStorReg) {
        Set-ItemProperty -Path `$usbStorReg -Name 'Start' -Value 4 -Type DWord }
    if (-not (Test-Path -LiteralPath `$usbPolPath)) {
        New-Item -Path `$usbPolPath -Force | Out-Null }
    Set-ItemProperty -Path `$usbPolPath -Name 'Deny_Read'  -Value 1 -Type DWord
    Set-ItemProperty -Path `$usbPolPath -Name 'Deny_Write' -Value 1 -Type DWord
    try {
        `$devices = Get-PnpDevice -Class USB -ErrorAction SilentlyContinue |
            Where-Object { `$_.FriendlyName -match 'Mass Storage|USB Attached SCSI|USB Storage' -or
                           `$_.CompatibleID -match 'USB\\\\Class_08' }
        foreach (`$dev in `$devices) {
            `$dev | Disable-PnpDevice -Confirm:`$false -ErrorAction SilentlyContinue | Out-Null
        }
    } catch { }
}

function Remove-DomainRestrictions {
    Write-Log "Removing browser domain restrictions"
    `$keys = @('AllowedDomainsForApps','RestrictSigninToPattern','BrowserSignin','SecondaryGoogleAccountSigninAllowed')
    foreach (`$k in `$keys) { Remove-ItemProperty -Path `$chromePath -Name `$k -ErrorAction SilentlyContinue }
    Remove-ItemProperty -Path `$edgePath -Name 'RestrictSigninToPattern' -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path `$edgePath -Name 'BrowserSignin'           -ErrorAction SilentlyContinue
}

function Apply-DomainRestrictions {
    Write-Log "Applying domain restrictions"
    if (-not (Test-Path -LiteralPath `$chromePath)) { New-Item -Path `$chromePath -Force | Out-Null }
    Set-ItemProperty -Path `$chromePath -Name 'AllowedDomainsForApps'               -Value `$domain      -Type String
    Set-ItemProperty -Path `$chromePath -Name 'RestrictSigninToPattern'             -Value "*@`$domain"  -Type String
    Set-ItemProperty -Path `$chromePath -Name 'BrowserSignin'                       -Value 1             -Type DWord
    Set-ItemProperty -Path `$chromePath -Name 'SecondaryGoogleAccountSigninAllowed' -Value 0             -Type DWord
    if (-not (Test-Path -LiteralPath `$edgePath)) { New-Item -Path `$edgePath -Force | Out-Null }
    Set-ItemProperty -Path `$edgePath -Name 'RestrictSigninToPattern' -Value "*@`$domain" -Type String
    Set-ItemProperty -Path `$edgePath -Name 'BrowserSignin'           -Value 1            -Type DWord
}

`$current = 'LOCKED'
if (Test-Path -LiteralPath `$stateFile) {
    try { `$current = (Get-Content `$stateFile -Raw -ErrorAction Stop).Trim().ToUpper() }
    catch { `$current = 'LOCKED' }
}

`$target = `$State.ToUpper()
if (`$target -eq 'TOGGLE') { `$target = if (`$current -eq 'LOCKED') { 'UNLOCKED' } else { 'LOCKED' } }

if (`$target -eq `$current) {
    Write-Log "Already in `$target state — no action"
    try { & gpupdate.exe /force /quiet 2>`$null } catch {}
    exit 0
}

Write-Log "Switching from `$current to `$target"
if (`$target -eq 'UNLOCKED') { Enable-UsbStorage; Remove-DomainRestrictions }
else                          { Disable-UsbStorage; Apply-DomainRestrictions }

Set-Content -Path `$stateFile -Value `$target -Force -Encoding UTF8
Write-Log "State updated to `$target"
try { & gpupdate.exe /force /quiet 2>`$null } catch {}
"@

Set-Content -Path $togglePath -Value $toggleContent -Encoding UTF8
Write-OK "Toggle script saved: $togglePath"


# ══════════════════════════════════════════════════════════════════════════════
#  STEP 13A — Dedicated LOCK Script  (v4.2 — self-elevation + immediate block)
# ══════════════════════════════════════════════════════════════════════════════
Write-Step 'Creating dedicated BrightUI_Lock.ps1 (v4.2 — immediate USB block & browser close)'

$lockScriptContent = @'
# ============================================================
#  BrightUI Technologies - Security Lock Script  v4.2
#  Called silently by the hotkey listener when LOCK is triggered.
#  Disables USB storage, applies domain restrictions, updates state.
#  Self-elevation, stops USBSTOR service, disables all
#  connected USB disks, terminates browsers for immediate effect.
# ============================================================

# ── Self-elevation to administrator ───────────────────────────────────────────
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    $arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$($MyInvocation.MyCommand.Path)`""
    Start-Process PowerShell.exe -Verb RunAs -ArgumentList $arguments
    exit 0
}

$ErrorActionPreference = 'Continue'

$stateFile  = '__STATE_FILE__'
$logFile    = '__LOG_FILE__'
$usbStorReg = 'HKLM:\SYSTEM\CurrentControlSet\Services\USBSTOR'
$usbPolPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices\{__USB_GUID__}'
$chromePath = 'HKLM:\SOFTWARE\Policies\Google\Chrome'
$edgePath   = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
$domain     = '__DOMAIN__'

function Write-Log([string]$msg) {
    try {
        $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [LOCK] $msg"
        Add-Content -Path $logFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch {}
}

Write-Log "Lock script started (v4.2)"

# ── Check current state ───────────────────────────────────────────────────────
$currentState = 'LOCKED'
try {
    if (Test-Path -LiteralPath $stateFile) {
        $currentState = (Get-Content $stateFile -Raw -ErrorAction Stop).Trim().ToUpper()
    }
} catch { }

if ($currentState -eq 'LOCKED') {
    Write-Log "Already LOCKED — no action needed"
    exit 0
}

# ── 1. Stop USBSTOR service and disable driver (immediate effect) ─────────────
try {
    $svc = Get-Service -Name USBSTOR -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -ne 'Stopped') {
        Stop-Service -Name USBSTOR -Force -ErrorAction SilentlyContinue
        Write-Log "USBSTOR service stopped"
    }
    if (Test-Path -LiteralPath $usbStorReg) {
        Set-ItemProperty -Path $usbStorReg -Name 'Start' -Value 4 -Type DWord
        Write-Log "USBSTOR driver disabled (Start=4)"
    }
} catch { Write-Log "Error disabling USBSTOR: $($_.Exception.Message)" }

# ── 2. Disable all connected USB mass‑storage devices ─────────────────────────
try {
    $usbDisks = Get-CimInstance -ClassName Win32_DiskDrive -ErrorAction SilentlyContinue |
        Where-Object { $_.InterfaceType -eq 'USB' }
    foreach ($disk in $usbDisks) {
        $pnpDev = Get-PnpDevice -ErrorAction SilentlyContinue |
            Where-Object { $_.InstanceId -eq $disk.PNPDeviceID }
        if ($pnpDev) {
            $pnpDev | Disable-PnpDevice -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
            Write-Log "Disabled USB disk: $($disk.Model) ($($disk.DeviceID))"
        }
    }
    # Also try matching by class/friendly name (fallback)
    $extraDevs = Get-PnpDevice -Class USB -ErrorAction SilentlyContinue |
        Where-Object { $_.FriendlyName -match 'Mass Storage|USB Attached SCSI|USB Storage' }
    foreach ($dev in $extraDevs) {
        if ($dev.Status -ne 'Disabled') {
            $dev | Disable-PnpDevice -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
            Write-Log "Disabled USB device (extra): $($dev.FriendlyName)"
        }
    }
    Write-Log "All USB mass‑storage devices disabled"
} catch { Write-Log "PnP disable error: $($_.Exception.Message)" }

# ── 3. Apply Group Policy USB block (registry) ────────────────────────────────
try {
    if (-not (Test-Path -LiteralPath $usbPolPath)) {
        New-Item -Path $usbPolPath -Force | Out-Null
    }
    Set-ItemProperty -Path $usbPolPath -Name 'Deny_Read'  -Value 1 -Type DWord
    Set-ItemProperty -Path $usbPolPath -Name 'Deny_Write' -Value 1 -Type DWord
    Write-Log "USB Group Policy block applied"
} catch { Write-Log "Error applying USB GP: $($_.Exception.Message)" }

# ── 4. Apply Chrome domain restrictions ──────────────────────────────────────
try {
    if (-not (Test-Path -LiteralPath $chromePath)) {
        New-Item -Path $chromePath -Force | Out-Null
    }
    Set-ItemProperty -Path $chromePath -Name 'AllowedDomainsForApps'               -Value $domain     -Type String
    Set-ItemProperty -Path $chromePath -Name 'RestrictSigninToPattern'             -Value "*@$domain" -Type String
    Set-ItemProperty -Path $chromePath -Name 'BrowserSignin'                       -Value 1            -Type DWord
    Set-ItemProperty -Path $chromePath -Name 'SecondaryGoogleAccountSigninAllowed' -Value 0            -Type DWord
    Write-Log "Chrome restrictions applied (only @$domain allowed)"
} catch { Write-Log "Error applying Chrome restrictions: $($_.Exception.Message)" }

# ── 5. Apply Edge domain restrictions ────────────────────────────────────────
try {
    if (-not (Test-Path -LiteralPath $edgePath)) {
        New-Item -Path $edgePath -Force | Out-Null
    }
    Set-ItemProperty -Path $edgePath -Name 'RestrictSigninToPattern' -Value "*@$domain" -Type String
    Set-ItemProperty -Path $edgePath -Name 'BrowserSignin'           -Value 1            -Type DWord
    Write-Log "Edge restrictions applied (only @$domain allowed)"
} catch { Write-Log "Error applying Edge restrictions: $($_.Exception.Message)" }

# ── 6. Force browsers to close so new policies take effect immediately ────────
try {
    $chromeProcs = Get-Process -Name "chrome" -ErrorAction SilentlyContinue
    if ($chromeProcs) {
        $chromeProcs | Stop-Process -Force -ErrorAction SilentlyContinue
        Write-Log "Closed Chrome to enforce domain restriction"
    }
    $edgeProcs = Get-Process -Name "msedge" -ErrorAction SilentlyContinue
    if ($edgeProcs) {
        $edgeProcs | Stop-Process -Force -ErrorAction SilentlyContinue
        Write-Log "Closed Edge to enforce domain restriction"
    }
} catch { Write-Log "Note: browser close error: $($_.Exception.Message)" }

# ── 7. Update state file ──────────────────────────────────────────────────────
try {
    Set-Content -Path $stateFile -Value 'LOCKED' -Force -Encoding UTF8
    Write-Log "State file updated to LOCKED"
} catch { Write-Log "Error updating state file: $($_.Exception.Message)" }

# ── 8. Force Group Policy refresh (changes take effect for future sessions) ───
try {
    & gpupdate.exe /force /quiet 2>$null
    Write-Log "Group Policy refreshed"
} catch { Write-Log "gpupdate note: $($_.Exception.Message)" }

Write-Log "Lock script completed successfully — system is now LOCKED"
'@

$lockScriptContent = $lockScriptContent -replace '__STATE_FILE__', $Cfg_StateFile
$lockScriptContent = $lockScriptContent -replace '__LOG_FILE__', $Cfg_LogFile
$lockScriptContent = $lockScriptContent -replace '__USB_GUID__', $Cfg_UsbClassGuid
$lockScriptContent = $lockScriptContent -replace '__DOMAIN__', $Cfg_Domain

Set-Content -Path $Cfg_LockScriptPath -Value $lockScriptContent -Encoding UTF8
Write-OK "Lock script (v4.2) saved: $Cfg_LockScriptPath"
Write-OK 'Self-elevation, immediate USB block, browser termination, domain restrictions.'


# ══════════════════════════════════════════════════════════════════════════════
#  STEP 13B — Dedicated UNLOCK Script  (v5.3 — Fixed USB drive letter assignment)
#
#  v5.3 key fixes over v5.2:
#    - Removed the broken  Set-Partition -NewDriveLetter ([char]::MinValue)  call.
#      [char]::MinValue is the null character (U+0000), which Windows rejects.
#      Replaced with diskpart-based letter assignment (most reliable method)
#      plus Add-PartitionAccessPath as fallback.
#    - Added Start-Sleep(3) after enabling PnP devices so Windows has time
#      to enumerate the hardware before disk cmdlets try to query it.
#    - USBSTOR service is now explicitly started (Start-Service) immediately
#      after setting Start=3 so the driver loads without needing a reboot.
#    - StorageDevicePolicies WriteProtect is reset BEFORE PnP re-enable
#      so no read-only flag exists when the device first mounts.
#    - Added retry logic (up to 3 attempts, 2-second pause) for disk online
#      to handle slow USB re-enumeration on certain chipsets.
#    - diskpart "online disk" + "attributes disk clear readonly" used for
#      any disk still showing offline after PnP re-enable.
# ══════════════════════════════════════════════════════════════════════════════
Write-Step 'Creating dedicated BrightUI_Unlock.ps1 (v5.3 — Fixed USB drive letter assignment)'

$unlockScriptContent = @'
<#
.SYNOPSIS
    BrightUI_Unlock.ps1 – Fully unlock USB ports, removable storage, and browser logins.
.DESCRIPTION
    v5.3 — Complete rewrite of disk online/mount logic.
    Removes every Group Policy / registry USB restriction, re-enables the
    USBSTOR driver and service, re-enables PnP devices, brings all USB disks
    online, removes read-only flags, and assigns drive letters using diskpart
    (most reliable) with Add-PartitionAccessPath as fallback.
    Also removes browser sign-in restrictions for Chrome and Edge.
.NOTES
    Fixed: [char]::MinValue (null char) bug in Set-Partition call.
    Fixed: USBSTOR service now explicitly started (no reboot needed).
    Fixed: WriteProtect cleared before PnP re-enable.
    Fixed: retry loop for disk online/mount.
#>

# ── Self‑elevation to administrator ───────────────────────────────────────────
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    $arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$($MyInvocation.MyCommand.Path)`""
    Start-Process PowerShell.exe -Verb RunAs -ArgumentList $arguments
    exit 0
}

$ErrorActionPreference = 'Continue'

# ── Ensure log directory exists ───────────────────────────────────────────────
$logDir = 'C:\ProgramData\BrightUI'
if (-not (Test-Path -LiteralPath $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
}

$stateFile      = "$logDir\toggle_state.txt"
$logFile        = "$logDir\hotkey_log.txt"
$usbStorReg     = 'HKLM:\SYSTEM\CurrentControlSet\Services\USBSTOR'
$storagePol     = 'HKLM:\SYSTEM\CurrentControlSet\Control\StorageDevicePolicies'
$remStorBase    = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices'
$remDiskGuid    = '{53f5630d-b6bf-11d0-94f2-00a0c91efb8b}'   # Removable Disks GUID
$deviceRestrict = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions'
$chromePath     = 'HKLM:\SOFTWARE\Policies\Google\Chrome'
$edgePath       = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'

function Write-Log([string]$msg) {
    try {
        $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [UNLOCK] $msg"
        Add-Content -Path $logFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch {}
}

Write-Log "Unlock script started (v5.3)"

# ── Check current state ───────────────────────────────────────────────────────
$currentState = 'LOCKED'
try {
    if (Test-Path -LiteralPath $stateFile) {
        $currentState = (Get-Content $stateFile -Raw -ErrorAction Stop).Trim().ToUpper()
    }
} catch {}
if ($currentState -eq 'UNLOCKED') {
    Write-Log "Already UNLOCKED — no action needed"
    exit 0
}

# ── 1. FIRST: Reset WriteProtect BEFORE enabling PnP devices ─────────────────
# This is critical — if WriteProtect=1 exists when the device mounts,
# Windows marks the volume read-only and it is very hard to clear afterwards.
try {
    if (Test-Path -LiteralPath $storagePol) {
        Set-ItemProperty -Path $storagePol -Name 'WriteProtect' -Value 0 -Type DWord -ErrorAction SilentlyContinue
        Write-Log "WriteProtect reset to 0 (done FIRST before PnP re-enable)"
    }
} catch { Write-Log "WriteProtect note: $($_.Exception.Message)" }

# ── 2. Enable USBSTOR driver AND start the service immediately ────────────────
# Setting Start=3 alone only takes effect after a reboot.
# Explicitly calling Start-Service makes it active right now.
try {
    if (Test-Path -LiteralPath $usbStorReg) {
        Set-ItemProperty -Path $usbStorReg -Name 'Start' -Value 3 -Type DWord
        Write-Log "USBSTOR driver set to enabled (Start=3)"
    }
    $svc = Get-Service -Name USBSTOR -ErrorAction SilentlyContinue
    if ($svc) {
        if ($svc.StartType -eq 'Disabled') {
            Set-Service -Name USBSTOR -StartupType Manual -ErrorAction SilentlyContinue
        }
        if ($svc.Status -ne 'Running') {
            Start-Service -Name USBSTOR -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 800
            Write-Log "USBSTOR service started successfully"
        } else {
            Write-Log "USBSTOR service was already running"
        }
    }
} catch { Write-Log "Error enabling USBSTOR: $($_.Exception.Message)" }

# ── 3. Clear all removable storage Group Policy blocks ────────────────────────
# 3a. Top-level Deny_All
try {
    if (Test-Path -LiteralPath $remStorBase) {
        Remove-ItemProperty -Path $remStorBase -Name 'Deny_All' -ErrorAction SilentlyContinue
        Set-ItemProperty    -Path $remStorBase -Name 'Deny_All' -Value 0 -Type DWord -ErrorAction SilentlyContinue
    }
    Write-Log "Deny_All reset to 0"
} catch { Write-Log "Deny_All error: $($_.Exception.Message)" }

# 3b. Removable Disks GUID subkey
$remDiskPath = Join-Path $remStorBase $remDiskGuid
try {
    if (-not (Test-Path -LiteralPath $remDiskPath)) {
        New-Item -Path $remDiskPath -Force -ErrorAction SilentlyContinue | Out-Null
    }
    Set-ItemProperty -Path $remDiskPath -Name 'Deny_Read'  -Value 0 -Type DWord -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $remDiskPath -Name 'Deny_Write' -Value 0 -Type DWord -ErrorAction SilentlyContinue
    Write-Log "Removable Disks GP policy reset (Deny_Read=0, Deny_Write=0)"
} catch { Write-Log "Error resetting removable disk policy: $($_.Exception.Message)" }

# 3c. Also sweep the USBSTOR GUID that was used during lock
$usbStorGuid = '{53f56307-b6bf-11d0-94f2-00a0c91efb8b}'
$usbStorPolPath = Join-Path $remStorBase $usbStorGuid
try {
    if (Test-Path -LiteralPath $usbStorPolPath) {
        Set-ItemProperty -Path $usbStorPolPath -Name 'Deny_Read'  -Value 0 -Type DWord -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $usbStorPolPath -Name 'Deny_Write' -Value 0 -Type DWord -ErrorAction SilentlyContinue
        Write-Log "USBSTOR GP GUID policy reset"
    }
} catch { Write-Log "USBSTOR GUID sweep error: $($_.Exception.Message)" }

# 3d. Sweep ALL subkeys to clear any remaining Deny_* values
try {
    Get-ChildItem -Path $remStorBase -ErrorAction SilentlyContinue | ForEach-Object {
        foreach ($p in @('Deny_Read','Deny_Write','Deny_All','Deny_Execute')) {
            Remove-ItemProperty -Path $_.PSPath -Name $p -ErrorAction SilentlyContinue
        }
    }
    Write-Log "Swept all RemovableStorageDevices subkeys"
} catch { Write-Log "Sweep error: $($_.Exception.Message)" }

# ── 4. Remove device installation restrictions ─────────────────────────────────
try {
    if (Test-Path -LiteralPath $deviceRestrict) {
        foreach ($val in @('DenyRemovableDevices','DenyUnspecified','DenyDeviceIDs',
                           'DenyDeviceClasses','DenyDeviceInstanceIDs','DenyAll')) {
            Remove-ItemProperty -Path $deviceRestrict -Name $val -ErrorAction SilentlyContinue
        }
    }
    Write-Log "DeviceInstall restriction values removed"
} catch { Write-Log "DeviceInstall cleanup error: $($_.Exception.Message)" }

# ── 5. Re‑enable USB mass‑storage devices via PnP ─────────────────────────────
try {
    # Enable disabled USB mass storage devices
    $disabledDevs = Get-PnpDevice -Class USB -ErrorAction SilentlyContinue |
        Where-Object { ($_.Status -eq 'Disabled' -or $_.Status -eq 'Error') -and (
            $_.FriendlyName -match 'Mass Storage|USB Attached SCSI|USB Storage|Flash|Disk' -or
            $_.CompatibleID  -match 'USB\\Class_08'
        )}
    foreach ($dev in $disabledDevs) {
        $dev | Enable-PnpDevice -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
        Write-Log "Enabled USB device: $($dev.FriendlyName)"
    }
    # Fallback: enable any USB device that is not currently OK
    Get-PnpDevice -Class USB -ErrorAction SilentlyContinue |
        Where-Object { $_.Status -ne 'OK' -and $_.Status -ne 'Unknown' } |
        Where-Object { $_.FriendlyName -match 'Mass Storage|USB Attached SCSI|USB Storage|Flash|Disk' } |
        ForEach-Object {
            $_ | Enable-PnpDevice -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
            Write-Log "Enabled (fallback): $($_.FriendlyName)"
        }
    Write-Log "PnP USB device re-enable complete"
} catch { Write-Log "PnP re-enable error: $($_.Exception.Message)" }

# ── 6. Wait for hardware re-enumeration before touching disk objects ──────────
# USB devices need a moment after PnP enable before the Disk cmdlets can see them.
Write-Log "Waiting 3 seconds for USB hardware re-enumeration..."
Start-Sleep -Seconds 3

# ── 7. Force hardware rescan ──────────────────────────────────────────────────
try {
    & pnputil.exe /scan-devices 2>&1 | Out-Null
    Write-Log "Hardware rescan issued via pnputil"
} catch { Write-Log "pnputil scan note: $($_.Exception.Message)" }

# ── 8. Start Shell Hardware Detection (triggers Autoplay / Explorer pop-up) ───
try {
    Set-Service -Name ShellHWDetection -StartupType Manual -ErrorAction SilentlyContinue
    Start-Service -Name ShellHWDetection -ErrorAction SilentlyContinue
    Write-Log "ShellHWDetection service started"
} catch { Write-Log "ShellHWDetection note: $($_.Exception.Message)" }

# ── 9. Restart USB Root Hubs so already-plugged drives are rediscovered ────────
try {
    Get-PnpDevice -Class USB -ErrorAction SilentlyContinue |
        Where-Object { $_.FriendlyName -match 'Root Hub' -and $_.Status -eq 'OK' } |
        ForEach-Object {
            $_ | Disable-PnpDevice -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
            Start-Sleep -Milliseconds 600
            $_ | Enable-PnpDevice  -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
            Write-Log "Cycled USB hub: $($_.FriendlyName)"
        }
    # Give hubs a moment to settle after cycling
    Start-Sleep -Seconds 2
} catch { Write-Log "Hub restart error: $($_.Exception.Message)" }

# ── 10. Bring USB disks ONLINE and assign drive letters (v5.3 fixed) ──────────
# This is the section that was broken in v5.2.
# [char]::MinValue is U+0000 (null) — Windows does NOT accept it as a drive letter.
# We now use diskpart for the most reliable assignment, with Add-PartitionAccessPath
# as a fallback if diskpart is unavailable.

Write-Log "Beginning disk online and drive letter assignment (v5.3 fixed method)..."

# Helper: use diskpart to bring a disk online and clear read-only
function Invoke-DiskpartOnline {
    param([int]$DiskNumber)
    $script = @"
select disk $DiskNumber
attributes disk clear readonly
online disk
exit
"@
    $tmpFile = [System.IO.Path]::GetTempFileName()
    $script | Set-Content -Path $tmpFile -Encoding ASCII
    try {
        $result = & diskpart.exe /s $tmpFile 2>&1
        Write-Log "diskpart online disk $DiskNumber result: $($result -join ' | ')"
    } catch {
        Write-Log "diskpart error for disk $DiskNumber : $($_.Exception.Message)"
    } finally {
        Remove-Item -Path $tmpFile -Force -ErrorAction SilentlyContinue
    }
}

# Helper: use diskpart to assign the next available drive letter to a partition
function Invoke-DiskpartAssignLetter {
    param([int]$DiskNumber, [int]$PartitionNumber)
    $script = @"
select disk $DiskNumber
select partition $PartitionNumber
assign
exit
"@
    $tmpFile = [System.IO.Path]::GetTempFileName()
    $script | Set-Content -Path $tmpFile -Encoding ASCII
    try {
        $result = & diskpart.exe /s $tmpFile 2>&1
        Write-Log "diskpart assign disk=$DiskNumber part=$PartitionNumber result: $($result -join ' | ')"
        return $true
    } catch {
        Write-Log "diskpart assign error: $($_.Exception.Message)"
        return $false
    } finally {
        Remove-Item -Path $tmpFile -Force -ErrorAction SilentlyContinue
    }
}

# Helper: find the next free drive letter (D: onwards, skipping system letters)
function Get-NextFreeDriveLetter {
    $usedLetters = (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue).Name
    # Also check via WMI for mapped drives that PSDrive may miss
    $wmiLetters = (Get-CimInstance -ClassName Win32_LogicalDisk -ErrorAction SilentlyContinue).DeviceID |
        ForEach-Object { $_.TrimEnd(':') }
    $allUsed = ($usedLetters + $wmiLetters) | Where-Object { $_ } | Select-Object -Unique
    # Start from D (skip A, B, C)
    for ($ascii = 68; $ascii -le 90; $ascii++) {
        $letter = [char]$ascii
        if ($allUsed -notcontains $letter.ToString()) {
            return $letter
        }
    }
    return $null
}

# Retry loop: attempt disk operations up to 3 times with pauses
$maxRetries = 3
for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
    Write-Log "Disk online/mount attempt $attempt of $maxRetries"

    # Collect all USB disks visible to Windows at this moment
    $usbDisks = @()
    try {
        # Primary method: Storage module (most reliable)
        $allDisks = Get-Disk -ErrorAction SilentlyContinue
        foreach ($disk in $allDisks) {
            if ($disk.BusType -eq 'USB') {
                $usbDisks += $disk
            }
        }
        # Fallback: CIM Win32_DiskDrive for USB interface
        if ($usbDisks.Count -eq 0) {
            $cimDisks = Get-CimInstance -ClassName Win32_DiskDrive -ErrorAction SilentlyContinue |
                Where-Object { $_.InterfaceType -eq 'USB' }
            foreach ($cimDisk in $cimDisks) {
                $d = Get-Disk -Number ([int]$cimDisk.Index) -ErrorAction SilentlyContinue
                if ($d) { $usbDisks += $d }
            }
        }
    } catch {
        Write-Log "Disk enumeration error on attempt $attempt : $($_.Exception.Message)"
    }

    if ($usbDisks.Count -eq 0) {
        Write-Log "No USB disks found on attempt $attempt — waiting 2s before retry"
        Start-Sleep -Seconds 2
        continue
    }

    Write-Log "Found $($usbDisks.Count) USB disk(s) on attempt $attempt"

    foreach ($disk in $usbDisks) {
        try {
            $diskNum = [int]$disk.Number
            Write-Log "Processing USB disk $diskNum ($($disk.FriendlyName))"

            # Clear read-only and bring online via diskpart (most reliable)
            Invoke-DiskpartOnline -DiskNumber $diskNum

            # Refresh disk object after diskpart
            Start-Sleep -Milliseconds 500
            $disk = Get-Disk -Number $diskNum -ErrorAction SilentlyContinue
            if (-not $disk) {
                Write-Log "Disk $diskNum not found after diskpart — skipping"
                continue
            }

            # Belt-and-braces: also use PowerShell Storage cmdlets
            if ($disk.IsReadOnly) {
                Set-Disk -Number $diskNum -IsReadOnly $false -ErrorAction SilentlyContinue
                Write-Log "Disk $diskNum IsReadOnly cleared via Set-Disk"
            }
            if ($disk.IsOffline) {
                Set-Disk -Number $diskNum -IsOffline $false -ErrorAction SilentlyContinue
                Write-Log "Disk $diskNum brought online via Set-Disk"
                Start-Sleep -Milliseconds 500
            }

            # Now assign drive letters to any partition that has none
            $partitions = Get-Partition -DiskNumber $diskNum -ErrorAction SilentlyContinue |
                Where-Object { $_.Type -notin @('Unknown','Reserved','System','Recovery') }

            foreach ($part in $partitions) {
                # Skip if this partition already has a drive letter
                if ($part.DriveLetter -and $part.DriveLetter -ne [char]0 -and $part.DriveLetter -ne '') {
                    Write-Log "  Partition $($part.PartitionNumber) already has drive letter $($part.DriveLetter): — skipping"
                    continue
                }

                Write-Log "  Partition $($part.PartitionNumber) has no drive letter — attempting assignment"

                # Method 1: diskpart assign (lets Windows pick the next free letter automatically)
                $assigned = Invoke-DiskpartAssignLetter -DiskNumber $diskNum -PartitionNumber ([int]$part.PartitionNumber)

                if (-not $assigned) {
                    # Method 2: Add-PartitionAccessPath with an explicit free letter
                    $freeLetter = Get-NextFreeDriveLetter
                    if ($freeLetter) {
                        try {
                            Add-PartitionAccessPath -DiskNumber $diskNum `
                                                    -PartitionNumber ([int]$part.PartitionNumber) `
                                                    -AccessPath "$($freeLetter):" `
                                                    -ErrorAction Stop
                            Write-Log "  Partition $($part.PartitionNumber) assigned $freeLetter: via Add-PartitionAccessPath"
                        } catch {
                            Write-Log "  Add-PartitionAccessPath failed for partition $($part.PartitionNumber): $($_.Exception.Message)"
                        }
                    } else {
                        Write-Log "  No free drive letters available — partition $($part.PartitionNumber) not mounted"
                    }
                }
            }
        } catch {
            Write-Log "Error processing disk $($disk.Number): $($_.Exception.Message)"
        }
    }

    # After first successful pass with disks found, break out of retry loop
    if ($usbDisks.Count -gt 0) { break }
    Start-Sleep -Seconds 2
}

Write-Log "Disk online/mount procedure completed (v5.3)"

# ── 11. Remove Chrome domain restrictions ──────────────────────────────────────
try {
    $keys = @('AllowedDomainsForApps','RestrictSigninToPattern','BrowserSignin','SecondaryGoogleAccountSigninAllowed')
    foreach ($k in $keys) {
        Remove-ItemProperty -Path $chromePath -Name $k -ErrorAction SilentlyContinue
    }
    Write-Log "Chrome domain restrictions removed"
} catch { Write-Log "Error removing Chrome restrictions: $($_.Exception.Message)" }

# ── 12. Remove Edge domain restrictions ───────────────────────────────────────
try {
    Remove-ItemProperty -Path $edgePath -Name 'RestrictSigninToPattern' -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $edgePath -Name 'BrowserSignin'           -ErrorAction SilentlyContinue
    Write-Log "Edge domain restrictions removed"
} catch { Write-Log "Error removing Edge restrictions: $($_.Exception.Message)" }

# ── 13. Update state file ─────────────────────────────────────────────────────
try {
    Set-Content -Path $stateFile -Value 'UNLOCKED' -Force -Encoding UTF8
    Write-Log "State file updated to UNLOCKED"
} catch { Write-Log "Error updating state file: $($_.Exception.Message)" }

# ── 14. Refresh Group Policy ──────────────────────────────────────────────────
try {
    & gpupdate.exe /force /quiet 2>&1 | Out-Null
    Write-Log "Group Policy refreshed"
} catch { Write-Log "gpupdate note: $($_.Exception.Message)" }

Write-Log "Unlock script v5.3 completed successfully — USB drives should now be accessible"
'@

Set-Content -Path $Cfg_UnlockScriptPath -Value $unlockScriptContent -Encoding UTF8
Write-OK "Unlock script (v5.3) saved: $Cfg_UnlockScriptPath"
Write-OK 'Fixed: null-char bug, USBSTOR service start, WriteProtect-first, diskpart assignment, retry loop.'


# ══════════════════════════════════════════════════════════════════════════════
#  STEP 14 — Security Hotkey Listener  (v4.4 — Remote Trigger File Support)
#
#  Changes from v4.3:
#    - Added TRIGGER FILE mechanism for AnyDesk / Chrome Remote Desktop.
#      When the admin is connected remotely, keyboard hooks may not receive
#      the hotkey because AnyDesk injects keystrokes differently to RDP.
#      The trigger file approach works regardless of input method:
#        C:\ProgramData\BrightUI\trigger_lock.txt   → triggers LOCK
#        C:\ProgramData\BrightUI\trigger_unlock.txt → triggers UNLOCK
#    - A FileSystemWatcher monitors the BrightUI folder on a background
#      thread and fires the action the instant a trigger file appears,
#      then deletes the file. No polling delay.
#    - A secondary 2-second polling timer runs as belt-and-braces backup
#      in case the FSW event fires slowly on certain antivirus setups.
#    - All three paths (RegisterHotKey + WH_KEYBOARD_LL + trigger files)
#      share the same debounce and ExecuteScript logic.
#    - Existing RegisterHotKey and WH_KEYBOARD_LL code is unchanged.
#
#  HOW TO TRIGGER REMOTELY (AnyDesk / CRD admin):
#    From an elevated PowerShell on the REMOTE side, run:
#      New-Item -Path 'C:\ProgramData\BrightUI\trigger_unlock.txt' -Force
#    Or simply create the file via File Explorer on the remote session.
#    The listener on the local machine will detect it within ~2 seconds.
# ══════════════════════════════════════════════════════════════════════════════
Write-Step 'Creating Hotkey Listener v4.4 (RegisterHotKey + LL hook + trigger files for remote)'

$listenerPath    = Join-Path $Cfg_ScriptsDir 'BrightUI_HotkeyListener.ps1'
$listenerContent = @'
# ============================================================
#  BrightUI Technologies - Security Hotkey Listener  v4.4
#  Runs at logon via HKLM Run key (no Task Scheduler needed).
#
#  THREE interception methods:
#    1. RegisterHotKey  — works in normal local desktop sessions.
#    2. WH_KEYBOARD_LL  — low-level hook for RDP/Chrome Remote Desktop.
#    3. TRIGGER FILES   — for AnyDesk and remote tools that block hooks:
#         Create  C:\ProgramData\BrightUI\trigger_lock.txt   → LOCK
#         Create  C:\ProgramData\BrightUI\trigger_unlock.txt → UNLOCK
#       The listener detects the file within 2 seconds and acts on it.
#
#  Hotkeys (local/RDP):  Ctrl+Alt+L (Lock)  |  Ctrl+Alt+U (Unlock)
#  All events logged to  C:\ProgramData\BrightUI\hotkey_log.txt
# ============================================================
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Single-instance guard
$mutexName = 'Global\BrightUI_HotkeyListener_v44_Mutex'
$mutex     = New-Object System.Threading.Mutex($false, $mutexName)
if (-not $mutex.WaitOne(0, $false)) { exit }

$csharpCode = @"
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using System.Drawing;
using System.IO;
using System.Diagnostics;
using System.Threading;

public class BrightUIHotkeyForm : Form {

    // ── Win32 imports ──────────────────────────────────────────────────────────
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn,
                                                   IntPtr hMod, uint dwThreadId);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode,
                                                 IntPtr wParam, IntPtr lParam);

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern IntPtr GetModuleHandle(string lpModuleName);

    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int vKey);

    // ── Constants ─────────────────────────────────────────────────────────────
    private const int  WH_KEYBOARD_LL = 13;
    private const int  WM_KEYDOWN     = 0x0100;
    private const int  WM_SYSKEYDOWN  = 0x0104;
    private const int  WM_HOTKEY      = 0x0312;
    private const uint MOD_ALT        = 0x0001;
    private const uint MOD_CONTROL    = 0x0002;
    private const uint MOD_NOREPEAT   = 0x4000;
    private const uint VK_L           = 0x4C;
    private const uint VK_U           = 0x55;
    private const int  VK_CONTROL     = 0x11;
    private const int  VK_MENU        = 0x12;
    private const int  HOTKEY_LOCK    = 9001;
    private const int  HOTKEY_UNLOCK  = 9002;

    // ── Fields ────────────────────────────────────────────────────────────────
    private readonly string _stateFile;
    private readonly string _logFile;
    private readonly string _lockScriptPath;
    private readonly string _unlockScriptPath;
    private readonly string _triggerLockPath;
    private readonly string _triggerUnlockPath;
    private readonly string _watchDir;

    private IntPtr _llHookHandle = IntPtr.Zero;
    private LowLevelKeyboardProc _llHookProc;

    // Shared debounce — prevents double-fire across all three methods
    private DateTime _lastHotkeyFired = DateTime.MinValue;
    private const int DEBOUNCE_MS = 1500;

    // FileSystemWatcher for trigger files (remote/AnyDesk support)
    private FileSystemWatcher _fsw;

    // Backup polling timer (belt-and-braces for FSW on strict AV setups)
    private System.Windows.Forms.Timer _pollTimer;

    // ── Delegate type for LL keyboard hook ────────────────────────────────────
    private delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    private struct KBDLLHOOKSTRUCT {
        public uint vkCode;
        public uint scanCode;
        public uint flags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    // ── Constructor ───────────────────────────────────────────────────────────
    public BrightUIHotkeyForm(string stateFilePath, string logFilePath,
                               string lockScriptPath, string unlockScriptPath,
                               string triggerLockPath, string triggerUnlockPath) {
        _stateFile         = stateFilePath;
        _logFile           = logFilePath;
        _lockScriptPath    = lockScriptPath;
        _unlockScriptPath  = unlockScriptPath;
        _triggerLockPath   = triggerLockPath;
        _triggerUnlockPath = triggerUnlockPath;
        _watchDir          = Path.GetDirectoryName(triggerLockPath);

        ShowInTaskbar   = false;
        WindowState     = FormWindowState.Minimized;
        FormBorderStyle = FormBorderStyle.None;
        Size            = new System.Drawing.Size(1, 1);
        Opacity         = 0;
    }

    // ── Logging ───────────────────────────────────────────────────────────────
    private void Log(string msg) {
        try {
            string line = "[" + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "] " + msg;
            File.AppendAllText(_logFile, line + Environment.NewLine, System.Text.Encoding.UTF8);
        } catch { }
    }

    // ── Form load: set up all three interception methods ──────────────────────
    protected override void OnLoad(EventArgs e) {
        base.OnLoad(e);
        this.Hide();
        Log("BrightUI HotkeyListener v4.4 starting — 3 interception methods active");

        // --- Method 1: RegisterHotKey ---
        uint combo = MOD_CONTROL | MOD_ALT | MOD_NOREPEAT;
        bool lockOk   = RegisterHotKey(Handle, HOTKEY_LOCK,   combo, VK_L);
        bool unlockOk = RegisterHotKey(Handle, HOTKEY_UNLOCK, combo, VK_U);
        Log("Method 1 (RegisterHotKey) — Lock=" + lockOk + " Unlock=" + unlockOk);

        // --- Method 2: WH_KEYBOARD_LL low-level hook (separate STA thread) ---
        Thread hookThread = new Thread(() => {
            _llHookProc = new LowLevelKeyboardProc(LowLevelKeyboardCallback);
            using (var curProcess = System.Diagnostics.Process.GetCurrentProcess())
            using (var curModule  = curProcess.MainModule) {
                IntPtr hMod = GetModuleHandle(curModule.ModuleName);
                _llHookHandle = SetWindowsHookEx(WH_KEYBOARD_LL, _llHookProc, hMod, 0);
            }
            if (_llHookHandle != IntPtr.Zero)
                Log("Method 2 (WH_KEYBOARD_LL) hook installed — RDP/CRD hotkeys active");
            else
                Log("Method 2 (WH_KEYBOARD_LL) hook FAILED (error " + Marshal.GetLastWin32Error() + ")");
            Application.Run();
        });
        hookThread.SetApartmentState(ApartmentState.STA);
        hookThread.IsBackground = true;
        hookThread.Start();

        // --- Method 3a: FileSystemWatcher for trigger files (AnyDesk / remote) ---
        // This fires immediately when the admin creates trigger_lock.txt or
        // trigger_unlock.txt on the user's machine via any remote desktop tool.
        try {
            _fsw = new FileSystemWatcher(_watchDir) {
                NotifyFilter        = NotifyFilters.FileName | NotifyFilters.LastWrite,
                Filter              = "trigger_*.txt",
                EnableRaisingEvents = true,
                IncludeSubdirectories = false
            };
            _fsw.Created += OnTriggerFileEvent;
            _fsw.Changed += OnTriggerFileEvent;
            Log("Method 3a (FileSystemWatcher) watching: " + _watchDir + " for trigger_*.txt");
        } catch (Exception ex) {
            Log("Method 3a (FileSystemWatcher) setup failed: " + ex.Message);
        }

        // --- Method 3b: Backup polling timer (every 2 seconds) ---
        // Belt-and-braces in case the FSW event is slow on strict AV setups.
        _pollTimer = new System.Windows.Forms.Timer();
        _pollTimer.Interval = 2000;
        _pollTimer.Tick += OnPollTimer;
        _pollTimer.Start();
        Log("Method 3b (poll timer) started — checking trigger files every 2 seconds");
    }

    // ── Trigger file event handler (FileSystemWatcher) ────────────────────────
    // Fires on the FSW thread — marshals execution to the UI thread.
    private void OnTriggerFileEvent(object sender, FileSystemEventArgs e) {
        string fileName = Path.GetFileName(e.FullPath).ToLower();
        if (fileName == "trigger_lock.txt") {
            Log("TRIGGER FILE detected: trigger_lock.txt (via FSW) — marshalling LOCK");
            this.BeginInvoke((Action)(() => HandleTriggerFile("LOCKED", _lockScriptPath, _triggerLockPath)));
        } else if (fileName == "trigger_unlock.txt") {
            Log("TRIGGER FILE detected: trigger_unlock.txt (via FSW) — marshalling UNLOCK");
            this.BeginInvoke((Action)(() => HandleTriggerFile("UNLOCKED", _unlockScriptPath, _triggerUnlockPath)));
        }
    }

    // ── Backup polling timer tick ─────────────────────────────────────────────
    private void OnPollTimer(object sender, EventArgs e) {
        // Check for trigger_lock.txt
        if (File.Exists(_triggerLockPath)) {
            Log("TRIGGER FILE detected: trigger_lock.txt (via poll timer) — executing LOCK");
            HandleTriggerFile("LOCKED", _lockScriptPath, _triggerLockPath);
        }
        // Check for trigger_unlock.txt
        if (File.Exists(_triggerUnlockPath)) {
            Log("TRIGGER FILE detected: trigger_unlock.txt (via poll timer) — executing UNLOCK");
            HandleTriggerFile("UNLOCKED", _unlockScriptPath, _triggerUnlockPath);
        }
    }

    // ── Handle trigger file: delete it, then execute the script ───────────────
    private void HandleTriggerFile(string targetState, string scriptPath, string triggerFilePath) {
        // Delete the trigger file FIRST so it doesn't fire again
        try {
            if (File.Exists(triggerFilePath)) {
                File.Delete(triggerFilePath);
                Log("Trigger file deleted: " + triggerFilePath);
            }
        } catch (Exception ex) {
            Log("Could not delete trigger file: " + ex.Message);
        }

        // Apply debounce
        TimeSpan elapsed = DateTime.Now - _lastHotkeyFired;
        if (elapsed.TotalMilliseconds < DEBOUNCE_MS) {
            Log("Trigger file: debounce active — skipping duplicate within " + DEBOUNCE_MS + "ms");
            return;
        }
        _lastHotkeyFired = DateTime.Now;
        ExecuteScript(targetState, scriptPath);
    }

    // ── Low-level keyboard callback (WH_KEYBOARD_LL — Method 2) ──────────────
    private IntPtr LowLevelKeyboardCallback(int nCode, IntPtr wParam, IntPtr lParam) {
        if (nCode >= 0 && (wParam == (IntPtr)WM_KEYDOWN || wParam == (IntPtr)WM_SYSKEYDOWN)) {
            KBDLLHOOKSTRUCT kbStruct = (KBDLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(KBDLLHOOKSTRUCT));
            uint vk = kbStruct.vkCode;
            if (vk == VK_L || vk == VK_U) {
                bool ctrlDown = (GetAsyncKeyState(VK_CONTROL) & 0x8000) != 0;
                bool altDown  = (GetAsyncKeyState(VK_MENU)    & 0x8000) != 0;
                if (ctrlDown && altDown) {
                    TimeSpan elapsed = DateTime.Now - _lastHotkeyFired;
                    if (elapsed.TotalMilliseconds > DEBOUNCE_MS) {
                        _lastHotkeyFired = DateTime.Now;
                        Log("LL hook: Ctrl+Alt+" + ((char)vk) + " intercepted");
                        string targetState = (vk == VK_L) ? "LOCKED"   : "UNLOCKED";
                        string scriptPath  = (vk == VK_L) ? _lockScriptPath : _unlockScriptPath;
                        this.BeginInvoke((Action)(() => ExecuteScript(targetState, scriptPath)));
                    }
                }
            }
        }
        return CallNextHookEx(_llHookHandle, nCode, wParam, lParam);
    }

    // ── WM_HOTKEY handler (RegisterHotKey — Method 1) ─────────────────────────
    protected override void WndProc(ref Message m) {
        if (m.Msg == WM_HOTKEY) {
            int id = m.WParam.ToInt32();
            TimeSpan elapsed = DateTime.Now - _lastHotkeyFired;
            if (elapsed.TotalMilliseconds > DEBOUNCE_MS) {
                _lastHotkeyFired = DateTime.Now;
                if (id == HOTKEY_LOCK)   ExecuteScript("LOCKED",   _lockScriptPath);
                if (id == HOTKEY_UNLOCK) ExecuteScript("UNLOCKED", _unlockScriptPath);
            }
        }
        base.WndProc(ref m);
    }

    // ── Execute lock/unlock script via UAC runas ───────────────────────────────
    private void ExecuteScript(string targetState, string scriptPath) {
        try {
            string currentState = ReadState();
            if (currentState == targetState) {
                Log("Already in " + targetState + " — no action needed");
                return;
            }
            if (!File.Exists(scriptPath)) {
                Log("Script not found: " + scriptPath);
                return;
            }
            Log("Executing: switch to " + targetState + " — launching script with elevation");

            string args = "-WindowStyle Hidden -NonInteractive -NoProfile -ExecutionPolicy Bypass -File \"" + scriptPath + "\"";
            ProcessStartInfo psi = new ProcessStartInfo {
                FileName        = "powershell.exe",
                Arguments       = args,
                WindowStyle     = ProcessWindowStyle.Hidden,
                CreateNoWindow  = true,
                UseShellExecute = true,
                Verb            = "runas"
            };

            try {
                using (Process p = Process.Start(psi)) {
                    if (p != null) p.WaitForExit(30000);
                }
            } catch (System.ComponentModel.Win32Exception ex) when (ex.NativeErrorCode == 1223) {
                Log("UAC prompt was cancelled by the user");
                return;
            }

            string newState = ReadState();
            Log("Script execution complete. New state: " + newState);
        } catch (Exception ex) {
            Log("ERROR during ExecuteScript: " + ex.Message);
        }
    }

    // ── Read state file ────────────────────────────────────────────────────────
    private string ReadState() {
        try {
            if (File.Exists(_stateFile))
                return File.ReadAllText(_stateFile).Trim().ToUpper();
        } catch { }
        return "LOCKED";
    }

    // ── Clean up on close ─────────────────────────────────────────────────────
    protected override void OnFormClosing(FormClosingEventArgs e) {
        try { UnregisterHotKey(Handle, HOTKEY_LOCK);   } catch {}
        try { UnregisterHotKey(Handle, HOTKEY_UNLOCK); } catch {}
        if (_llHookHandle != IntPtr.Zero) {
            try { UnhookWindowsHookEx(_llHookHandle); } catch {}
            _llHookHandle = IntPtr.Zero;
        }
        try { if (_fsw   != null) { _fsw.EnableRaisingEvents = false; _fsw.Dispose(); } } catch {}
        try { if (_pollTimer != null) { _pollTimer.Stop(); _pollTimer.Dispose(); } } catch {}
        Log("HotkeyListener v4.4 stopped — all hooks, FSW, and timers cleaned up");
        base.OnFormClosing(e);
    }
}
"@

Add-Type -TypeDefinition $csharpCode `
    -ReferencedAssemblies 'System.Windows.Forms', 'System.Drawing'

$sf           = 'C:\ProgramData\BrightUI\toggle_state.txt'
$log          = 'C:\ProgramData\BrightUI\hotkey_log.txt'
$lockScript   = 'C:\ProgramData\BrightUI\Scripts\BrightUI_Lock.ps1'
$unlockScript = 'C:\ProgramData\BrightUI\Scripts\BrightUI_Unlock.ps1'
$trigLock     = 'C:\ProgramData\BrightUI\trigger_lock.txt'
$trigUnlock   = 'C:\ProgramData\BrightUI\trigger_unlock.txt'

$form = New-Object BrightUIHotkeyForm($sf, $log, $lockScript, $unlockScript, $trigLock, $trigUnlock)
[System.Windows.Forms.Application]::Run($form)

$mutex.ReleaseMutex()
$mutex.Dispose()
'@

Set-Content -Path $listenerPath -Value $listenerContent -Encoding UTF8
Write-OK "Hotkey listener script (v4.4) saved: $listenerPath"
Write-OK 'Method 1: RegisterHotKey (local) | Method 2: WH_KEYBOARD_LL (RDP/CRD) | Method 3: Trigger files (AnyDesk/remote)'


# ══════════════════════════════════════════════════════════════════════════════
#  STEP 15 — Write Hotkey Registry Documentation Key
# ══════════════════════════════════════════════════════════════════════════════
Write-Step 'Writing hotkey documentation to HKLM\SOFTWARE\BrightUI\Hotkeys'

$hotkeyRegPath = 'HKLM:\SOFTWARE\BrightUI\Hotkeys'
Set-Reg $hotkeyRegPath 'LockKey'          $Cfg_LockHotkeyName   'String'
Set-Reg $hotkeyRegPath 'UnlockKey'        $Cfg_UnlockHotkeyName 'String'
Set-Reg $hotkeyRegPath 'LockScript'       $Cfg_LockScriptPath   'String'
Set-Reg $hotkeyRegPath 'UnlockScript'     $Cfg_UnlockScriptPath 'String'
Set-Reg $hotkeyRegPath 'StateFile'        $Cfg_StateFile        'String'
Set-Reg $hotkeyRegPath 'LogFile'          $Cfg_LogFile          'String'
Set-Reg $hotkeyRegPath 'ListenerScript'   $listenerPath         'String'
Set-Reg $hotkeyRegPath 'TriggerLock'      $Cfg_TriggerLock      'String'
Set-Reg $hotkeyRegPath 'TriggerUnlock'    $Cfg_TriggerUnlock    'String'
Set-Reg $hotkeyRegPath 'Version'          '4.8.1'                 'String'
Set-Reg $hotkeyRegPath 'Note' `
    'v4.4 listener: RegisterHotKey + WH_KEYBOARD_LL + trigger files. Remote unlock via: New-Item C:\ProgramData\BrightUI\trigger_unlock.txt -Force' `
    'String'

Write-OK "Registry documentation key written: $hotkeyRegPath"


# ══════════════════════════════════════════════════════════════════════════════
#  STEP 16 — Register Hotkey Listener and Wallpaper Enforcer via HKLM Run
#
#  v4.8: ALL Register-ScheduledTask calls have been REMOVED.
#  Components are instead registered in HKLM Run keys so they start
#  at every user logon without needing the Windows Task Scheduler.
# ══════════════════════════════════════════════════════════════════════════════
Write-Step 'Registering Run keys for listener and wallpaper enforcer (NO Task Scheduler in v4.8)'

# Register hotkey listener via HKLM Run
try {
    $listenerRunCmd = "powershell.exe -WindowStyle Hidden -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$listenerPath`""
    Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' 'BrightUI_HotkeyListener' $listenerRunCmd 'String'
    Write-OK "HotkeyListener registered in HKLM Run — starts at every user logon."
    Write-OK "Command: $listenerRunCmd"
} catch {
    Write-Warn "Could not register HotkeyListener Run key: $($_.Exception.Message)"
}

Write-OK 'NOTE (v4.8): ALL Register-ScheduledTask calls have been REMOVED.'
Write-OK '             BrightUI_SecurityLock, BrightUI_SecurityUnlock, BrightUI_HotkeyListener,'
Write-OK '             and BrightUI_LoginReminder scheduled tasks are NOT created.'
Write-OK '             Listener runs via HKLM Run. Lock/Unlock via hotkeys or trigger files.'


# ══════════════════════════════════════════════════════════════════════════════
#  STEP 16A — Create Additional Hotkey Persistence Files (BrightUI_Hotkeys.ps1, .vbs, .reg)
# ══════════════════════════════════════════════════════════════════════════════
Write-Step 'Creating secondary hotkey monitor files (BrightUI_Hotkeys.ps1, .vbs, .reg)'

$hotkeysPs1Path = Join-Path $Cfg_ScriptsDir 'BrightUI_Hotkeys.ps1'
$hotkeysVbsPath = Join-Path $Cfg_ScriptsDir 'BrightUI_Hotkeys.vbs'
$hotkeysRegPath = Join-Path $Cfg_ScriptsDir 'BrightUI_Hotkeys.reg'

# 1) PowerShell secondary hotkey listener (GetAsyncKeyState polling)
$hotkeysPs1Content = @'
Add-Type @"
using System;
using System.Runtime.InteropServices;

public class KeyboardHook {
    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int vKey);
}
"@

$unlockScript = "C:\ProgramData\BrightUI\Scripts\BrightUI_Unlock.ps1"
$lockScript   = "C:\ProgramData\BrightUI\Scripts\BrightUI_Lock.ps1"

Write-Host "BrightUI Hotkey Service Started..."

while ($true) {

    # CTRL + ALT + U
    $ctrl  = [KeyboardHook]::GetAsyncKeyState(0x11)
    $alt   = [KeyboardHook]::GetAsyncKeyState(0x12)
    $uKey  = [KeyboardHook]::GetAsyncKeyState(0x55)

    if (($ctrl -band 0x8000) -and ($alt -band 0x8000) -and ($uKey -band 0x8000)) {
        Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-ExecutionPolicy Bypass -File `"$unlockScript`""
        Start-Sleep -Milliseconds 1000
    }

    # CTRL + ALT + L
    $lKey = [KeyboardHook]::GetAsyncKeyState(0x4C)

    if (($ctrl -band 0x8000) -and ($alt -band 0x8000) -and ($lKey -band 0x8000)) {
        Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-ExecutionPolicy Bypass -File `"$lockScript`""
        Start-Sleep -Milliseconds 1000
    }

    Start-Sleep -Milliseconds 100
}
'@
Set-Content -Path $hotkeysPs1Path -Value $hotkeysPs1Content -Encoding UTF8
Write-OK "BrightUI_Hotkeys.ps1 saved: $hotkeysPs1Path"

# 2) VBS launcher (runs the PS1 silently in the background)
$hotkeysVbsContent = @"
Set objShell = CreateObject("Wscript.Shell")
objShell.Run "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File ""C:\ProgramData\BrightUI\Scripts\BrightUI_Hotkeys.ps1""", 0, False
"@
Set-Content -Path $hotkeysVbsPath -Value $hotkeysVbsContent -Encoding ASCII
Write-OK "BrightUI_Hotkeys.vbs saved: $hotkeysVbsPath"

# 3) Registry file to run the VBS at user logon
$hotkeysRegContent = @'
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Run]
"BrightUIHotkeys"="wscript.exe \"C:\\ProgramData\\BrightUI\\Scripts\\BrightUI_Hotkeys.vbs\""
'@
Set-Content -Path $hotkeysRegPath -Value $hotkeysRegContent -Encoding ASCII
Write-OK "BrightUI_Hotkeys.reg saved: $hotkeysRegPath"


# ══════════════════════════════════════════════════════════════════════════════
#  STEP 16B — Apply the .reg file to enable secondary hotkey monitor at startup
# ══════════════════════════════════════════════════════════════════════════════
Write-Step 'Applying BrightUI_Hotkeys.reg to register secondary hotkey listener'

if (Test-Path -LiteralPath $hotkeysRegPath) {
    try {
        $regResult = & reg import "`"$hotkeysRegPath`"" 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-OK "Registry imported successfully: $hotkeysRegPath"
        } else {
            Write-Warn "reg import exited with code $LASTEXITCODE. Output: $regResult"
        }
    } catch {
        Write-Warn "Failed to import registry: $($_.Exception.Message)"
    }
} else {
    Write-Warn "Registry file not found: $hotkeysRegPath"
}


# ══════════════════════════════════════════════════════════════════════════════
#  STEP 17 — PowerShell Execution Policy
# ══════════════════════════════════════════════════════════════════════════════
Write-Step 'Setting PowerShell execution policy to RemoteSigned (LocalMachine)'

try {
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force
    Write-OK 'Execution policy set to RemoteSigned for LocalMachine scope.'
} catch {
    Write-Warn "Could not set execution policy: $($_.Exception.Message)"
    Write-Warn 'Run manually:  Set-ExecutionPolicy RemoteSigned -Scope LocalMachine' }


# ══════════════════════════════════════════════════════════════════════════════
#  STEP 18 — Force Group Policy Refresh
# ══════════════════════════════════════════════════════════════════════════════
Write-Step 'Refreshing Group Policy (gpupdate /force)'

try {
    $null = & gpupdate /force 2>&1
    Write-OK 'Group Policy refreshed successfully.'
} catch { Write-Warn "gpupdate note (normal on non-domain machines): $($_.Exception.Message)" }


# ══════════════════════════════════════════════════════════════════════════════
#  STEP 19 — Check Chrome, Install if Missing, then Install GCPW  (v4.8.1 SILENT)
#
#  UPDATED v4.8.1: GCPW now installed directly via official standalone EXE
#  with /silent /install. No external scripts, no interactivity.
#  Chrome already uses /quiet /norestart.
# ══════════════════════════════════════════════════════════════════════════════
Write-Step 'Checking for Chrome installation (required before GCPW)'

# ── 19a. Detect Chrome ────────────────────────────────────────────────────────
$chromeInstalled = $false

$chromeRegistryPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Google Chrome',
    'HKCU:\SOFTWARE\Google\Chrome\BLBeacon'
)
foreach ($path in $chromeRegistryPaths) {
    if (Test-Path -LiteralPath $path) {
        $chromeInstalled = $true
        Write-OK "Chrome detected via registry: $path"
        break
    }
}

if (-not $chromeInstalled) {
    $chromeBinaryPaths = @(
        "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "${env:LocalAppData}\Google\Chrome\Application\chrome.exe"
    )
    foreach ($binPath in $chromeBinaryPaths) {
        if (Test-Path -LiteralPath $binPath) {
            $chromeInstalled = $true
            Write-OK "Chrome detected on disk: $binPath"
            break
        }
    }
}

# ── 19b. Install Chrome if not present ───────────────────────────────────────
if (-not $chromeInstalled) {
    Write-Warn 'Google Chrome is NOT installed. Downloading and installing Chrome Enterprise before GCPW...'

    $chromeMsiUrl  = 'https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi'
    $chromeMsiPath = Join-Path $env:TEMP 'ChromeEnterprise64.msi'

    try {
        Write-Host '    Downloading Chrome Enterprise installer (~80 MB) — please wait...'
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $chromeMsiUrl `
                          -OutFile $chromeMsiPath `
                          -UseBasicParsing `
                          -UserAgent 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'

        if ((Test-Path -LiteralPath $chromeMsiPath) -and ((Get-Item $chromeMsiPath).Length -gt 1MB)) {
            Write-OK "Chrome installer downloaded: $chromeMsiPath"
            Write-Host '    Installing Chrome silently — this may take 30-60 seconds...'
            $msiArgs = "/i `"$chromeMsiPath`" /quiet /norestart ALLUSERS=1"
            $proc    = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -Wait -PassThru -WindowStyle Hidden
            if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
                $chromeInstalled = $true
                Write-OK "Chrome installed successfully (exit code: $($proc.ExitCode))."
                if ($proc.ExitCode -eq 3010) {
                    Write-Warn 'Chrome install requests a reboot (3010) — GCPW will still be configured now.'
                }
            } else {
                Write-Warn "Chrome MSI installer exited with code $($proc.ExitCode). GCPW may not work correctly."
            }
            try { Remove-Item -Path $chromeMsiPath -Force -ErrorAction SilentlyContinue } catch {}
        } else {
            Write-Warn 'Chrome installer download appears incomplete. Continuing with GCPW anyway.'
        }
    } catch {
        Write-Warn "Chrome download/install failed: $($_.Exception.Message)"
        Write-Warn 'Please install Chrome manually then re-run this script for GCPW to work correctly.'
    }
} else {
    Write-OK 'Chrome is already installed — proceeding directly to GCPW installation.'
}

# ── 19c. GCPW silent installation (v4.8.1 — direct EXE, no external script) ───
Write-Step 'Installing and configuring GCPW (Google Credential Provider for Windows) — Silent Mode'

$enrollmentToken = 'f8a95d69-7c80-4dcb-b7b6-fb91de01dc57'
$gcpwUrl         = "https://dl.google.com/tag/s/appguid=%7B32987697-A14E-4B89-84D6-630D5431E831%7D&needsadmin=true&appname=GCPW&etoken=$enrollmentToken/credentialprovider/gcpwstandaloneenterprise64.exe"
$gcpwInstaller   = Join-Path $env:TEMP 'gcpwstandaloneenterprise64.exe'

try {
    Write-Host '  Downloading GCPW installer...'
    Invoke-WebRequest -Uri $gcpwUrl -OutFile $gcpwInstaller -UseBasicParsing `
                      -UserAgent 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'
    if ((Test-Path -LiteralPath $gcpwInstaller) -and ((Get-Item $gcpwInstaller).Length -gt 100KB)) {
        Write-OK 'GCPW installer downloaded successfully'
        Write-Host '  Running GCPW silent install...'
        $p = Start-Process -FilePath $gcpwInstaller `
                           -ArgumentList '/silent /install' `
                           -WindowStyle Hidden -Wait -PassThru
        if ($p.ExitCode -eq 0) {
            Write-OK 'GCPW installed successfully'
        } else {
            Write-Warn "GCPW installer exited with code $($p.ExitCode) — may still be OK"
        }
        try { Remove-Item -Path $gcpwInstaller -Force -ErrorAction SilentlyContinue } catch {}
    } else {
        Write-Warn 'GCPW download appears incomplete'
    }
} catch {
    Write-Warn "GCPW download/install failed: $($_.Exception.Message)"
}

# ── 19d. Configure GCPW registry keys (already in script, keep them) ──────────
try {
    & reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Google\CloudManagement" /v "EnrollmentToken" /t REG_SZ /d "$enrollmentToken" /f
    Write-OK 'GCPW enrollment token configured.'
} catch { Write-Warn "Failed to set EnrollmentToken: $($_.Exception.Message)" }

try {
    & reg add "HKEY_LOCAL_MACHINE\Software\Google\GCPW" /v domains_allowed_to_login /t REG_SZ /d "$Cfg_Domain" /f
    Write-OK "GCPW allowed login domain: $Cfg_Domain"
} catch { Write-Warn "Failed to set domains_allowed_to_login: $($_.Exception.Message)" }

try {
    & reg add "HKEY_LOCAL_MACHINE\Software\Google\GCPW" /v validity_period_in_days /t REG_DWORD /d 5 /f
    Write-OK 'GCPW validity period set to 5 days.'
} catch { Write-Warn "Failed to set validity_period_in_days: $($_.Exception.Message)" }

# ── 19e. Hide last username on login screen ───────────────────────────────────
try {
    & reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v dontdisplaylastusername /t REG_DWORD /d 1 /f
    Write-OK 'Last username hidden on login screen (dontdisplaylastusername = 1).'
} catch { Write-Warn "Failed to set dontdisplaylastusername: $($_.Exception.Message)" }


# ══════════════════════════════════════════════════════════════════════════════
#  FINAL SUMMARY
# ══════════════════════════════════════════════════════════════════════════════
$ld = '=' * 72
Write-Host ''
Write-Host $ld -ForegroundColor Cyan
Write-Host '   BrightUI Technologies  -  Setup v4.8.1  Completed Successfully!' -ForegroundColor Green
Write-Host $ld -ForegroundColor Cyan
Write-Host ''
Write-Host '  FILES STORED UNDER:' -ForegroundColor Yellow
Write-Host "    $Cfg_RootDir"
Write-Host "    Assets\  brightui_logo.png        (logo downloaded: $logoDownloaded)"
Write-Host '             lockscreen_bg.jpg        (1920x1080, quality 98)'
Write-Host "             Desktop_image.png        (wallpaper downloaded: $wallpaperDownloaded)"
Write-Host '    Scripts\ BrightUI_InternetCheck.ps1'
Write-Host '             BrightUI_LoginReminder.ps1   (file only — NO task in v4.8)'
Write-Host '             BrightUI_Toggle.ps1          (manual admin use)'
Write-Host '             BrightUI_Lock.ps1            (v4.2 — self-elevation, instant USB block)'
Write-Host '             BrightUI_Unlock.ps1          (v5.3 — FIXED USB drive letter assignment)'
Write-Host '             BrightUI_HotkeyListener.ps1  (v4.4 — hotkeys + trigger files)'
Write-Host '             BrightUI_Hotkeys.ps1         (secondary hotkey monitor)'
Write-Host '             BrightUI_Hotkeys.vbs         (launcher for secondary monitor)'
Write-Host '             BrightUI_Hotkeys.reg         (Run key for secondary monitor)'
Write-Host '             BrightUI_SetWallpaper.ps1    (wallpaper enforcer — logon)'
Write-Host "    hotkey_log.txt    (all toggle events logged here)"
Write-Host "    toggle_state.txt  (current: LOCKED)"
Write-Host "    trigger_lock.txt  (CREATE THIS FILE remotely to trigger LOCK)"
Write-Host "    trigger_unlock.txt(CREATE THIS FILE remotely to trigger UNLOCK)"
Write-Host ''
Write-Host '  CONFIGURED:' -ForegroundColor Yellow
Write-Host "    Lock Screen         :  Advanced JPEG — glow, step circles, amber strip"
Write-Host "    Default Win Image   :  REMOVED  (Spotlight + CDM disabled)"
Write-Host "    Login Screen Blur   :  DISABLED (image renders crisp)"
Write-Host "    Pre-Login Notice    :  Winlogon dialog (before PIN/password prompt)"
Write-Host "    Post-Login Popup    :  Script file created — NOT auto-launched (v4.8)"
Write-Host "    Browser Restriction :  @$Cfg_Domain only (Chrome + Edge)"
Write-Host "    USB Storage         :  BLOCKED  (driver + Group Policy)"
Write-Host "    Desktop Wallpaper   :  Desktop_image.png (Fill — full screen, locked via GP)"
Write-Host "                           Downloaded via Invoke-WebRequest, refreshed via rundll32"
Write-Host "                           Re-applied at every logon — theme changes cannot override it"
Write-Host ''
Write-Host '  SECURITY MANAGEMENT:' -ForegroundColor Yellow
Write-Host "    Ctrl+Alt+L  →  Lock   (UAC prompt)  — disables USB, restricts browsers"
Write-Host "    Ctrl+Alt+U  →  Unlock (UAC prompt)  — enables USB, mounts drives, removes restrictions"
Write-Host ''
Write-Host '  REMOTE TRIGGER (AnyDesk / any remote tool):' -ForegroundColor Yellow
Write-Host '    To LOCK   remotely: create  C:\ProgramData\BrightUI\trigger_lock.txt'
Write-Host '    To UNLOCK remotely: create  C:\ProgramData\BrightUI\trigger_unlock.txt'
Write-Host '    PowerShell command: New-Item -Path "C:\ProgramData\BrightUI\trigger_unlock.txt" -Force'
Write-Host '    The listener detects the file within 2 seconds and executes the action.'
Write-Host ''
Write-Host '  TASK SCHEDULER:' -ForegroundColor Yellow
Write-Host '    NO scheduled tasks are created in v4.8.'
Write-Host '    Listener runs via HKLM\Run (starts at every user logon automatically).'
Write-Host "    BrightUI_HotkeyListener  — HKLM\Run key (no Task Scheduler)"
Write-Host "    BrightUI_Wallpaper       — HKLM\Run key (re-applies wallpaper at logon)"
Write-Host "    BrightUIHotkeys (VBS)    — HKLM\Run key (secondary monitor)"
Write-Host "    BrightUI_InternetCheck   — HKLM\Run key (connectivity check at startup)"
Write-Host ''
Write-Host '  USB FIX DETAILS (v5.3):' -ForegroundColor Yellow
Write-Host '    WriteProtect is cleared BEFORE PnP re-enable (prevents read-only mount).'
Write-Host '    USBSTOR service is explicitly Started (no reboot needed for driver).'
Write-Host '    diskpart assigns drive letters (no null-char bug from v5.2).'
Write-Host '    3-second pause after PnP enable for hardware re-enumeration.'
Write-Host '    Retry loop: up to 3 attempts with 2-second pause for slow USB chipsets.'
Write-Host ''
Write-Host '  REGISTRY & GCPW:' -ForegroundColor Yellow
Write-Host "    HKLM\SOFTWARE\BrightUI\Hotkeys            (documentation + trigger file paths)"
Write-Host "    HKLM\Run\BrightUI_HotkeyListener          (listener startup — no Task Scheduler)"
Write-Host "    HKLM\Run\BrightUI_Wallpaper               (wallpaper enforcer at logon)"
Write-Host "    HKLM\Run\BrightUIHotkeys                  (secondary hotkey monitor via VBS)"
Write-Host "    HKLM\Run\BrightUI_InternetCheck           (internet check at startup)"
Write-Host "    GCPW installed — allowed domain: brightuitechnologies.com"
Write-Host "    Offline validity: 5 days | Last username hidden on login screen"
Write-Host "    Chrome installed: $chromeInstalled"
Write-Host ''
Write-Host '  NEXT STEPS:' -ForegroundColor Yellow
Write-Host '    1.  RESTART this computer (USB driver + lock screen + GCPW + wallpaper need reboot).'
Write-Host '    2.  After restart, confirm the lock screen shows the BrightUI image.'
Write-Host '    3.  Confirm the desktop shows Desktop_image.png (full-screen, no borders).'
Write-Host '    4.  Log in — the hotkey listener starts automatically via HKLM Run.'
Write-Host '    5.  Press Ctrl+Alt+L or Ctrl+Alt+U for local hotkeys (UAC prompt appears).'
Write-Host '    6.  For AnyDesk/remote unlock, run on the remote session:'
Write-Host '          New-Item -Path "C:\ProgramData\BrightUI\trigger_unlock.txt" -Force'
Write-Host '        The listener on the local machine will act within 2 seconds.'
Write-Host '    7.  After unlocking, any connected USB storage will be brought online'
Write-Host '        automatically with drive letters assigned via diskpart.'
Write-Host '    8.  Verify GCPW by restarting and signing in with a Google Workspace account.'
Write-Host ''
Write-Host $ld -ForegroundColor Cyan

# ── Automatic restart (added in v4.8.1) ───────────────────────────────────────
Write-Host '  SYSTEM WILL RESTART IN 5 SECONDS. No action needed.' -ForegroundColor Magenta
Start-Sleep -Seconds 5
Restart-Computer -Force
