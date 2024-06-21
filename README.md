# Get-Updated Apps
Simple PowerShell scripts to use via Intune to update Microsoft Edge, OneDrive, Teams and Defender.

These products typically/mostly come built-in to Windows now, but OEM images will never contain the currently available version. Each script here tries to determine if the already-installed version of the app is older than what is currently-available, and if it is (or if it is missing), then the never version will be downloaded and installed.

| App | URL | Size | Description |
|:---:|:---:|:---:| --- |
| [Edge](https://www.microsoft.com/en-us/edge/business/download) | [xml](https://edgeupdates.microsoft.com/api/products?view=enterprise) | ~120mb | Using [Mattias Benninge's approach](https://www.deploymentresearch.com/using-powershell-to-download-edge-chromium-for-business/) to retrieve the latest Stable x64 installer |
| [OneDrive](https://www.microsoft.com/en-us/microsoft-365/onedrive/download) | [exe](https://go.microsoft.com/fwlink/?linkid=844652) | ~50mb | Using [Niehaus' method in Autopilot Branding](https://github.com/mtniehaus/AutopilotBranding) to update OneDrive with latest x64 installer for All Users |
| [Teams](https://docs.microsoft.com/en-us/MicrosoftTeams/msi-deployment) | [msi](https://teams.microsoft.com/downloads/desktopurl?env=production&plat=windows&arch=x64&managedInstaller=true&download=true) | ~120mb | Uses the current x64 Teams Machine-Wide installer, but does not make any changes for User copies of Teams.  Configurable option to install only if an older version is found and needs upgrading |
| [Defender](https://docs.microsoft.com/en-us/microsoft-365/security/defender-endpoint/manage-updates-baselines-microsoft-defender-antivirus) | [about](https://devblogs.microsoft.com/scripting/use-powershell-to-update-windows-defender-signatures/) | ~120mb | Using a powershell variation of a [sample VB script](https://docs.microsoft.com/en-us/previous-versions/windows/desktop/aa387102(v=vs.85)) to install Security intelligence updates ([KB2267602](https://www.microsoft.com/en-us/wdsi/defenderupdates)) and Product updates ([KB4052623](https://support.microsoft.com/help/4052623/update-for-windows-defender-antimalware-platform)) then uses [Update-MpSignature](https://docs.microsoft.com/en-us/powershell/module/defender/update-mpsignature) to update antimalware definitions |
| [WebView2](https://developer.microsoft.com/en-us/microsoft-edge/webview2/) | [exe](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/distribution#deploying-the-evergreen-webview2-runtime) | ~120mb | Using the Evergreen Bootstrap Installers to retrieve the latest installer |
| [MMR Service](https://learn.microsoft.com/en-us/azure/virtual-desktop/multimedia-redirection) | [about](https://learn.microsoft.com/en-us/azure/virtual-desktop/multimedia-redirection-intro) | ~1mb | Using the latest MSI installer to update the Multimedia Redirection Service "host component" service, but does not do anything with the browser extention. NOTE: Only for use on an AVD Session Host or Windows 365 CPC! |
| [Remote Help](https://learn.microsoft.com/en-us/mem/intune/fundamentals/remote-help-windows) | [exe](https://www.catalog.update.microsoft.com/Search.aspx?q=remote%20help) | ~7mb | Using the latest exe from the Microsoft Update Catalog to install or update Remote Help |

Each app has it's own distribution mechanisim, but each is being dealt with in basically the same way ... with the exception of Defender.  Where the apps are being updated by downloading their latest installers, Defender is updated directly from Windows Update.  There is some basic error handling and built-in logic to hopefully prevent unnecessary or repeated downloads.

# Deploying with Intune
For each product you want to get updated, add a new PowerShell script policy, upload the .ps1 file and assign it to a group of devices using these settings:
| Setting | Value |
| --- | --- |
| Run this script using the logged on credentials | No |
| Enforce script signature check | No |
| Run script in 64 bit PowerShell Host | **Yes** |

For devices that are being deployed via Autopilot with the Enrollment Status Page enabled, the script assignment/execution happens during the Device Setup stage just before apps are installed.  By design, they also run during the User setup before their apps are installed.

# Collecting Logs
A PowerShell Transcript log is created in `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\` which can be harvested directly, or by using the [Collect Diagnostics](https://docs.microsoft.com/en-us/mem/intune/remote-actions/collect-diagnostics) feature to get them in a `.zip` file off the device directly through the Intune portal.  Here's an example:

```
**********************
Get-UpdatedTeams-v1.03
C:\Program Files (x86)\Microsoft Intune Management Extension\Policies\Scripts\00000000-0000-0000-0000-000000000000_39b7981f-5e68-44d1-8cb2-870bd9de080c.ps1
Attempting to update Teams Machine-wide Installer
Current installer hasn't been downloaded yet.
Download redirected to https://statics.teams.cdn.office.net/production-windows-x64/1.5.00.9163/Teams_windows_x64.msi
Available Teams Machine-wide Installer version ....: 1.5.00.9163
Pre-installed Teams Machine-wide Installer version : 1.3.0.28779
Installation needed.  The Pre-Installed version is outdated.
Uninstalling older version of Teams Machine-wide Installer
Uninstallation took 1 seconds
Starting download to C:\Windows\TEMP\GotUpdatedTeams.msi
Download completed in 1 seconds
Downloaded Teams Machine-wide Installer version ...: 1.5.0.9163
Installing C:\Windows\TEMP\GotUpdatedTeams.msi
Installation completed in 5 seconds
Checking the now-installed version on this device
Installed Version on this device was ..: 1.3.0.28779
Installed Version on this device is ...: 1.5.0.9163
Update was sucessful.
**********************
```

You may find that there are multiple log files for each script because the script actually executes for both the Device and any Users that logs in to it.

# How it works
When a PowerShell script is assigned to a device via Intune, the [Intune Management Extension (IME)](https://docs.microsoft.com/en-us/mem/intune/apps/intune-management-extension) is installed on the device automatically.  The IME service runs in the SYSTEM context and keeps its logs in `C:\Microsoft\IntuneManagementExtension\Logs\`.  Once installed and running, the IME downloads any assigned PowerShell scripts and runs them from the `c:\program files (x86)\microsoft intune management extension\policies\scripts\` dierctory.

During the Windows OOBE / Autopilot process, the IME will be installed then run and complete (or fail) all assigned PowerShell scripts BEFORE any assigned applications are installed.  Scripts will time out after 30mins, but any failures will re-try 3 additional times.  After sucess (or multi-failures), the scripts will not execute again unless the script or policy in Intune is changed.  When assigning multiple scripts, the order that they execute is not predictible. However, because these particular products don't have any dependancy on each other, their install order doesn't really matter.

Scripts will also run whenever a new user signs in to the device, so an attempt was made to prevent the scripts from unnecessarily downloading the installers, but it could probably be managed better.  Today it just checks if an installation file for the product already exists (in $env:TEMP), and if it does then it assums the script already ran the update some time before and just quits gracefully. If the installer file is not found then the script tries to determine what version is currently installed and only downloads if the available version is newer.  It might be better to use a registry key somewhere to indicate the script should just quit, but this seems to be working for now.

# Why not use a Win32 app?
These scripts could easily be put in a [Win32 .intunewin package](https://docs.microsoft.com/en-us/mem/intune/apps/apps-win32-prepare) and be assigned as an "application" rather than as a script, but there wouldn't be a huge benifit given the way these scripts behave.

**First**, the scripts do not contain the actual installation files, so they are not large file sizes and there would be no tangible benifit from the availability of [Delivery Optomization for Win32 apps](https://docs.microsoft.com/en-us/windows/deployment/do/waas-delivery-optimization#windows-client).  If you packged the installers, you could argue that DO would help, but now you'd have to mantain the packages and revisit them when never versions of the apps are released.  The design of this script is meant to always get the latest version, on-demand for each device deployment by each individual device.  Assuming you have update policies to keep these products current, that should mean everyone is running the latest version, including those coming right out-of-the-box.

**Second**, the individual installation files are not terribly large by today's standards, althgough with all scripts combined we're talking about a few hundred MB per device.  For large a number of devices this will add up, but since most user-driven deployments are not likely to occur simultaneously enmass, these downloads would likely be sprinkled around the clock as users unbox and deploy their own machines, perhaps even from home or other locations, so the network impact should be manageable.  Of course, YMMV.

**Third**, By using the PowerShell script assignment instead, we are guaranteed to execute and complete these scripts before ANY apps are even assigned, so we can be confident these "core apps" are being updated before the user profile is even created on the device.  These scripts will update the products BEFORE a user ever gets a chance to open an older version.  By contrast, using a Win32 app package would require forcing the device to [wait for installation to complete during the ESP](https://docs.microsoft.com/en-us/mem/intune/enrollment/windows-enrollment-status#block-access-to-a-device-until-a-specific-application-is-installed).  Unfortunatly, Intune does not prioritize the delivery of required apps ahead of any other assigned apps, and the installation order is essentially random.  This means if you force ESP to wait for an app but you also have other apps assigned, it's possible (even probable) that the ESP could end up waiting for installations of more apps than what is forced by policy.

**Fourth**, and finally, because these are supposed to be some pretty simple examples, so they're not meant to be the ideal solutions. Hopefully, we'll see better and more native ways to get these products updated during OOBE so users can get the fresh and shiny versions of the products they use immediately after they open their shrink-wrapped devices for the first time.  But until that happens, maybe thees will help some of you.
