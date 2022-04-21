# Get-UpdatedTeams.ps1 v1.02
# Updates Teams to whatever is the current version available to download for the Commercial x64 Machine-Wide installer

# Log to the ProgramData path for IME.  If Diagnostic data is collected, this .log should come along for the ride.
Start-Transcript -Path "$('{0}\Microsoft\IntuneManagementExtension\Logs\Get-UpdatedTeams-{1}.log' -f $env:ProgramData, $(Get-Date).ToFileTimeUtc())" | Out-Null
#Start-Transcript -Path "$('{0}-{1}.log' -f $PSCommandPath, $(Get-Date).ToFileTimeUtc())" | Out-Null
Write-Host $PSCommandPath

# Download the current Teams Machine Wide installer, remove older version and install the downloaded one
# Find the URI at https://docs.microsoft.com/en-us/MicrosoftTeams/msi-deployment

# Commercial x64 MSI
$appName = 'Teams Machine-wide Installer'
$InstallerURI = 'https://teams.microsoft.com/downloads/desktopurl?env=production&plat=windows&arch=x64&managedInstaller=true&download=true'
$InstallerMSI = "$($env:TEMP)\GotUpdatedTeams.msi"
#$filename = ('Teams_windows-{0}.msi' -f [Guid]::NewGuid().ToString())

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
                if ($null -ne $request.BaseResponse.ResponseUri) {
                    # This is for Powershell 5
                    $redirectUri = $request.BaseResponse.ResponseUri.AbsoluteUri
                }
                elseif ($null -ne $request.BaseResponse.RequestMessage.RequestUri) {
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
# for 64bit - https://statics.teams.cdn.office.net/production-windows-x64/1.5.00.9163/Teams_windows_x64.msi
[string]$DownloadURI = Get-RedirectedURI -Uri $InstallerURI
Write-Host "Download redirected to $DownloadURI"
# Parse the version from the download URI
[string]$DownloadVer = (Split-Path -Path $DownloadURI -Parent).Split('\')[-1]
Write-Host "Available $appName version ....: $DownloadVer"

Write-Host "Pre-installed $appName version : " -NoNewline
$preInstalledWMIObj = Get-WmiObject -Class Win32_Product | Where-Object {$_.Name -eq $appName}
[string]$preInstalledVersion = $preInstalledWMIObj.Version
Write-Host $preInstalledVersion

if (-not $preInstalledVersion) {
    Write-Host "Installation is needed! A Pre-Installed version was not found."
    $doinstall = $true
}
elseif (-not $DownloadVer) {
    Write-Warning "Not installing! The currently available version is unknown."
    $doinstall = $false
}
elseif ([version]$preInstalledVersion -eq [version]$DownloadVer) {
    Write-Warning "Update not needed! Installed version already matches the latest available."
    $doinstall = $false
}
elseif ([version]$preInstalledVersion -gt [version]$DownloadVer) {
    Write-Warning "Update not needed! Installed version is NEWER than the latest available."
    $doinstall = $false
}
else {
    Write-Host "Installation needed.  The Pre-Installed version is outdated."
    $doinstall = $true
    Write-Host "Uninstalling older version of $appName"
    $perf = Measure-Command { $preInstalledWMIObj.Uninstall(); }
    Write-Host "Uninstallation took $($perf.Seconds) seconds"
}

if ($doInstall)
{
    try {
        Write-Host "Starting download to $InstallerMSI"
        #$perf = Measure-Command { Invoke-WebRequest -Uri $InstallerURI -OutFile "$InstallerMSI" -UseBasicParsing }
        #$perf = Measure-Command { Start-BitsTransfer -Source $InstallerURI -Destination "$InstallerMSI" }
        $perf = Measure-Command { (New-Object System.Net.WebClient).DownloadFile("$DownloadURI","$InstallerMSI") }
        Write-Host "Download completed in $($perf.Seconds) seconds"
    }
    catch {
        $exitCode = 1
        throw "Attempted to download file, but failed: $error[0]"
    }

    try {
        # Get the version out of the downloaded MSI
        $windowsInstaller = New-Object -com WindowsInstaller.Installer
        $database = $windowsInstaller.GetType().InvokeMember(
            "OpenDatabase", "InvokeMethod", $Null,
            $windowsInstaller, @($InstallerMSI, 0)
        )
 
        $q = "SELECT Value FROM Property WHERE Property = 'ProductVersion'"
        $View = $database.GetType().InvokeMember(
            "OpenView", "InvokeMethod", $Null, $database, ($q)
        )
 
        $View.GetType().InvokeMember("Execute", "InvokeMethod", $Null, $View, $Null)
        $record = $View.GetType().InvokeMember( "Fetch", "InvokeMethod", $Null, $View, $Null )
        $downloadedVersion = $record.GetType().InvokeMember( "StringData", "GetProperty", $Null, $record, 1 )
        Write-Host "Downloaded $appName version ...: $downloadedVersion"
    } catch {
        $exitCode = 1
        throw "Unable to determine verion of downloaded file: $error[0]"
    }

    Write-Host "Installing $InstallerMSI"
    $SetupArgs = @(
        "/I"
        ('"{0}"' -f $InstallerMSI)
        "/qn"
        "/norestart"
        "/L*v"
        "TeamsInstall.log"
    )
    $perf = Measure-Command { Start-Process msiexec.exe -Wait -NoNewWindow -ArgumentList $SetupArgs }
    Write-Host "Installation completed in $($perf.Seconds) seconds"

    Write-Host "Checking the now-installed version on this device"
    $nowInstalledVersion = $(Get-WmiObject -Class Win32_Product | Where-Object {$_.Name -eq $appName}).Version
    Write-Host "Installed Version on this device was ..: $preInstalledVersion"
    Write-Host "Installed Version on this device is ...: $nowInstalledVersion"
    if (-not $preInstalledVersion -and $nowInstalledVersion) {
        Write-Host "Installation sucessful."
    }
    elseif ([version]$preInstalledVersion -lt [version]$nowInstalledVersion) {
        Write-Host "Update was sucessful."
    }
    else {
        Write-Host "Update failed."
        $exitCode = 1
    }
}

Stop-Transcript | Out-Null
exit $exitCode