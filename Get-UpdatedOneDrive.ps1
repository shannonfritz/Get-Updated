# Get-UpdatedOneDrive.ps1
# Updates OneDrive to whatever is the current version available to download for the 32-bit installer that self-updates for 64bit devices

# Log to the ProgramData path for IME.  If Diagnostic data is collected, this .log should come along for the ride.
Start-Transcript -Path "$('{0}\Microsoft\IntuneManagementExtension\Logs\Get-UpdatedOneDrive-{1}.log' -f $env:ProgramData, $(Get-Date).ToFileTimeUtc())" | Out-Null
#Start-Transcript -Path "$('{0}-{1}.log' -f $PSCommandPath, $(Get-Date).ToFileTimeUtc())" | Out-Null
Write-Host $PSCommandPath

# Guidance here suggests getting the 32-bit version which is available at the URL below
# https://support.microsoft.com/en-us/office/choose-between-the-64-bit-and-32-bit-version-of-onedrive-9d36d262-4fc2-4019-a8f6-314ef41a29d1
# "Your device will be automatically updated to 64-bit if it meets the requirements"
# 32bit ... https://go.microsoft.com/fwlink/?linkid=2181213
# 64bit ... https://go.microsoft.com/fwlink/?linkid=2181064

# Can also fetch the URL from https://www.microsoft.com/en-us/microsoft-365/onedrive/download
# The same URL is used in the AutopilotBranding script https://github.com/mtniehaus/AutopilotBranding
# https://go.microsoft.com/fwlink/?linkid=844652

# "If you want to ensure you have the latest version, click here"
# https://support.microsoft.com/en-us/office/onedrive-desktop-app-for-windows-579d71c9-fbdd-4d6a-80ba-d0fac3920aac
# 32bit ... 'https://go.microsoft.com/fwlink/?LinkId=248256'

$appName = 'Microsoft OneDrive'
# Let's use the 64bit installer
$InstallerURI = 'https://go.microsoft.com/fwlink/?linkid=844652'
$InstallerEXE = "$($env:TEMP)\OneDriveSetup.exe"

# Force using TLS 1.2 connection
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Disable the progress bar in Invoke-WebRequest which speeds things up https://github.com/PowerShell/PowerShell/issues/2138
$ProgressPreference = 'SilentlyContinue'

$exitCode = 0

Write-Host "Attempting to update $appName"
if (Test-Path -Path $InstallerEXE -PathType Leaf)
{
    Write-Host "$InstallerEXE already exists.  Assuming this script has already run and exiting clean."
    Stop-Transcript | Out-Null
    exit $exitCode
} else {
    Write-Host "Current installer hasn't been downloaded yet."
}


# Thank you Jeff Bolduan https://winblog.it.umn.edu/2018/05/19/getting-redirected-uris-in-powershell/
function Get-RedirectedUri {
    <#
    .SYNOPSIS
        Gets the real download URL from the redirection.
    .DESCRIPTION
        Used to get the real URL for downloading a file, this will not work if downloading the file directly.
    .EXAMPLE
        Get-RedirectedURL -URL "https://download.mozilla.org/?product=firefox-latest&os=win&lang=en-US"
    .PARAMETER URL
        URL for the redirected URL to be un-obfuscated
    .NOTES
        Code from: Redone per issue #2896 in core https://github.com/PowerShell/PowerShell/issues/2896
    #>
 
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Uri
    )
    process {
        do {
            try {
                $request = Invoke-WebRequest -Method Head -Uri $Uri -UseBasicParsing
                if ($request.BaseResponse.ResponseUri -ne $null) {
                    # This is for Powershell 5
                    $redirectUri = $request.BaseResponse.ResponseUri.AbsoluteUri
                }
                elseif ($request.BaseResponse.RequestMessage.RequestUri -ne $null) {
                    # This is for Powershell core
                    $redirectUri = $request.BaseResponse.RequestMessage.RequestUri.AbsoluteUri
                }
 
                $retry = $false
            }
            catch {
                if (($_.Exception.GetType() -match "HttpResponseException") -and ($_.Exception -match "302")) {
                    $Uri = $_.Exception.Response.Headers.Location.AbsoluteUri
                    $retry = $true
                }
                else {
                    throw $_
                }
            }
        } while ($retry)
 
        $redirectUri
    }
}

