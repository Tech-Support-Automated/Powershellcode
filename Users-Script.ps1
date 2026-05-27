<#
================================================================================
  BrightUI Technologies — Windows 10 / 11 Login Screen Setup  v4.7
  (User‑mode – no admin required)
================================================================================
  HOW TO RUN:
    1.  Save this file as  BrightUI_Setup_V4.7.ps1
    2.  Open PowerShell as the CURRENT USER (not as Administrator).
        If you are an admin, you may run it without elevation for user‑only setup.
    3.  cd to the script's folder and run:
           .\BrightUI_Setup_V4.7.ps1

  WHAT THIS SCRIPT DOES:
    - Creates all files under  %LOCALAPPDATA%\BrightUI
    - Applies user‑level policies (HKCU) for lock screen, browsers, USB block
    - Installs hotkey listeners via Startup folder (no scheduled tasks)
    - Skips admin‑only features when run without elevation
    - After a REBOOT the setup becomes fully active

  COMPATIBILITY : Windows 10 Build 1703+  and  Windows 11 (all builds)
  NOTE          : For full functionality (system‑wide USB block, GCPW, etc.)
                  the script must be run as Administrator.
================================================================================
#>

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

Write-Host ''
Write-Host ('=' * 72) -ForegroundColor Cyan
Write-Host '   BrightUI Technologies — Windows Login Screen Setup  v4.7' -ForegroundColor Cyan
Write-Host '   (User‑mode – no admin required)' -ForegroundColor Yellow
Write-Host ('=' * 72) -ForegroundColor Cyan
Write-Host ''

# ══════════════════════════════════════════════════════════════════════════════
#  SECTION A — CONFIGURATION
# ══════════════════════════════════════════════════════════════════════════════

$Cfg_CompanyName = 'BrightUI Technologies'
$Cfg_Domain      = 'brightuitechnologies.com'
$Cfg_SupportURL  = 'https://portal.brightuitechnologies.com'
$Cfg_LogoURL     = 'https://dev.brightuitechnologies.com/site/wp-content/themes/startnext/landing/img/logo.png'

# All files are stored in the current user's LOCALAPPDATA (no admin needed for C: drive)
$Cfg_RootDir    = "$env:LOCALAPPDATA\BrightUI"
$Cfg_AssetsDir  = "$Cfg_RootDir\Assets"
$Cfg_ScriptsDir = "$Cfg_RootDir\Scripts"
$Cfg_StateFile  = "$Cfg_RootDir\toggle_state.txt"
$Cfg_LogFile    = "$Cfg_RootDir\hotkey_log.txt"

$Cfg_LockScriptPath   = "$Cfg_ScriptsDir\BrightUI_Lock.ps1"
$Cfg_UnlockScriptPath = "$Cfg_ScriptsDir\BrightUI_Unlock.ps1"

$Cfg_BgWidth  = 1920
$Cfg_BgHeight = 1080

$Cfg_UsbClassGuid  = '{53f56307-b6bf-11d0-94f2-00a0c91efb8b}'
$Cfg_UsbPolicyBase = 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices'   # HKCU now

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

function Write-Skip { param([string]$Message)
    Write-Host "    [--]  SKIPPED: $Message" -ForegroundColor DarkYellow }

function Set-Reg {
    param([string]$RegistryPath,[string]$Name,[object]$Value,[string]$Type='String')
    if (-not (Test-Path -LiteralPath $RegistryPath)) {
        New-Item -Path $RegistryPath -Force | Out-Null }
    Set-ItemProperty -Path $RegistryPath -Name $Name -Value $Value -Type $Type -ErrorAction SilentlyContinue
}

$script:IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
if (-not $script:IsAdmin) {
    Write-Warn 'Running WITHOUT administrator rights – some features will be skipped.'
}


# ══════════════════════════════════════════════════════════════════════════════
#  STEP 1 — Create Working Directories
# ══════════════════════════════════════════════════════════════════════════════
Write-Step 'Creating BrightUI directory structure under user profile'

foreach ($dir in @($Cfg_RootDir, $Cfg_AssetsDir, $Cfg_ScriptsDir)) {
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Write-OK "Directory ready: $dir"
}

try {
    $acl  = Get-Acl -LiteralPath $Cfg_RootDir
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $env:USERNAME,'FullControl','ContainerInherit,ObjectInherit','None','Allow')
    $acl.AddAccessRule($rule)
    Set-Acl -LiteralPath $Cfg_RootDir -AclObject $acl
    Write-OK "Full control for current user granted on $Cfg_RootDir"
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
    Write-Warn 'Background will use a styled text placeholder instead of the logo image.'
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
#  STEP 4 — Apply Lock Screen Background (User‑level policies)
# ══════════════════════════════════════════════════════════════════════════════
Write-Step 'Applying lock screen image (HKCU policies)'

