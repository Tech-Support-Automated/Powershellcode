# 1. Run the first script (GCPW)
Write-Host "Downloading and executing GCPW.ps1..." -ForegroundColor Cyan
iex (iwr 'https://raw.githubusercontent.com/Tech-Support-Automated/Powershellcode/master/GCPW.ps1').Content

# Check if the first script succeeded
if ($?) {
    Write-Host "GCPW.ps1 completed successfully. Moving to script.ps1..." -ForegroundColor Green
    
    # 2. Run the second script
    iex (iwr 'https://raw.githubusercontent.com/Tech-Support-Automated/Powershellcode/master/script.ps1').Content
    
    # Check if the second script succeeded
    if ($?) {
        Write-Host "script.ps1 completed successfully. Restarting the system in 5 seconds..." -ForegroundColor Green
        Start-Sleep -Seconds 5
        
        # 3. Restart the computer
        Restart-Computer -Force
    } else {
        Write-Host "Error: script.ps1 failed to execute properly. The system will not restart." -ForegroundColor Red
    }
} else {
    Write-Host "Error: GCPW.ps1 failed to execute properly. The sequence has been stopped." -ForegroundColor Red
}