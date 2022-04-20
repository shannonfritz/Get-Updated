# Get-UpdatedEdge.ps1
# Updates Edge to whatever is the current version available to download for the x64 Stable Channel

# Log to the ProgramData path for IME.  If Diagnostic data is collected, this .log should come along for the ride.
Start-Transcript -Path "$('{0}\Microsoft\IntuneManagementExtension\Logs\Get-UpdatedEdge-{1}.log' -f $env:ProgramData, $(Get-Date).ToFileTimeUtc())" | Out-Null
#Start-Transcript -Path "$('{0}-{1}.log' -f $PSCommandPath, $(Get-Date).ToFileTimeUtc())" | Out-Null
Write-Host $PSCommandPath

$appName = 'Microsoft Edge'
$Platform = "Windows"
$Architecture = "x64"
$Channel = "Stable"
$InstallerURI = 'https://edgeupdates.microsoft.com/api/products?view=enterprise'
$InstallerMSI = "$($env:TEMP)\CurrentEdge.msi"

# Force using TLS 1.2 connection
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Disable the progress bar in Invoke-WebRequest which speeds things up https://github.com/PowerShell/PowerShell/issues/2138
$ProgressPreference = 'SilentlyContinue'

$exitCode = 0

Write-Host "Attempting to update $appName"
if (Test-Path -Path $InstallerMSI -PathType Leaf)
{
    Write-Host "$InstallerMSI already exists.  Assuming this script has already run and exiting clean."
    Stop-Transcript | Out-Null
    exit $exitCode
} else {
    Write-Host "Current installer hasn't been downloaded yet."
}

try
{
    Write-Host "Fetching list of available Edge installers"
    # Thanks to Matt Benninge who wrote the parsing of Edge JSON
    # https://www.deploymentresearch.com/using-powershell-to-download-edge-chromium-for-business/
    #$response = Invoke-WebRequest -Uri $InstallerURI -Method Get -ContentType "application/json" -UseBasicParsing -ErrorVariable InvokeWebRequestError
    $response = Invoke-WebRequest $InstallerURI -UseBasicParsing
}
catch
{
    $exitCode = 1
    throw "Unable to get HTTP status code 200 from $InstallerURI, but failed: $error[0]"
}

$jsonObj = ConvertFrom-Json $([String]::new($response.Content))
$selectedIndex = [array]::indexof($jsonObj.Product, "$Channel")

Write-Host "Checking the latest version available for $Channel channel..: " -NoNewline
$DownloadVer = (([Version[]](($jsonObj[$selectedIndex].Releases |
    Where-Object { $_.Architecture -eq $Architecture -and $_.Platform -eq $Platform }).ProductVersion) |
    Sort-Object -Descending)[0]).ToString(4)
Write-Host $DownloadVer

# Let's see if we can determine what version is on this device now.
function Get-InstalledAppVersion
{
    $installedVersion = Get-WmiObject -Class Win32_Product | Where-Object {$_.Name -eq $appName}
    if($installedVersion)
    {
        # Found Edge has been Pre-Installed
        return [string]$($installedVersion.Version)
    }
    elseif (Test-Path ("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"))
    {
        # Found the application .exe in Program Files (x86) which should be normal for Edge, even on x64 Windows
        return [string]$($(Get-Item "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe").VersionInfo).ProductVersion
    }
    else
    {
        # Edge wasn't part of Windows 10 until 20H2.  Maybe this is an older version of Windows?
        return [string]''
    }
}

Write-Host "Checking the installed version currently on this device...: " -NoNewline
$preInstalledVersion = Get-InstalledAppVersion
Write-Host $preInstalledVersion

function Remove-EdgeDesktopLnk
{
    # Remove the Desktop Shortcut, if it's there.
    if (Test-Path -Path "$env:PUBLIC\Desktop\Microsoft Edge.lnk")
    {
        Write-Host "Removing Desktop Shortcut"
        Remove-Item -Path "$env:PUBLIC\Desktop\Microsoft Edge.lnk" -Force
    }
}

if ($preInstalledVersion -eq $DownloadVer)
{
    Write-Warning "Update not needed! Installed version already matches the latest available."
    Remove-EdgeDesktopLnk
}
elseif ($preInstalledVersion -gt $DownloadVer) {
    Write-Warning "Update not needed! Installed version is NEWER than the latest available. Different channels?"
    Remove-EdgeDesktopLnk
}
else
{
    # Edge needs to be updated...
    $selectedObject = $jsonObj[$selectedIndex].Releases |
        Where-Object { $_.Architecture -eq $Architecture -and $_.Platform -eq $Platform -and $_.ProductVersion -eq $DownloadVer }

    foreach ($artifact in $selectedObject.Artifacts) {
        $fileName = Split-Path $artifact.Location -Leaf
        Write-Host "Download redirected to $($artifact.Location)"

        # This should be an MSI, but let's make sure
        if ($artifact.ArtifactName -ne 'msi') {
            Write-Warning "$fileName is not an MSI, quitting!"
            $exitCode = 1
        }

        try {
            Write-Host "Starting download of: $fileName as $InstallerMSI"
            #$perf = Measure-Command { Invoke-WebRequest -Uri $artifact.Location -OutFile "$InstallerMSI" -UseBasicParsing }
            #$perf = Measure-Command { Start-BitsTransfer -Source $artifact.Location -Destination "$InstallerMSI" }
    	    $client = new-object System.Net.WebClient
	        $perf = Measure-Command { $client.DownloadFile($artifact.Location, $InstallerMSI) }
            Write-Host "Download completed in $($perf.Seconds) seconds"
        }
        catch {
            $exitCode = 1
            throw "Attempted to download file, but failed: $error[0]"
        }
    
        # Check the file hash to make sure we've got the good stuff
        $checkedHash = (Get-FileHash -Algorithm $artifact.HashAlgorithm -Path "$InstallerMSI").Hash
        if ($checkedHash -ne $artifact.Hash) {
            Write-Warning "Checksum mismatch!"
            Write-Warning "Expected file Hash....: $($artifact.Hash)"
            Write-Warning "Downloaded file Hash..: $checkedHash"
            $exitCode = 1
        }
        else
        {
            Write-Host "Calculated checksum matches the Expcted checksum!"
            Write-Host "Installing $InstallerMSI"
            $SetupArgs = @(
                "/I"
                ('"{0}"' -f $InstallerMSI)
                "DONOTCREATEDESKTOPSHORTCUT=true"
                "/qn"
                "/norestart"
                "/L*v"
                "EdgeInstall.log"
            )
            $perf = Measure-Command { Start-Process msiexec.exe -Wait -NoNewWindow -ArgumentList $SetupArgs }
            Write-Host "Installation completed in $($perf.Seconds) seconds"
            Remove-EdgeDesktopLnk

            Write-Host "Checking the now-installed version on this device"
            $nowInstalledVersion = Get-InstalledAppVersion

            Write-Host "Installed Version on this device was ..: $preInstalledVersion"
            Write-Host "Installed Version on this device is ...: $nowInstalledVersion"
            if ($nowInstalledVersion -gt $preInstalledVersion)
            {
                Write-Host "Update was sucessful."
            }
            else
            {
                Write-Host "Update failed."
                $exitCode = 1
            }
        }
    }

}

# Shouldn't need to do this...
Remove-EdgeDesktopLnk

Stop-Transcript | Out-Null
exit $exitCode