# User‑level Personalization policy
$persPath = 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\Personalization'
Set-Reg $persPath 'LockScreenImage'      $bgFilePath 'String'
Set-Reg $persPath 'NoChangingLockScreen' 1           'DWord'
Write-OK 'HKCU Personalization: LockScreenImage and NoChangingLockScreen set.'

# CSP path (also user‑level)
$cspPath = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP'
Set-Reg $cspPath 'LockScreenImagePath'   $bgFilePath 'String'
Set-Reg $cspPath 'LockScreenImageUrl'    $bgFilePath 'String'
Set-Reg $cspPath 'LockScreenImageStatus' 1           'DWord'
Write-OK 'HKCU PersonalizationCSP: lock screen image path configured.'

# Spotlight disabled (user‑level)
$ccPath = 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
Set-Reg $ccPath 'DisableWindowsSpotlightOnLockScreen' 1 'DWord'
Set-Reg $ccPath 'DisableWindowsConsumerFeatures'      1 'DWord'
Set-Reg $ccPath 'DisableCloudOptimizedContent'        1 'DWord'
Set-Reg $ccPath 'DisableSoftLanding'                  1 'DWord'
Write-OK 'HKCU: Windows Spotlight on lock screen DISABLED.'

# Acrylic blur
Set-Reg 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\System' 'DisableAcrylicBackgroundOnLogon' 1 'DWord'
Write-OK 'Acrylic blur on login screen DISABLED (HKCU).'


# ══════════════════════════════════════════════════════════════════════════════
#  STEP 5 — Winlogon Legal Notice (admin only, skip if non‑admin)
# ══════════════════════════════════════════════════════════════════════════════
Write-Step 'Configuring Winlogon pre-login legal notice dialog'
if ($script:IsAdmin) {
    $winlogonPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    Set-Reg $winlogonPath 'LegalNoticeCaption' $Cfg_NoticeTitle 'String'
    Set-Reg $winlogonPath 'LegalNoticeText'    $Cfg_NoticeBody  'String'
    Write-OK "Winlogon legal notice configured."
} else {
    Write-Skip 'Admin rights required for Winlogon legal notice.'
}


# ══════════════════════════════════════════════════════════════════════════════
#  STEP 6 — Azure AD / Domain Hint (admin only)
# ══════════════════════════════════════════════════════════════════════════════
Write-Step "Setting Azure AD domain hint (admin only)"
if ($script:IsAdmin) {
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\AzureADAccount' 'DomainHint'        $Cfg_Domain 'String'
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\AzureADAccount' 'AllowedAadTenants' $Cfg_Domain 'String'
    Write-OK "Domain hint: @$Cfg_Domain"
} else {
    Write-Skip 'Admin rights required for Azure AD hint.'
}


# ══════════════════════════════════════════════════════════════════════════════
#  STEP 7 — OEM Branding (admin only)
# ══════════════════════════════════════════════════════════════════════════════
Write-Step 'Configuring OEM branding (admin only)'
if ($script:IsAdmin) {
    $oemPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation'
    Set-Reg $oemPath 'Manufacturer' $Cfg_CompanyName 'String'
    Set-Reg $oemPath 'SupportURL'   $Cfg_SupportURL  'String'
    if ($logoDownloaded) { Set-Reg $oemPath 'Logo' $logoFilePath 'String'; Write-OK "OEM logo: $logoFilePath" }
    Write-OK "OEM manufacturer: $Cfg_CompanyName  |  Support URL: $Cfg_SupportURL"
} else {
    Write-Skip 'Admin rights required for OEM branding.'
}


# ══════════════════════════════════════════════════════════════════════════════
#  STEP 8 — Internet Connectivity Reminder (Startup folder)
# ══════════════════════════════════════════════════════════════════════════════
Write-Step 'Installing internet connectivity reminder (Startup folder)'

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

# Create shortcut in Startup folder
$startupDir = [Environment]::GetFolderPath('Startup')
$shortcutPath = Join-Path $startupDir 'BrightUI_InternetCheck.lnk'
$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut($shortcutPath)
$Shortcut.TargetPath = 'powershell.exe'
$Shortcut.Arguments = "-WindowStyle Hidden -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$checkPath`""
$Shortcut.WorkingDirectory = $Cfg_ScriptsDir
$Shortcut.IconLocation = 'powershell.exe,0'
$Shortcut.Save()
Write-OK "Internet check shortcut placed in Startup: $shortcutPath"


# ══════════════════════════════════════════════════════════════════════════════
#  STEP 9 — USB Mass Storage Restriction (User‑level)
# ══════════════════════════════════════════════════════════════════════════════
Write-Step 'Blocking USB mass storage (user‑level Group Policy)'

