$ScriptName = 'Get-UpdatedRemoteHelp-v0.01'
# Updates or Installs Remote Help with the current version that is available for download

# Log to the ProgramData path for IME.  If Diagnostic data is collected, this .log should come along for the ride.
Start-Transcript -Path "$('{0}\Microsoft\IntuneManagementExtension\Logs\{1}-{2}.log' -f $env:ProgramData, $ScriptName, $(Get-Date).ToFileTimeUtc())" | Out-Null
#Start-Transcript -Path "$('{0}-{1}.log' -f $PSCommandPath, $(Get-Date).ToFileTimeUtc())" | Out-Null
Write-Host $ScriptName
Write-Host $PSCommandPath

# Documentation below has an AKA link to download the latest installer
# https://learn.microsoft.com/en-us/mem/intune/fundamentals/remote-help-windows#download-remote-help
# NOTE: Remote Help will also install WebView2 if needed

$appName = 'Remote Help'
$InstallerURI = 'https://aka.ms/downloadremotehelp'
$InstallerEXE = "$($env:TEMP)\GotUpdatedRemoteHelp.exe"

# Force using TLS 1.2 connection
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Disable the progress bar in Invoke-WebRequest which speeds things up https://github.com/PowerShell/PowerShell/issues/2138
$ProgressPreference = 'SilentlyContinue'

$exitCode = 0

Write-Host "Attempting to update $appName"
if (Test-Path -Path $InstallerEXE -PathType Leaf) {
    Write-Host "$InstallerEXE already exists.  Assuming this script has already run and exiting clean."
    Stop-Transcript | Out-Null
    exit $exitCode
}
else {
    Write-Host "Current installer hasn't been downloaded yet."
}

# Let's see if we can determine what version is on this device now.
function Get-InstalledAppVersion {
    # Try getting the version directly from the registry first (it's faster than WMI)
    $installedVersion = Get-ItemProperty -Path "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" | Where-Object { $_.DisplayName -match $appName }
    if ($installedVersion) {
        Write-Host "Found $appName is already installed."
        return [string]$($installedVersion.DisplayVersion)
    }

    $installedVersion = Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -eq $appName }
    if ($installedVersion) {
        Write-Host "Found $appName is already installed."
        return [string]$($installedVersion.Version)
    }

    Write-Host "Did not find $appName already installed."
        return [string]''
}

Write-Host "Checking for pre-installed version of $appName"
if ($preInstalledVersion = Get-InstalledAppVersion) {
    Write-Host "Pre-installed $appName version : $preInstalledVersion"
}

Write-Host "Starting download to $InstallerEXE"
try {
    #$perf = Measure-Command { Invoke-WebRequest -Uri $InstallerURI -OutFile "$InstallerEXE" -UseBasicParsing }
    #$perf = Measure-Command { Start-BitsTransfer -Source $InstallerURI -Destination "$InstallerEXE" }
    $perf = Measure-Command { (New-Object System.Net.WebClient).DownloadFile("$InstallerURI", "$InstallerEXE") }
    Write-Host "Download completed in $($perf.Seconds) seconds"
}
catch {
    Write-Error "Download failed : $_"
    $exitCode = 1
    throw "Attempted to download file, but failed: $error[0]"
}

$downloadedVersion = [string]$($(Get-Item "$InstallerEXE").VersionInfo).ProductVersion
Write-Host "Downloaded $appName version ...: $downloadedVersion"

if ($downloadedVersion -lt $preInstalledVersion) {
    Write-Host "Downloaded version is older than the preinstalled version.  Quitting."
} elseif ($downloadedVersion -eq $preInstalledVersion) {
    Write-Host "Downloaded version is the same as the preinstalled version.  Quitting."
} else {
    Write-Host "Installing $InstallerEXE"
    $SetupArgs = @(
        "/install"
        "/quiet acceptTerms=1"
    )
    
    $perf = Measure-Command { $(Start-Process $InstallerEXE -ArgumentList $SetupArgs -WindowStyle Hidden -PassThru).WaitForExit() }
    Write-Host "Installation completed in $($perf.Seconds) seconds"
    
    Write-Host "Checking the now-installed version on this device"
    $nowInstalledVersion = Get-InstalledAppVersion

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
