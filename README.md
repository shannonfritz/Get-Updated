# Get-Updated Apps
Simple PowerShell scripts to update Microsoft Edge, OneDrive and Teams via Intune.

These products typically come built-in to Windows now, but OEM images will never contain the currently available version. Each script here tries to determine if the already-installed version of the app is older than what is currently-available, and if it is, then download and install the never version.  Since each app has it's own distribution mechanisim, but each is being dealt with in basically the same way.

| App | URL | Size | Description |
|:---:|:---:|:---:| --- |
| [Edge](https://www.microsoft.com/en-us/edge/business/download) | [link](https://edgeupdates.microsoft.com/api/products?view=enterprise) | ~120mb | Using [Mattias Benninge's approach](https://www.deploymentresearch.com/using-powershell-to-download-edge-chromium-for-business/) to retrieve the latest Stable x64 installer |
| [OneDrive](https://www.microsoft.com/en-us/microsoft-365/onedrive/download) | [link](https://go.microsoft.com/fwlink/?linkid=844652) | ~50mb | Using [Neihaus' method in Autopilot Branding](https://github.com/mtniehaus/AutopilotBranding) to update OneDrive with latest x64 installer for All Users |
| [Teams](https://docs.microsoft.com/en-us/MicrosoftTeams/msi-deployment) | [link](https://teams.microsoft.com/downloads/desktopurl?env=production&plat=windows&arch=x64&managedInstaller=true&download=true) | ~120mb | Uses the current x64 Teams Machine-Wide installer, but does not make any changes for User copies of Teams |

There is some basic error handling and built-in logic to hopefully prevent unnecessary or repeated downloads.

# Deploying with Intune
For each product you want to get updated, add a new PowerShell script policy, upload the .ps1 file and assign it to a group of devices using these settings:
| Setting | Value |
| --- | --- |
| Run this script using the logged on credentials | No |
| Enforce script signature check | No |
| Run script in 64 bit PowerShell Host | **Yes** |

For devices that are being deployed via Autopilot with the Enrollment Status Page enabled, the script assignment/execution happens during the Device Setup stage just before apps are installed.  By design, they also run during the User setup before their apps are installed.

# Collecting Logs
A PowerShell Transcript log is created in `C:\Microsoft\IntuneManagementExtension\Logs\` which can be harvested directly, or by using the [Collect Diagnostics](https://docs.microsoft.com/en-us/mem/intune/remote-actions/collect-diagnostics) feature to get them in a `.zip` file off the device directly through the Intune portal.  Here's an example:

```
**********************
Attempting to update Microsoft Edge
Current installer hasn't been downloaded yet.
Fetching list of available Edge installers
Checking the latest version available for Stable channel..: 100.0.1185.44
Checking the installed version currently on this device...:
Download redirected to https://msedge.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/b3ed8b52-ee6b-401e-aa19-85b6f3dbfa0e/MicrosoftEdgeEnterpriseX64.msi
Starting download of: MicrosoftEdgeEnterpriseX64.msi as C:\Windows\TEMP\CurrentEdge.msi
Download completed in 2 seconds
Calculated checksum matches the Expcted checksum!
Installing C:\Windows\TEMP\CurrentEdge.msi
Installation completed in 52 seconds
Checking the now-installed version on this device
Installed Version on this device was ..:
Installed Version on this device is ...: 100.0.1185.44
Update was sucessful.
**********************
```

You may find that there are multiple log files for each script because the script actually executes for both the Device and any Users that logs in to it.

# How it works
When a PowerShell script is assigned to a device via Intune, the [Intune Management Extension (IME)](https://docs.microsoft.com/en-us/mem/intune/apps/intune-management-extension) is installed on the device automatically.  The IME service runs in the SYSTEM context and keeps its logs in `C:\Microsoft\IntuneManagementExtension\Logs\`.  Once installed and running, the IME downloads any assigned PowerShell scripts and runs them from the `c:\program files (x86)\microsoft intune management extension\policies\scripts\` dierctory.

During the Windows OOBE / Autopilot process, the IME will be installed then run and complete (or fail) all assigned PowerShell scripts BEFORE any assigned applications are installed.  Scripts will time out after 30mins, but any failures will re-try 3 additional times.  After sucess (or multi-failures), the scripts will not execute again unless the script or policy in Intune is changed.  When assigning multiple scripts, the order that they execute is not predictible. However, because these particular products don't have any dependancy on each other, their install order doesn't really matter.

Scripts will also run whenever a new user signs in to the device, so an attempt was made to prevent the scripts from unnecessarily downloading the installers, but it could probably be managed better.  Today it just checks if an installation file for the product already exists (in $env:TEMP), and if it does then it assums the script already ran the update some time before and just quits gracefully. If the installer file is not found then the script tries to determine what version is currently installed and only downloads if the available version is newer.  It might be better to use a registry key somewhere to indicate the script should just quit, but this seems to be working for now.

# Why not use an Win32 app?
These scripts could eaily be put in a [Win32 .intunewin package](https://docs.microsoft.com/en-us/mem/intune/apps/apps-win32-prepare) and be assigned as an "application" rather than as a script, but there wouldn't be a huge benifit given the way these scripts behave.

**First**, the scripts do not contain the actual installation files, so they are not large file sizes and there would be no tangible benifit from the availability of [Delivery Optomization for Win32 apps](https://docs.microsoft.com/en-us/windows/deployment/do/waas-delivery-optimization#windows-client).  If you packged the installers, you could argue that DO would help, but now you'd have to mantain the packages and revisit them when never versions of the apps are released.  The design of this script is meant to always get the lattest version, on-demand for each device deployment by each individual device.  Assuming you have update policies to keep these products current, that should mean everyone is running the latest version, including those coming right out-of-the-box.

**Second**, the individual installation files are not terribly large by today's standards, althgough with all three combined we're looking at just under 300MB per device.  For large numbers of devices this will add up, but most user-driven deployments are not likely to occur simultaneously enmass, and instead these downloads would be sprinkled around the clock as users unbox and deploy their own machines, perhaps even from home, so the network impact should be manageable.  Of course, YMMV.

**Third**, since the intent of these scripts is to update the products BEFORE a user ever gets a chance to open an older version, using a Win32 app package would require forcing the device to [wait for installation to complete during the ESP](https://docs.microsoft.com/en-us/mem/intune/enrollment/windows-enrollment-status#block-access-to-a-device-until-a-specific-application-is-installed).  Unfortunatly, Intune does not prioritize the delivery of required apps ahead of any other assigned apps, and the installation order is essentially random.  This means if you force ESP to wait for an app (like an updater script package for example), and you also have some other apps assigned to the device, even if the ESP doesn't wait for those other apps, it's possible (even probable) that the ESP could be stuck waiting for some installations other that what is forced by policy.  By using the PowerShell script assignment instead, we are guaranteed to execute and complete these scripts before ANY apps are even assigned.  This way, regardless of the app assignment story, we can be confident these core apps are being updated before the user profile is even created on the device.

**Fourth**, and finally, because this is supposed to be a pretty simple example, so it's not meant to be the ideal. Hopefully, we'll see better and more native ways to get these products updated during OOBE so users can get the fresh and shiny versions of the products they use immediatly when they open their shrink-wrapped devices for the first time.  But until that happens, maybe this will help someone.