# The HKLM USBSTOR driver cannot be changed without admin; we rely on HKCU policies.
$usbPolPath = "$Cfg_UsbPolicyBase\$Cfg_UsbClassGuid"
Set-Reg $usbPolPath 'Deny_Read'  1 'DWord'
Set-Reg $usbPolPath 'Deny_Write' 1 'DWord'
Write-OK "User Group Policy USB block: Deny_Read=1, Deny_Write=1."

Set-Content -Path $Cfg_StateFile -Value 'LOCKED' -Force -Encoding UTF8
Write-OK "State file initialised: LOCKED  ($Cfg_StateFile)"


# ══════════════════════════════════════════════════════════════════════════════
#  STEP 10 — Chrome Domain Restriction (User‑level)
# ══════════════════════════════════════════════════════════════════════════════
Write-Step "Restricting Chrome browser sign-in to @$Cfg_Domain accounts"

$chromePath = 'HKCU:\Software\Policies\Google\Chrome'
Set-Reg $chromePath 'AllowedDomainsForApps'               $Cfg_Domain       'String'
Set-Reg $chromePath 'RestrictSigninToPattern'             "*@$Cfg_Domain"   'String'
Set-Reg $chromePath 'BrowserSignin'                       1                 'DWord'
Set-Reg $chromePath 'SecondaryGoogleAccountSigninAllowed' 0                 'DWord'
Write-OK "Chrome HKCU: AllowedDomainsForApps = $Cfg_Domain  |  RestrictSigninToPattern = *@$Cfg_Domain"


# ══════════════════════════════════════════════════════════════════════════════
#  STEP 11 — Microsoft Edge Domain Restriction (User‑level)
# ══════════════════════════════════════════════════════════════════════════════
Write-Step "Restricting Edge browser sign-in to @$Cfg_Domain accounts"

$edgePath = 'HKCU:\Software\Policies\Microsoft\Edge'
Set-Reg $edgePath 'RestrictSigninToPattern' "*@$Cfg_Domain" 'String'
Set-Reg $edgePath 'BrowserSignin'           1               'DWord'
Write-OK "Edge HKCU: RestrictSigninToPattern = *@$Cfg_Domain"


# ══════════════════════════════════════════════════════════════════════════════
#  STEP 12 — ADVANCED Post-Login Reminder Popup  (v4.1 — WHITE TEXT)
# ══════════════════════════════════════════════════════════════════════════════
Write-Step 'Creating ADVANCED post-logon reminder popup script (v4.1 — white text)'

$reminderPath    = Join-Path $Cfg_ScriptsDir 'BrightUI_LoginReminder.ps1'
$reminderContent = @'
# ============================================================
#  BrightUI Technologies - Advanced Login Reminder Popup v4.1
#  Triggered by: Startup shortcut (BrightUI_LoginReminder.lnk)
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
$logoPath = 'C:\ProgramData\BrightUI\Assets\brightui_logo.png'    # (unused – will be replaced)
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
$reminderContent = $reminderContent -replace 'C:\\ProgramData\\BrightUI\\Assets\\brightui_logo.png', $logoFilePath   # update logo path

Set-Content -Path $reminderPath -Value $reminderContent -Encoding UTF8
Write-OK "Advanced login reminder script saved: $reminderPath"

# Create Startup shortcut for the reminder
$startupDir = [Environment]::GetFolderPath('Startup')
$reminderShortcut = Join-Path $startupDir 'BrightUI_LoginReminder.lnk'
$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut($reminderShortcut)
$Shortcut.TargetPath = 'powershell.exe'
$Shortcut.Arguments = "-WindowStyle Hidden -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$reminderPath`""
$Shortcut.WorkingDirectory = $Cfg_ScriptsDir
$Shortcut.Save()
Write-OK "Login reminder shortcut placed in Startup: $reminderShortcut"


# ══════════════════════════════════════════════════════════════════════════════
#  STEP 13 — Security Toggle Script  (legacy / manual admin use)
# ══════════════════════════════════════════════════════════════════════════════
Write-Step 'Creating Security Toggle script (manual admin / task use)'

