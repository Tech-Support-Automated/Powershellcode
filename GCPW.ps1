# Temp Location
$tempPath = "C:\TempApps"

if (!(Test-Path $tempPath)) {
    New-Item -ItemType Directory -Path $tempPath | Out-Null
}

# Download URL
$gcpwUrl = "https://dl.google.com/tag/s/appguid=%7B32987697-A14E-4B89-84D6-630D5431E831%7D&needsadmin=true&appname=GCPW&etoken=f8a95d69-7c80-4dcb-b7b6-fb91de01dc57/credentialprovider/gcpwstandaloneenterprise64.exe"

# Save EXE
$gcpwExe = "$tempPath\gcpwstandaloneenterprise64.exe"

# Download File
Invoke-WebRequest -Uri $gcpwUrl -OutFile $gcpwExe

# Install Silently
Start-Process $gcpwExe -ArgumentList "/silent /install" -Wait

Write-Host "GCPW Installed Successfully"