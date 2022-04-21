$ScriptName = 'Get-UpdatedDefender-v1.01'
# Updates Microsoft Defender for Endpoint from Windows Update Services
# Variation on the VB script here https://docs.microsoft.com/en-us/previous-versions/windows/desktop/aa387102(v=vs.85)

# Log to the ProgramData path for IME.  If Diagnostic data is collected, this .log should come along for the ride.
Start-Transcript -Path "$('{0}\Microsoft\IntuneManagementExtension\Logs\{1}-{2}.log' -f $env:ProgramData, $ScriptName, $(Get-Date).ToFileTimeUtc())" | Out-Null
#Start-Transcript -Path "$('{0}-{1}.log' -f $PSCommandPath, $(Get-Date).ToFileTimeUtc())" | Out-Null
Write-Host $ScriptName
Write-Host $PSCommandPath

Write-Host "Checking initial status of Defender updates and Signatures"
Get-MpComputerStatus | select *updated, *version

# Initialize UpdateSession, UpdateSearcher, UpdateDownloader and UpdateInstaller, UpdateCollection
$UpdateSession = New-Object -ComObject Microsoft.Update.Session

#RetryOptions - This is needed if we need a prerequisite update for detecting new updates.
$MaxDefenderUpdateRetry = 3
$DefenderUpdateRetry = 0

Do {
    #Increment Retry attempt
    $DefenderUpdateRetry++
    Write-Host "Searching for Windows Defender Product updates ($DefenderUpdateRetry of $MaxDefenderUpdateRetry tries)"

    #Create WU Objects    
    $UpdateSearcher = $UpdateSession.CreateUpdateSearcher()
    $UpdateDownloader = $UpdateSession.CreateUpdateDownloader()
    $UpdateInstaller = $UpdateSession.CreateUpdateInstaller()

    $UpdateSession.ClientApplicationID = $ScriptName

    #Create Update collection for UpdateSearcher Result
    try {
        # https://docs.microsoft.com/en-us/previous-versions/windows/desktop/ff357803(v=vs.85)
        # E0789628-CE08-4437-BE74-2495B842F43B = DefinitionUpdates
        $UpdateScanResult = $UpdateSearcher.Search("IsInstalled = 0 and IsHidden = 0 and CategoryIDs contains 'E0789628-CE08-4437-BE74-2495B842F43B'")
    }
    catch {
        Write-Error ("Error occured: {0}" -f $($_.Exception.Message))
    }

    #Log Search result
    switch ($UpdateScanResult.ResultCode) {
        0 { Write-Warning "Scan result: The operation is not started." }
        1 { Write-Warning "Scan result: The operation is in progress." }
        2 { Write-Host    "Scan result: The operation was completed successfully." }
        3 { Write-Warning "Scan result: The operation is complete, but one or more errors occurred during the operation. The results might be incomplete." }
        4 { Write-Error   "Scan result: The operation failed to complete." }
        5 { Write-Error   "Scan result: The operation is canceled." }
    }

    #If Updates are detected download and install them
    if ($UpdateScanResult.Updates.Count -gt 0) {
        #Create UpdateCollection to Download
        $DefenderUpdatesDownloadColl = New-Object -ComObject Microsoft.Update.UpdateColl
        foreach ($DefenderUpdateScan in $UpdateScanResult.Updates) {
            #Add only updates that is not requiring User prompt
            if ($DefenderUpdateScan.InstallationBehavior.CanRequestUserInput -eq $false) {
                Write-Host ("Adding: {0}." -f $DefenderUpdateScan.title)
            }
            $DefenderUpdatesDownloadColl.Add($DefenderUpdateScan) | Out-Null
        }

        Write-Host ("Number of updates to download : {0}" -f $DefenderUpdatesDownloadColl.count)

        if ($DefenderUpdatesDownloadColl.count -gt 0) {
            $UpdateDownloader.Updates = $DefenderUpdatesDownloadColl
            Write-Host "Downloading updates"
            try {
                $UpdateDownloader.Download() | Out-Null
            }
            catch {
                Write-Error ("Error occured: {0}" -f $($_.Exception.Message))
            }

            #Create Update Collection to Install
            $DefenderUpdatesInstallColl = New-Object -ComObject Microsoft.Update.UpdateColl
            Foreach ($DefUpdateDownload in $UpdateDownloader.Updates) {
                if ($DefUpdateDownload.isDownloaded -eq $true) {
                    Write-Host ("Installing: {0}." -f $DefUpdateDownload.title)
                    $DefenderUpdatesInstallColl.Add($DefUpdateDownload) | Out-Null
                }
            }
            $UpdateInstaller.Updates = $DefenderUpdatesInstallColl
            try {
                $UpdateInstaller.Install() | Out-Null
            }
            catch {
                Write-Error ("Error occured: {0}" -f $($_.Exception.Message))
            }
            $DefenderUpdatesInstallColl = $null
        }

        else {
            Write-Host "No updates were found"
            $DefenderUpdateRetry = $MaxDefenderUpdateRetry
            break
        }

        #Cleaning up...
        $UpdateSearcher = $null
        $UpdateDownloader = $null
        $UpdateInstaller = $null
        $DefenderUpdatesDownloadColl = $null
    }
    else {
        Write-Host "No updates were found"
        $DefenderUpdateRetry = $MaxDefenderUpdateRetry
        break
    }
} While ($DefenderUpdateRetry -lt $MaxDefenderUpdateRetry)

Write-Host "Updating Defender Signatures"
Update-MpSignature

Write-Host "Checking current status of Defender updates and Signatures"
Get-MpComputerStatus | select *updated, *version

Write-Host "Finished." 
Stop-Transcript | Out-Null
exit $exitCode