$togglePath    = Join-Path $Cfg_ScriptsDir 'BrightUI_Toggle.ps1'
$toggleContent = @"
# ============================================================
#  BrightUI Technologies - Security Toggle
#  Accepts: -State (LOCKED|UNLOCKED|TOGGLE)
# ============================================================
param([string]`$State = 'TOGGLE')
`$ErrorActionPreference = 'Stop'

`$stateFile  = '$Cfg_StateFile'
`$logFile    = '$Cfg_LogFile'
`$usbPolPath = '$Cfg_UsbPolicyBase\$Cfg_UsbClassGuid'
`$chromePath = 'HKCU:\Software\Policies\Google\Chrome'
`$edgePath   = 'HKCU:\Software\Policies\Microsoft\Edge'
`$domain     = '$Cfg_Domain'

function Write-Log(`$msg) {
    `$line = "[`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] `$msg"
    Add-Content -Path `$logFile -Value `$line -Encoding UTF8
}

function Enable-UsbStorage {
    Write-Log "Enabling USB storage (user level)"
    if (Test-Path -LiteralPath `$usbPolPath) {
        Set-ItemProperty -Path `$usbPolPath -Name 'Deny_Read'  -Value 0 -Type DWord
        Set-ItemProperty -Path `$usbPolPath -Name 'Deny_Write' -Value 0 -Type DWord
    }
}
function Disable-UsbStorage {
    Write-Log "Disabling USB storage (user level)"
    if (-not (Test-Path -LiteralPath `$usbPolPath)) { New-Item -Path `$usbPolPath -Force | Out-Null }
    Set-ItemProperty -Path `$usbPolPath -Name 'Deny_Read'  -Value 1 -Type DWord
    Set-ItemProperty -Path `$usbPolPath -Name 'Deny_Write' -Value 1 -Type DWord
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
    try { `$current = (Get-Content `$stateFile -Raw -ErrorAction Stop).Trim().ToUpper() } catch {}
}
`$target = `$State.ToUpper()
if (`$target -eq 'TOGGLE') { `$target = if (`$current -eq 'LOCKED') { 'UNLOCKED' } else { 'LOCKED' } }
if (`$target -eq `$current) {
    Write-Log "Already in `$target state — no action"
    exit 0
}
Write-Log "Switching from `$current to `$target"
if (`$target -eq 'UNLOCKED') { Enable-UsbStorage; Remove-DomainRestrictions }
else                          { Disable-UsbStorage; Apply-DomainRestrictions }
Set-Content -Path `$stateFile -Value `$target -Force -Encoding UTF8
Write-Log "State updated to `$target"
"@

Set-Content -Path $togglePath -Value $toggleContent -Encoding UTF8
Write-OK "Toggle script saved: $togglePath"


# ══════════════════════════════════════════════════════════════════════════════
#  STEP 13A — Dedicated LOCK Script  (v4.2 – user‑mode with self‑elevation)
# ══════════════════════════════════════════════════════════════════════════════
Write-Step 'Creating dedicated BrightUI_Lock.ps1 (v4.2)'

$lockScriptContent = @'
# ============================================================
#  BrightUI Technologies - Security Lock Script  v4.2
# ============================================================
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    $arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$($MyInvocation.MyCommand.Path)`""
    Start-Process PowerShell.exe -Verb RunAs -ArgumentList $arguments
    exit 0
}
$ErrorActionPreference = 'Continue'

$stateFile  = '__STATE_FILE__'
$logFile    = '__LOG_FILE__'
$usbStorReg = 'HKLM:\SYSTEM\CurrentControlSet\Services\USBSTOR'
$usbPolPath = '__USB_POL_PATH__'
$chromePath = 'HKCU:\Software\Policies\Google\Chrome'
$edgePath   = 'HKCU:\Software\Policies\Microsoft\Edge'
$domain     = '__DOMAIN__'

function Write-Log([string]$msg) {
    try { Add-Content -Path $logFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [LOCK] $msg" -Encoding UTF8 } catch {}
}

Write-Log "Lock script started (v4.2)"
$currentState = 'LOCKED'
try { if (Test-Path $stateFile) { $currentState = (Get-Content $stateFile -Raw).Trim().ToUpper() } } catch {}
if ($currentState -eq 'LOCKED') { Write-Log "Already LOCKED"; exit 0 }

# 1. Stop USBSTOR service (needs admin)
try { Stop-Service USBSTOR -Force -ErrorAction SilentlyContinue; Write-Log "USBSTOR stopped" } catch {}
if (Test-Path $usbStorReg) { Set-ItemProperty -Path $usbStorReg -Name 'Start' -Value 4 -Type DWord; Write-Log "USBSTOR Start=4" }

# 2. Disable USB mass storage devices (PnP)
try {
    Get-PnpDevice -Class USB -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match 'Mass Storage|USB Attached SCSI|USB Storage' } | ForEach-Object {
        $_ | Disable-PnpDevice -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
        Write-Log "Disabled device: $($_.FriendlyName)"
    }
} catch {}

# 3. Apply user‑level USB block
if (-not (Test-Path $usbPolPath)) { New-Item -Path $usbPolPath -Force | Out-Null }
Set-ItemProperty -Path $usbPolPath -Name 'Deny_Read'  -Value 1 -Type DWord
Set-ItemProperty -Path $usbPolPath -Name 'Deny_Write' -Value 1 -Type DWord

# 4. Browser restrictions (HKCU)
if (-not (Test-Path $chromePath)) { New-Item -Path $chromePath -Force | Out-Null }
Set-ItemProperty -Path $chromePath -Name 'AllowedDomainsForApps'               -Value $domain     -Type String
Set-ItemProperty -Path $chromePath -Name 'RestrictSigninToPattern'             -Value "*@$domain" -Type String
Set-ItemProperty -Path $chromePath -Name 'BrowserSignin'                       -Value 1            -Type DWord
Set-ItemProperty -Path $chromePath -Name 'SecondaryGoogleAccountSigninAllowed' -Value 0            -Type DWord
if (-not (Test-Path $edgePath)) { New-Item -Path $edgePath -Force | Out-Null }
Set-ItemProperty -Path $edgePath -Name 'RestrictSigninToPattern' -Value "*@$domain" -Type String
Set-ItemProperty -Path $edgePath -Name 'BrowserSignin'           -Value 1            -Type DWord
Write-Log "Browser restrictions applied"

# 5. Close browsers
Get-Process -Name chrome,msedge -ErrorAction SilentlyContinue | Stop-Process -Force

# 6. State file
Set-Content -Path $stateFile -Value 'LOCKED' -Force -Encoding UTF8
Write-Log "Lock completed"
'@

$lockScriptContent = $lockScriptContent -replace '__STATE_FILE__', $Cfg_StateFile
$lockScriptContent = $lockScriptContent -replace '__LOG_FILE__', $Cfg_LogFile
$lockScriptContent = $lockScriptContent -replace '__USB_POL_PATH__', ($Cfg_UsbPolicyBase + '\' + $Cfg_UsbClassGuid)
$lockScriptContent = $lockScriptContent -replace '__DOMAIN__', $Cfg_Domain

Set-Content -Path $Cfg_LockScriptPath -Value $lockScriptContent -Encoding UTF8
Write-OK "Lock script saved: $Cfg_LockScriptPath"


# ══════════════════════════════════════════════════════════════════════════════
#  STEP 13B — Dedicated UNLOCK Script  (v5.2 – full unlock, self‑elevation)
# ══════════════════════════════════════════════════════════════════════════════
Write-Step 'Creating dedicated BrightUI_Unlock.ps1 (v5.2)'

$unlockScriptContent = @'
<#
.SYNOPSIS
    BrightUI_Unlock.ps1 – Fully unlock USB ports, removable storage, and browser logins.
.DESCRIPTION
    Removes every known Group Policy / registry restriction that blocks USB mass storage,
    removes sign‑in restrictions for Chrome/Edge, brings all USB disks online,
    and forces immediate hardware rediscovery.
.NOTES
    Version 5.2
#>

if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    $arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$($MyInvocation.MyCommand.Path)`""
    Start-Process PowerShell.exe -Verb RunAs -ArgumentList $arguments
    exit 0
}

$ErrorActionPreference = 'Continue'

$logDir = '__ROOT_DIR__'
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }

