# Run as Administrator

 Add-Type -AssemblyName System.Drawing

 $SourceImage = "C:\ProgramData\BrightUI\Assets\logo.png"
 $DestFolder = "C:\ProgramData\Microsoft\User Account Pictures"
 if (!(Test-Path $SourceImage)) {
    Write-Host "ERROR: Source image not found: $SourceImage" -ForegroundColor Red
     exit 1
 }

 # Create destination folder
 New-Item -Path $DestFolder -ItemType Directory -Force | Out-Null
 # Generate all required sizes
 $Sizes = @(32,40,48,96,192,200,240,448)
 foreach ($Size in $Sizes) {
    try {
        $Bitmap = [System.Drawing.Image]::FromFile($SourceImage)

         $Resized = New-Object System.Drawing.Bitmap $Size, $Size
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
}
catch {
Write-Host "Failed creating size $Size" -ForegroundColor Red
}
}
# Create main user.png
Copy-Item $SourceImage "$DestFolder\user.png" -Force
# Enable default account picture policy
$PolicyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
if (!(Test-Path $PolicyPath)) {
New-Item -Path $PolicyPath -Force | Out-Null
}
New-ItemProperty `
-Path $PolicyPath `
-Name "UseDefaultTile" `
-Value 1 `
-PropertyType DWord `
-Force | Out-Null
# Remove current user's cached account pictures
$AccountPictures = "$env:APPDATA\Microsoft\Windows\AccountPictures"
if (Test-Path $AccountPictures) {
Remove-Item "$AccountPictures\*" -Force -Recurse -ErrorAction SilentlyContinue
}
# Refresh Explorer
Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Process explorer.exe
Write-Host ""
Write-Host "SUCCESS: BrightUI default account picture installed." -ForegroundColor Green
Write-Host "IMPORTANT: Sign out and sign back in (or restart Windows)." -ForegroundColor Yellow
Write-Host ""
Write-Host "Verify files exist in:" -ForegroundColor Cyan
 Write-Host "C:\ProgramData\Microsoft\User Account Pictures"