# Get the actual download URI from the redirection which looks something like this
# for 32bit - https://oneclient.sfx.ms/Win/Prod/22.065.0412.0004/OneDriveSetup.exe
# for 64bit - https://oneclient.sfx.ms/Win/Prod/22.045.0227.0004/amd64/OneDriveSetup.exe
$DownloadURI = Get-RedirectedURI -Uri $InstallerURI
Write-Host "Download redirected to $DownloadURI"
# Parse the version from the download URI for the 32bit
#$DownloadVer = (Split-Path -Path $DownloadURI -Parent).Split('\')[-1]
# Parse the version from the download URI for the 64bit
$DownloadVer = (Split-Path -Path $DownloadURI -Parent).Split('\')[-2]
Write-Host "Available $appName version ....: $DownloadVer"


# Let's see if we can determine what version is on this device now.
function Get-InstalledAppVersion
{
    $installedVersion = Get-WmiObject -Class Win32_Product | Where-Object {$_.Name -eq $appName}
    if($installedVersion)
    {
        Write-Host "Found OneDrive was pre-installed.  That's unusual, but ok."
        return [string]$($installedVersion.Version)
    }
    elseif (Test-Path ("${env:ProgramFiles}\Microsoft OneDrive\OneDrive.exe"))
    {
        Write-Host "Found the application .exe in Program Files, which is a bit weird if this is x64 Windows, but ok."
        return [string]$($(Get-Item "${env:ProgramFiles}\Microsoft OneDrive\OneDrive.exe").VersionInfo).ProductVersion
    }
    elseif (Test-Path ("${env:ProgramFiles(x86)}\Microsoft OneDrive\OneDrive.exe"))
    {
        Write-Host "Found the 32bit application .exe in Program Files (x86) which should be normal for x64 Windows."
        return [string]$($(Get-Item "${env:ProgramFiles(x86)}\Microsoft OneDrive\OneDrive.exe").VersionInfo).ProductVersion
    }
    elseif (Test-Path ("$env:windir\SysWOW64\OneDriveSetup.exe"))
    {
        Write-Host "Found the 32bit installer in SysWOW64, which should be normal in pre-deployment"
        return [string]$($(Get-Item "$env:windir\SysWOW64\OneDriveSetup.exe").VersionInfo).ProductVersion
    }
    elseif (Test-Path ("$env:windir\System32\OneDriveSetup.exe"))
    {
        Write-Host "Found the installer in System32 which should only happen on x86 Windows(maybe on ARM64?)"
        return [string]$($(Get-Item "$env:windir\System32\OneDriveSetup.exe").VersionInfo).ProductVersion
    }
    else
    {
        Write-Host "Can't seem to find OneDrive anywhere... that's weird."
        return [string]''
    }
}

$preInstalledVersion = Get-InstalledAppVersion
Write-Host "Pre-installed $appName version : $preInstalledVersion"


if ($preInstalledVersion -eq $DownloadVer) {
    Write-Warning "Update not needed! Installed version already matches the latest available."
}
elseif ($preInstalledVersion -gt $DownloadVer) {
    Write-Warning "Update not needed! Installed version is NEWER than the latest available."
}
else {
    try {
        Write-Host "Starting download of: $InstallerEXE"
        #$perf = Measure-Command { Invoke-WebRequest -Uri $InstallerURI -OutFile "$InstallerEXE" -UseBasicParsing }
        #$perf = Measure-Command { Start-BitsTransfer -Source $InstallerURI -Destination "$InstallerEXE" }
    	$client = new-object System.Net.WebClient
	    $perf = Measure-Command { $client.DownloadFile($DownloadURI, $InstallerEXE) }
        Write-Host "Download completed in $($perf.Seconds) seconds"

        $downloadedVersion = [string]$($(Get-Item "$InstallerEXE").VersionInfo).ProductVersion
        Write-Host "Downloaded $appName version ...: $downloadedVersion"
    }
    catch {
        $exitCode = 1
        throw "Attempted to download file, but failed: $error[0]"
    }

    Write-Host "Installing $InstallerEXE"
    $SetupArgs = @(
        "/allusers"
        "/silent"
    )
    
    $perf = Measure-Command { $(Start-Process $InstallerEXE -ArgumentList $SetupArgs -WindowStyle Hidden -PassThru).WaitForExit() }
    Write-Host "Installation completed in $($perf.Seconds) seconds"
    
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

Stop-Transcript | Out-Null
exit $exitCode