$stateFile      = "$logDir\toggle_state.txt"
$logFile        = "$logDir\hotkey_log.txt"
$usbStorReg     = 'HKLM:\SYSTEM\CurrentControlSet\Services\USBSTOR'
$storagePol     = 'HKLM:\SYSTEM\CurrentControlSet\Control\StorageDevicePolicies'
$remStorBase    = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices'
$remDiskGuid    = '{53f5630d-b6bf-11d0-94f2-00a0c91efb8b}'
$deviceRestrict = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions'
$chromePath     = 'HKCU:\Software\Policies\Google\Chrome'
$edgePath       = 'HKCU:\Software\Policies\Microsoft\Edge'
$usbPolPathUser = '__USB_POL_PATH__'

function Write-Log([string]$msg) {
    try { Add-Content -Path $logFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [UNLOCK] $msg" -Encoding UTF8 } catch {}
}

Write-Log "Unlock script started (v5.2)"

# Check state
$currentState = 'LOCKED'
try { if (Test-Path $stateFile) { $currentState = (Get-Content $stateFile -Raw).Trim().ToUpper() } } catch {}
if ($currentState -eq 'UNLOCKED') { Write-Log "Already UNLOCKED"; exit 0 }

# 1. Enable USBSTOR driver
if (Test-Path $usbStorReg) {
    Set-ItemProperty -Path $usbStorReg -Name 'Start' -Value 3 -Type DWord
    Write-Log "USBSTOR Start=3"
}
try { Start-Service USBSTOR -ErrorAction SilentlyContinue } catch {}

# 2. WriteProtect
Set-ItemProperty -Path $storagePol -Name 'WriteProtect' -Value 0 -Type DWord -ErrorAction SilentlyContinue

# 3. Removable storage policies (system)
Set-ItemProperty -Path $remStorBase -Name 'Deny_All' -Value 0 -Type DWord -ErrorAction SilentlyContinue
$remDiskPath = Join-Path $remStorBase $remDiskGuid
if (-not (Test-Path $remDiskPath)) { New-Item -Path $remDiskPath -Force | Out-Null }
Set-ItemProperty -Path $remDiskPath -Name 'Deny_Read'  -Value 0 -Type DWord
Set-ItemProperty -Path $remDiskPath -Name 'Deny_Write' -Value 0 -Type DWord
Get-ChildItem -Path $remStorBase -ErrorAction SilentlyContinue | ForEach-Object {
    'Deny_Read','Deny_Write','Deny_All' | ForEach-Object { Remove-ItemProperty -Path $_.PSPath -Name $_ -ErrorAction SilentlyContinue }
}

# 4. DeviceInstall restrictions
'DenyRemovableDevices','DenyUnspecified','DenyDeviceIDs','DenyDeviceClasses','DenyDeviceInstanceIDs','DenyAll' | ForEach-Object {
    Remove-ItemProperty -Path $deviceRestrict -Name $_ -ErrorAction SilentlyContinue
}

# 5. Re-enable USB devices
Get-PnpDevice -Class USB -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match 'Mass Storage|USB Attached SCSI|USB Storage' } | ForEach-Object {
    $_ | Enable-PnpDevice -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
}

