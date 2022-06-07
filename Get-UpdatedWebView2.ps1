$ScriptName = 'Get-UpdatedWebView2-v0.02'
# Install the current version of WebView2 from the developer site using the bootstrap installer

# Log to the ProgramData path for IME.  If Diagnostic data is collected, this .log should come along for the ride.
Start-Transcript -Path "$('{0}\Microsoft\IntuneManagementExtension\Logs\{1}-{2}.log' -f $env:ProgramData, $ScriptName, $(Get-Date).ToFileTimeUtc())" | Out-Null
#Start-Transcript -Path "$('{0}-{1}.log' -f $PSCommandPath, $(Get-Date).ToFileTimeUtc())" | Out-Null
Write-Host $ScriptName
Write-Host $PSCommandPath

$appName = 'WebView2'
# Let's use the "Evergreen Bootstrap" installer - https://developer.microsoft.com/en-us/microsoft-edge/webview2/
$InstallerURI = 'https://go.microsoft.com/fwlink/p/?LinkId=2124703'
$InstallerEXE = "$($env:TEMP)\GotUpdatedWebView2.exe"

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


### --- functions begin

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

function Get-InstalledAppVersion {
    # Check for the per-machine install of WebView2 (we're not handing the per-user scenario)
    # https://docs.microsoft.com/en-us/microsoft-edge/webview2/concepts/distribution#detect-if-a-suitable-webview2-runtime-is-already-installed
    $WebViewRegKey = Get-ItemProperty -Path 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}\' -ErrorAction SilentlyContinue
    if ($WebViewRegKey.pv) {
        #Write-Host "WebView2 $WebViewRegKey.pv is installed"
        return [string]$WebViewRegKey.pv
    }
    else {
        #Write-Host "WebView2 is not installed"
        return [string]''
    }
}

function Install-UpdatedWebView2 {
    Write-Host "Fetching the installer..."
    try {
        Write-Host "Starting download to $InstallerEXE"
        #$perf = Measure-Command { Invoke-WebRequest -Uri $InstallerURI -OutFile "$InstallerEXE" -UseBasicParsing }
        #$perf = Measure-Command { Start-BitsTransfer -Source $InstallerURI -Destination "$InstallerEXE" }
        $perf = Measure-Command { (New-Object System.Net.WebClient).DownloadFile("$DownloadURI", "$InstallerEXE") }
        Write-Host "Download completed in $($perf.Seconds) seconds"

        $downloadedVersion = [string]$($(Get-Item "$InstallerEXE").VersionInfo).ProductVersion
        Write-Host "Downloaded $appName version ...: $downloadedVersion"
    }
    catch {
        $exitCode = 1
        throw "Attempted to download file, but failed: $error[0]"
    }

    Write-Host "Starting installation..."
    $SetupArgs = @(
        "/silent"
        "/install"
    )
    # https://docs.microsoft.com/en-us/microsoft-edge/webview2/concepts/distribution#installing-the-runtime-as-per-machine-or-per-user
    # "If you run the installer from an elevated process or command prompt, the Runtime is installed as per-machine."
    Start-Process $InstallerEXE -ArgumentList $SetupArgs -WindowStyle Hidden -PassThru | Out-Null

    # The bootstraper exits before the installation completes, so watch a regkey to determine when it's done
    # https://github.com/MicrosoftEdge/WebView2Feedback/issues/1349
    $retry = 20 # We'll try 20 times, waiting 5 seconds between loops.
     do {
         if ($installedVersion = Get-InstalledAppVersion) {
            $retry = -1
            Write-Output "Finished installing."
        }
        else {
            Write-Output "Waiting for install to finish... ($retry/20)"
            Start-Sleep 5
            $retry = $retry - 1
        }
    } while ($retry -gt 0)

    if ($retry -eq 0) {
        $exitCode = 1
        throw "$appName failed to install: $error[0]"
    }
}

### --- functions end

# Download and install WebView2 for all users
if ($installedVersion = Get-InstalledAppVersion) {
    Write-Host "$appName $installedVersion is already installed"
} else {
    [string]$DownloadURI = Get-RedirectedURI -Uri $InstallerURI
    Write-Host "Download redirected to $DownloadURI"
    Install-UpdatedWebView2
    # check our work
    if ($installedVersion = Get-InstalledAppVersion) {
        Write-Host "$appName $installedVersion was installed for all users"
    } else {
        Write-Host "$appName was NOT installed!"
        $exitCode = 1
    }
}

### ---
Stop-Transcript | Out-Null
exit $exitCode