# 6. Restart USB hubs
Get-PnpDevice -Class USB -FriendlyName '*Root Hub*' -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'OK' } | ForEach-Object {
    $_ | Disable-PnpDevice -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
    Start-Sleep -Milliseconds 500
    $_ | Enable-PnpDevice  -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
}
pnputil.exe /scan-devices > $null 2>&1

# 7. Online all USB disks
try {
    Set-Service ShellHWDetection -StartupType Manual -ErrorAction SilentlyContinue
    Start-Service ShellHWDetection -ErrorAction SilentlyContinue
} catch {}
$usbDisks = Get-Disk | Where-Object { $_.BusType -eq 'USB' }
if (-not $usbDisks) {
    Get-CimInstance -ClassName Win32_DiskDrive | Where-Object { $_.InterfaceType -eq 'USB' } | ForEach-Object {
        $d = Get-Disk -Number $_.Index -ErrorAction SilentlyContinue
        if ($d) { $usbDisks += $d }
    }
}
foreach ($disk in $usbDisks) {
    if ($disk.IsOffline) { Set-Disk -InputObject $disk -IsOffline $false }
    if ($disk.IsReadOnly) { Set-Disk -InputObject $disk -IsReadOnly $false }
    Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter -eq $null -and $_.Type -ne 'Unknown' } | ForEach-Object {
        try { Set-Partition -InputObject $_ -NewDriveLetter ([char]::MinValue) -ErrorAction Stop } catch {}
    }
}
Write-Log "USB disks brought online and mounted"

# 8. Clear user‑level USB block
Set-ItemProperty -Path $usbPolPathUser -Name 'Deny_Read'  -Value 0 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path $usbPolPathUser -Name 'Deny_Write' -Value 0 -Type DWord -ErrorAction SilentlyContinue

# 9. Remove browser restrictions
'AllowedDomainsForApps','RestrictSigninToPattern','BrowserSignin','SecondaryGoogleAccountSigninAllowed' | ForEach-Object {
    Remove-ItemProperty -Path $chromePath -Name $_ -ErrorAction SilentlyContinue
}
Remove-ItemProperty -Path $edgePath -Name 'RestrictSigninToPattern' -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $edgePath -Name 'BrowserSignin'           -ErrorAction SilentlyContinue

# 10. State file
Set-Content -Path $stateFile -Value 'UNLOCKED' -Force -Encoding UTF8
Write-Log "Unlock completed"
'@

$unlockScriptContent = $unlockScriptContent -replace '__ROOT_DIR__', $Cfg_RootDir
$unlockScriptContent = $unlockScriptContent -replace '__USB_POL_PATH__', ($Cfg_UsbPolicyBase + '\' + $Cfg_UsbClassGuid)

Set-Content -Path $Cfg_UnlockScriptPath -Value $unlockScriptContent -Encoding UTF8
Write-OK "Unlock script (v5.2) saved: $Cfg_UnlockScriptPath"


# ══════════════════════════════════════════════════════════════════════════════
#  STEP 14 — Security Hotkey Listener (user‑level)
# ══════════════════════════════════════════════════════════════════════════════
Write-Step 'Creating Hotkey Listener (user‑level)'

$listenerPath    = Join-Path $Cfg_ScriptsDir 'BrightUI_HotkeyListener.ps1'
$listenerContent = @"
# ============================================================
#  BrightUI Hotkey Listener – user mode
# ============================================================
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
`$mutex = New-Object System.Threading.Mutex(`$false, 'Global\BrightUI_HotkeyListener_Mutex')
if (-not `$mutex.WaitOne(0, `$false)) { exit }

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using System.Drawing;
using System.IO;
using System.Diagnostics;

public class BrightUIHotkeyForm : Form {
    [DllImport("user32.dll")]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
    [DllImport("user32.dll")]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    private const int WM_HOTKEY = 0x0312;
    private const uint MOD_ALT = 0x0001, MOD_CONTROL = 0x0002, MOD_NOREPEAT = 0x4000;
    private const uint VK_L = 0x4C, VK_U = 0x55;
    private const int HOTKEY_LOCK = 9001, HOTKEY_UNLOCK = 9002;

    private readonly string _stateFile, _logFile, _lockScript, _unlockScript;

    public BrightUIHotkeyForm(string sf, string lf, string ls, string us) {
        _stateFile=sf; _logFile=lf; _lockScript=ls; _unlockScript=us;
        ShowInTaskbar=false; WindowState=FormWindowState.Minimized;
        FormBorderStyle=FormBorderStyle.None; Size=new Size(1,1); Opacity=0;
    }

    private void Log(string msg) { try { File.AppendAllText(_logFile, "["+DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss")+"] "+msg+Environment.NewLine); } catch {} }

    protected override void OnLoad(EventArgs e) {
        base.OnLoad(e); this.Hide();
        uint combo = MOD_CONTROL | MOD_ALT | MOD_NOREPEAT;
        RegisterHotKey(Handle, HOTKEY_LOCK, combo, VK_L);
        RegisterHotKey(Handle, HOTKEY_UNLOCK, combo, VK_U);
        Log("Hotkeys registered");
    }

    protected override void WndProc(ref Message m) {
        if (m.Msg == WM_HOTKEY) {
            int id = m.WParam.ToInt32();
            if (id == HOTKEY_LOCK) RunScript("LOCKED", _lockScript);
            if (id == HOTKEY_UNLOCK) RunScript("UNLOCKED", _unlockScript);
        }
        base.WndProc(ref m);
    }

    private void RunScript(string target, string script) {
        string cur = "LOCKED";
        try { if (File.Exists(_stateFile)) cur = File.ReadAllText(_stateFile).Trim().ToUpper(); } catch {}
        if (cur == target) { Log("Already "+target); return; }
        Log("Hotkey pressed – launching script");
        Process.Start(new ProcessStartInfo {
            FileName = "powershell.exe",
            Arguments = "-WindowStyle Hidden -ExecutionPolicy Bypass -File \""+script+"\"",
            UseShellExecute = true, Verb = "runas"
        });
    }

    protected override void OnFormClosing(FormClosingEventArgs e) {
        UnregisterHotKey(Handle, HOTKEY_LOCK); UnregisterHotKey(Handle, HOTKEY_UNLOCK);
        Log("Listener stopped"); base.OnFormClosing(e);
    }
}
'@

`$sf = '$Cfg_StateFile'; `$log = '$Cfg_LogFile'; `$ls = '$Cfg_LockScriptPath'; `$us = '$Cfg_UnlockScriptPath'
`$form = New-Object BrightUIHotkeyForm(`$sf, `$log, `$ls, `$us)
[System.Windows.Forms.Application]::Run(`$form)
`$mutex.ReleaseMutex(); `$mutex.Dispose()
"@

Set-Content -Path $listenerPath -Value $listenerContent -Encoding UTF8
Write-OK "Hotkey listener script saved: $listenerPath"


# ══════════════════════════════════════════════════════════════════════════════
#  STEP 15 — Startup Shortcuts for Hotkey Listener & Secondary Monitor
# ══════════════════════════════════════════════════════════════════════════════
Write-Step 'Creating Startup shortcuts for hotkey listeners'

$startupDir = [Environment]::GetFolderPath('Startup')

# Primary listener (the one that uses RegisterHotKey)
$primShortcut = Join-Path $startupDir 'BrightUI_HotkeyListener.lnk'
$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut($primShortcut)
$Shortcut.TargetPath = 'powershell.exe'
$Shortcut.Arguments = "-WindowStyle Hidden -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$listenerPath`""
$Shortcut.WorkingDirectory = $Cfg_ScriptsDir
$Shortcut.Save()
Write-OK "Primary hotkey listener shortcut: $primShortcut"

# Secondary keyhook (optional, from BrightUI_Hotkeys.ps1)
$hotkeysPs1Path = Join-Path $Cfg_ScriptsDir 'BrightUI_Hotkeys.ps1'
$hotkeysPs1Content = @'
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class KeyboardHook {
    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int vKey);
}
"@

$unlockScript = "__UNLOCK_SCRIPT__"
$lockScript   = "__LOCK_SCRIPT__"

while ($true) {
    $ctrl = [KeyboardHook]::GetAsyncKeyState(0x11)
    $alt  = [KeyboardHook]::GetAsyncKeyState(0x12)
    $uKey = [KeyboardHook]::GetAsyncKeyState(0x55)
    if (($ctrl -band 0x8000) -and ($alt -band 0x8000) -and ($uKey -band 0x8000)) {
        Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-ExecutionPolicy Bypass -File `"$unlockScript`""
        Start-Sleep -Milliseconds 1000
    }
    $lKey = [KeyboardHook]::GetAsyncKeyState(0x4C)
    if (($ctrl -band 0x8000) -and ($alt -band 0x8000) -and ($lKey -band 0x8000)) {
        Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-ExecutionPolicy Bypass -File `"$lockScript`""
        Start-Sleep -Milliseconds 1000
    }
    Start-Sleep -Milliseconds 100
}
'@
$hotkeysPs1Content = $hotkeysPs1Content -replace '__UNLOCK_SCRIPT__', $Cfg_UnlockScriptPath
$hotkeysPs1Content = $hotkeysPs1Content -replace '__LOCK_SCRIPT__', $Cfg_LockScriptPath
Set-Content -Path $hotkeysPs1Path -Value $hotkeysPs1Content -Encoding UTF8

$secShortcut = Join-Path $startupDir 'BrightUI_Hotkeys_Second.lnk'
$Shortcut2 = $WshShell.CreateShortcut($secShortcut)
$Shortcut2.TargetPath = 'powershell.exe'
$Shortcut2.Arguments = "-WindowStyle Hidden -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$hotkeysPs1Path`""
$Shortcut2.WorkingDirectory = $Cfg_ScriptsDir
$Shortcut2.Save()
Write-OK "Secondary hotkey listener shortcut: $secShortcut"


# ══════════════════════════════════════════════════════════════════════════════
#  STEP 16 — GCPW Installation (admin only, skip if not)
# ══════════════════════════════════════════════════════════════════════════════
Write-Step 'Installing GCPW (admin only)'
if ($script:IsAdmin) {
    try {
        iex (iwr 'https://raw.githubusercontent.com/Tech-Support-Automated/Powershellcode/master/GCPW.ps1').Content
        Write-OK 'GCPW installer executed.'
    } catch { Write-Warn "GCPW failed: $($_.Exception.Message)" }

    & reg add "HKLM\SOFTWARE\Policies\Google\CloudManagement" /v "EnrollmentToken" /t REG_SZ /d "f8a95d69-7c80-4dcb-b7b6-fb91de01dc57" /f
    & reg add "HKLM\Software\Google\GCPW" /v domains_allowed_to_login /t REG_SZ /d "brightuitechnologies.com" /f
    & reg add "HKLM\Software\Google\GCPW" /v validity_period_in_days /t REG_DWORD /d 5 /f
    & reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v dontdisplaylastusername /t REG_DWORD /d 1 /f
    Write-OK 'GCPW registry keys configured.'
} else {
    Write-Skip 'GCPW requires administrator rights.'
}


# ══════════════════════════════════════════════════════════════════════════════
#  FINAL SUMMARY
# ══════════════════════════════════════════════════════════════════════════════
$ld = '=' * 72
Write-Host ''
Write-Host $ld -ForegroundColor Cyan
Write-Host '   BrightUI Technologies  -  Setup v4.7  Completed!' -ForegroundColor Green
Write-Host $ld -ForegroundColor Cyan
Write-Host ''
Write-Host "  All files stored under: $Cfg_RootDir"
Write-Host "  Hotkeys: Ctrl+Alt+L (Lock)  /  Ctrl+Alt+U (Unlock)"
Write-Host "  State file: $Cfg_StateFile"
Write-Host ''
Write-Host '  NEXT STEPS:' -ForegroundColor Yellow
Write-Host '    1.  RESTART this computer.'
Write-Host '    2.  After login, the lock screen image, popup, and hotkeys will be active.'
Write-Host '    3.  To unlock USB, press Ctrl+Alt+U (UAC prompt will appear).'
Write-Host '    4.  For system‑wide USB/GCPW, re‑run the script as Administrator.'
Write-Host ''
Write-Host $ld -ForegroundColor Cyan
Write-Host ''