# Sophia Script for Windows 11 - Complete Function Reference
**Version:** 6.9.1
**Source:** https://raw.githubusercontent.com/farag2/Sophia-Script-for-Windows/master/src/Sophia_Script_for_Windows_11/Sophia.ps1

---

## Privacy & Telemetry

### DiagTrackService
- `DiagTrackService -Disable` - Disable the "Connected User Experiences and Telemetry" service
- `DiagTrackService -Enable` - Enable the service (default)

### DiagnosticDataLevel
- `DiagnosticDataLevel -Minimal` - Set diagnostic data collection to minimum
- `DiagnosticDataLevel -Default` - Set to default (default value)

### ErrorReporting
- `ErrorReporting -Disable` - Turn off Windows Error Reporting
- `ErrorReporting -Enable` - Turn on (default)

### FeedbackFrequency
- `FeedbackFrequency -Never` - Change feedback frequency to "Never"
- `FeedbackFrequency -Automatically` - Set to "Automatically" (default)

### ScheduledTasks
- `ScheduledTasks -Disable` - Turn off diagnostics tracking scheduled tasks
- `ScheduledTasks -Enable` - Turn on (default)

### SigninInfo
- `SigninInfo -Disable` - Do not use sign-in info to auto-finish setup after update
- `SigninInfo -Enable` - Use sign-in info (default)

### LanguageListAccess
- `LanguageListAccess -Disable` - Don't let websites access language list
- `LanguageListAccess -Enable` - Allow access (default)

### AdvertisingID
- `AdvertisingID -Disable` - Don't let apps show personalized ads using advertising ID
- `AdvertisingID -Enable` - Allow personalized ads (default)

### WindowsWelcomeExperience
- `WindowsWelcomeExperience -Hide` - Hide Windows welcome experiences after updates
- `WindowsWelcomeExperience -Show` - Show welcome experiences (default)

### WindowsTips
- `WindowsTips -Enable` - Get tips and suggestions when using Windows (default)
- `WindowsTips -Disable` - Do not get tips and suggestions

### SettingsSuggestedContent
- `SettingsSuggestedContent -Hide` - Hide suggested content in Settings app
- `SettingsSuggestedContent -Show` - Show suggested content (default)

### AppsSilentInstalling
- `AppsSilentInstalling -Disable` - Turn off automatic installing of suggested apps
- `AppsSilentInstalling -Enable` - Turn on (default)

### WhatsNewInWindows
- `WhatsNewInWindows -Disable` - Don't suggest ways to finish setting up device
- `WhatsNewInWindows -Enable` - Suggest ways (default)

### TailoredExperiences
- `TailoredExperiences -Disable` - Don't let Microsoft use diagnostic data for personalized tips/ads
- `TailoredExperiences -Enable` - Allow personalized experiences (default)

### BingSearch
- `BingSearch -Disable` - Disable Bing search in Start Menu
- `BingSearch -Enable` - Enable Bing search (default)

### StartRecommendationsTips
- `StartRecommendationsTips -Hide` - Don't show recommendations in Start menu
- `StartRecommendationsTips -Show` - Show recommendations (default)

### StartAccountNotifications
- `StartAccountNotifications -Hide` - Don't show Microsoft account notifications in Start
- `StartAccountNotifications -Show` - Show notifications (default)

---

## UI & Personalization

### ThisPC
- `ThisPC -Show` - Show "This PC" icon on Desktop
- `ThisPC -Hide` - Hide icon (default)

### CheckBoxes
- `CheckBoxes -Disable` - Do not use item check boxes
- `CheckBoxes -Enable` - Use check boxes (default)

### HiddenItems
- `HiddenItems -Enable` - Show hidden files, folders, and drives
- `HiddenItems -Disable` - Do not show (default)

### FileExtensions
- `FileExtensions -Show` - Show file name extensions
- `FileExtensions -Hide` - Hide extensions (default)

### MergeConflicts
- `MergeConflicts -Show` - Show folder merge conflicts
- `MergeConflicts -Hide` - Hide conflicts (default)

### OpenFileExplorerTo
- `OpenFileExplorerTo -ThisPC` - Open File Explorer to "This PC"
- `OpenFileExplorerTo -QuickAccess` - Open to Quick access (default)

### FileExplorerCompactMode
- `FileExplorerCompactMode -Disable` - Disable compact mode (default)
- `FileExplorerCompactMode -Enable` - Enable compact mode

### OneDriveFileExplorerAd
- `OneDriveFileExplorerAd -Hide` - Don't show sync provider notification in File Explorer
- `OneDriveFileExplorerAd -Show` - Show notification (default)

### SnapAssist
- `SnapAssist -Disable` - When snapping window, don't show what can snap next to it
- `SnapAssist -Enable` - Show snap suggestions (default)

### FileTransferDialog
- `FileTransferDialog -Detailed` - Show file transfer dialog in detailed mode
- `FileTransferDialog -Compact` - Show in compact mode (default)

### RecycleBinDeleteConfirmation
- `RecycleBinDeleteConfirmation -Enable` - Display recycle bin delete confirmation
- `RecycleBinDeleteConfirmation -Disable` - Don't display confirmation (default)

### QuickAccessRecentFiles
- `QuickAccessRecentFiles -Hide` - Hide recently used files in Quick access
- `QuickAccessRecentFiles -Show` - Show recent files (default)

### QuickAccessFrequentFolders
- `QuickAccessFrequentFolders -Hide` - Hide frequently used folders in Quick access
- `QuickAccessFrequentFolders -Show` - Show frequent folders (default)

### TaskbarAlignment
- `TaskbarAlignment -Center` - Set taskbar alignment to center (default)
- `TaskbarAlignment -Left` - Set alignment to left

### TaskbarWidgets
- `TaskbarWidgets -Hide` - Hide widgets icon on taskbar
- `TaskbarWidgets -Show` - Show widgets icon (default)

### TaskbarSearch
- `TaskbarSearch -Hide` - Hide search on taskbar
- `TaskbarSearch -SearchIcon` - Show search icon
- `TaskbarSearch -SearchIconLabel` - Show search icon and label
- `TaskbarSearch -SearchBox` - Show search box (default)

### SearchHighlights
- `SearchHighlights -Hide` - Hide search highlights
- `SearchHighlights -Show` - Show search highlights (default)

### TaskViewButton
- `TaskViewButton -Hide` - Hide Task view button from taskbar
- `TaskViewButton -Show` - Show Task view button (default)

### SecondsInSystemClock
- `SecondsInSystemClock -Show` - Show seconds on taskbar clock
- `SecondsInSystemClock -Hide` - Hide seconds (default)

### TaskbarCombine
- `TaskbarCombine -Always` - Combine taskbar buttons and always hide labels (default)
- `TaskbarCombine -Full` - Combine and hide labels when taskbar is full
- `TaskbarCombine -Never` - Never hide labels

### UnpinTaskbarShortcuts
- `UnpinTaskbarShortcuts -Shortcuts Edge, Store, Outlook` - Unpin specified shortcuts from taskbar

### TaskbarEndTask
- `TaskbarEndTask -Enable` - Enable end task in taskbar by right click
- `TaskbarEndTask -Disable` - Disable (default)

### ControlPanelView
- `ControlPanelView -LargeIcons` - View Control Panel icons as large icons
- `ControlPanelView -SmallIcons` - View as small icons
- `ControlPanelView -Category` - View by category (default)

### WindowsColorMode
- `WindowsColorMode -Dark` - Set default Windows mode to dark
- `WindowsColorMode -Light` - Set to light (default)

### AppColorMode
- `AppColorMode -Dark` - Set default app mode to dark
- `AppColorMode -Light` - Set to light (default)

### FirstLogonAnimation
- `FirstLogonAnimation -Disable` - Hide first sign-in animation after upgrade
- `FirstLogonAnimation -Enable` - Show animation (default)

### JPEGWallpapersQuality
- `JPEGWallpapersQuality -Max` - Set JPEG wallpaper quality to maximum
- `JPEGWallpapersQuality -Default` - Set to default

### ShortcutsSuffix
- `ShortcutsSuffix -Disable` - Don't add "- Shortcut" suffix to created shortcuts
- `ShortcutsSuffix -Enable` - Add suffix (default)

### PrtScnSnippingTool
- `PrtScnSnippingTool -Enable` - Use Print Screen button to open screen snipping
- `PrtScnSnippingTool -Disable` - Don't use (default)

### AppsLanguageSwitch
- `AppsLanguageSwitch -Enable` - Let me use different input method for each app window
- `AppsLanguageSwitch -Disable` - Don't use different input method (default)

### AeroShaking
- `AeroShaking -Enable` - When grabbing title bar and shaking, minimize other windows
- `AeroShaking -Disable` - Don't minimize (default)

### Cursors
- `Cursors -Dark` - Download and install dark "Windows 11 Cursors Concept"
- `Cursors -Light` - Download and install light cursors
- `Cursors -Default` - Set default cursors

### FolderGroupBy
- `FolderGroupBy -None` - Don't group files and folders in Downloads folder
- `FolderGroupBy -Default` - Group by date modified (default)

### NavigationPaneExpand
- `NavigationPaneExpand -Disable` - Don't expand to open folder in navigation pane (default)
- `NavigationPaneExpand -Enable` - Expand to open folder

### StartRecommendedSection
- `StartRecommendedSection -Hide` - Remove Recommended section in Start (not Home edition)
- `StartRecommendedSection -Show` - Show Recommended section (default)

---

## OneDrive

### OneDrive
- `OneDrive -Uninstall` - Uninstall OneDrive
- `OneDrive -Install` - Install OneDrive 64-bit (default)
- `OneDrive -Install -AllUsers` - Install OneDrive for all users to %ProgramFiles%

---

## System

### StorageSense
- `StorageSense -Enable` - Turn on Storage Sense
- `StorageSense -Disable` - Turn off (default)

### Hibernation
- `Hibernation -Disable` - Disable hibernation (not recommended for laptops)
- `Hibernation -Enable` - Enable hibernate (default)

### Win32LongPathSupport
- `Win32LongPathSupport -Enable` - Enable Windows long paths support (>260 chars)
- `Win32LongPathSupport -Disable` - Disable (default)

### BSoDStopError
- `BSoDStopError -Enable` - Display Stop error code when BSoD occurs
- `BSoDStopError -Disable` - Don't display (default)

### AdminApprovalMode
- `AdminApprovalMode -Never` - Never notify about changes to computer
- `AdminApprovalMode -Default` - Notify only when apps try to make changes (default)

### DeliveryOptimization
- `DeliveryOptimization -Disable` - Turn off Delivery Optimization
- `DeliveryOptimization -Enable` - Turn on (default)

### WindowsManageDefaultPrinter
- `WindowsManageDefaultPrinter -Disable` - Don't let Windows manage default printer
- `WindowsManageDefaultPrinter -Enable` - Let Windows manage (default)

### WindowsFeatures
- `WindowsFeatures -Disable` - Disable Windows features using pop-up dialog
- `WindowsFeatures -Enable` - Enable Windows features using pop-up dialog

### WindowsCapabilities
- `WindowsCapabilities -Uninstall` - Uninstall optional features using pop-up dialog
- `WindowsCapabilities -Install` - Install optional features using pop-up dialog

### UpdateMicrosoftProducts
- `UpdateMicrosoftProducts -Enable` - Receive updates for other Microsoft products
- `UpdateMicrosoftProducts -Disable` - Don't receive updates (default)

### RestartNotification
- `RestartNotification -Show` - Notify me when restart required to finish updating
- `RestartNotification -Hide` - Don't notify (default)

### RestartDeviceAfterUpdate
- `RestartDeviceAfterUpdate -Enable` - Restart ASAP to finish updating
- `RestartDeviceAfterUpdate -Disable` - Don't restart ASAP (default)

### ActiveHours
- `ActiveHours -Automatically` - Automatically adjust active hours based on usage
- `ActiveHours -Manually` - Manually adjust (default)

### WindowsLatestUpdate
- `WindowsLatestUpdate -Disable` - Don't get latest updates ASAP (default)
- `WindowsLatestUpdate -Enable` - Get latest updates ASAP

### PowerPlan
- `PowerPlan -High` - Set power plan to "High performance" (not recommended for laptops)
- `PowerPlan -Balanced` - Set to "Balanced" (default)

### NetworkAdaptersSavePower
- `NetworkAdaptersSavePower -Disable` - Don't allow turning off network adapters to save power (not recommended for laptops)
- `NetworkAdaptersSavePower -Enable` - Allow (default)

### InputMethod
- `InputMethod -English` - Override default input method to English
- `InputMethod -Default` - Use language list (default)

### Set-UserShellFolderLocation
- `Set-UserShellFolderLocation -Root` - Change user folders to root of drive (interactive)
- `Set-UserShellFolderLocation -Custom` - Select folders manually
- `Set-UserShellFolderLocation -Default` - Change to default values

### LatestInstalled.NET
- `LatestInstalled.NET -Enable` - Use .NET Framework 4.8.1 for old apps
- `LatestInstalled.NET -Disable` - Don't use (default)

### WinPrtScrFolder
- `WinPrtScrFolder -Desktop` - Save screenshots to Desktop when pressing Win+PrtScr
- `WinPrtScrFolder -Default` - Save to Pictures folder (default)

### RecommendedTroubleshooting
- `RecommendedTroubleshooting -Automatically` - Run troubleshooter automatically, then notify
- `RecommendedTroubleshooting -Default` - Ask before running (default)

### ReservedStorage
- `ReservedStorage -Disable` - Disable and delete reserved storage after next update
- `ReservedStorage -Enable` - Enable (default)

### F1HelpPage
- `F1HelpPage -Disable` - Disable help lookup via F1
- `F1HelpPage -Enable` - Enable (default)

### NumLock
- `NumLock -Enable` - Enable Num Lock at startup
- `NumLock -Disable` - Disable at startup (default)

### CapsLock
- `CapsLock -Disable` - Disable Caps Lock
- `CapsLock -Enable` - Enable (default)

### StickyShift
- `StickyShift -Disable` - Turn off pressing Shift 5 times for Sticky keys
- `StickyShift -Enable` - Turn on (default)

### Autoplay
- `Autoplay -Disable` - Don't use AutoPlay for all media and devices
- `Autoplay -Enable` - Use AutoPlay (default)

### ThumbnailCacheRemoval
- `ThumbnailCacheRemoval -Disable` - Disable thumbnail cache removal
- `ThumbnailCacheRemoval -Enable` - Enable (default)

### SaveRestartableApps
- `SaveRestartableApps -Enable` - Automatically save restartable apps and restart on sign-in
- `SaveRestartableApps -Disable` - Turn off (default)

### RestorePreviousFolders
- `RestorePreviousFolders -Disable` - Don't restore previous folder windows at logon (default)
- `RestorePreviousFolders -Enable` - Restore previous folders

### NetworkDiscovery
- `NetworkDiscovery -Enable` - Enable Network Discovery and File/Printer Sharing
- `NetworkDiscovery -Disable` - Disable (default)

### Set-Association
- `Set-Association -ProgramPath "path" -Extension .ext -Icon "icon"` - Register app and associate with extension
- Example: `Set-Association -ProgramPath "%ProgramFiles%\Notepad++\notepad++.exe" -Extension .txt -Icon "%ProgramFiles%\Notepad++\notepad++.exe,0"`

### Export-Associations
- `Export-Associations` - Export all Windows associations to Application_Associations.json

### Import-Associations
- `Import-Associations` - Import all Windows associations from Application_Associations.json

### DefaultTerminalApp
- `DefaultTerminalApp -WindowsTerminal` - Set Windows Terminal as default terminal app
- `DefaultTerminalApp -ConsoleHost` - Set Windows Console Host (default)

### Install-VCRedist
- `Install-VCRedist -Redistributables 2015_2022_x86, 2015_2022_x64` - Install Visual C++ Redistributable Packages

### Install-DotNetRuntimes
- `Install-DotNetRuntimes -Runtimes NET8x64, NET9x64` - Install .NET Runtime 8, 9 x64

### RKNBypass
- `RKNBypass -Enable` - Enable proxying blocked sites from Roskomnadzor (Russia only)
- `RKNBypass -Disable` - Disable (default)

### PreventEdgeShortcutCreation
- `PreventEdgeShortcutCreation -Channels Stable, Beta, Dev, Canary` - Prevent Edge desktop shortcut creation
- `PreventEdgeShortcutCreation -Disable` - Don't prevent (default)

### RegistryBackup
- `RegistryBackup -Enable` - Back up system registry to RegBack folder on restart
- `RegistryBackup -Disable` - Don't back up (default)

---

## WSL

### Install-WSL
- `Install-WSL` - Enable WSL, install latest kernel and Linux distribution

---

## Start Menu

### StartLayout
- `StartLayout -Default` - Show default Start layout (default)
- `StartLayout -ShowMorePins` - Show more pins on Start
- `StartLayout -ShowMoreRecommendations` - Show more recommendations on Start

---

## UWP Apps

### UninstallUWPApps
- `UninstallUWPApps` - Uninstall UWP apps using pop-up dialog
- `UninstallUWPApps -ForAllUsers` - Uninstall for all users using pop-up dialog

---

## Gaming

### XboxGameBar
- `XboxGameBar -Disable` - Disable Xbox Game Bar
- `XboxGameBar -Enable` - Enable (default)

### XboxGameTips
- `XboxGameTips -Disable` - Disable Xbox Game Bar tips
- `XboxGameTips -Enable` - Enable (default)

### GPUScheduling
- `GPUScheduling -Enable` - Turn on hardware-accelerated GPU scheduling (requires restart, dedicated GPU, WDDM 2.7+)
- `GPUScheduling -Disable` - Turn off (default)

---

## Scheduled Tasks

### CleanupTask
- `CleanupTask -Register` - Create "Windows Cleanup" scheduled task (every 30 days)
- `CleanupTask -Delete` - Delete the task

### SoftwareDistributionTask
- `SoftwareDistributionTask -Register` - Create "SoftwareDistribution" cleanup task (every 90 days)
- `SoftwareDistributionTask -Delete` - Delete the task

### TempTask
- `TempTask -Register` - Create "Temp" folder cleanup task (every 60 days)
- `TempTask -Delete` - Delete the task

---

## Microsoft Defender & Security

### NetworkProtection
- `NetworkProtection -Enable` - Enable Microsoft Defender network protection
- `NetworkProtection -Disable` - Disable (default)

### PUAppsDetection
- `PUAppsDetection -Enable` - Enable detection for potentially unwanted apps
- `PUAppsDetection -Disable` - Disable (default)

### DefenderSandbox
- `DefenderSandbox -Enable` - Enable sandboxing for Microsoft Defender
- `DefenderSandbox -Disable` - Disable (default)

### DismissMSAccount
- `DismissMSAccount` - Dismiss Microsoft Defender offer about signing in with MS account

### DismissSmartScreenFilter
- `DismissSmartScreenFilter` - Dismiss offer about turning on SmartScreen for Edge

### EventViewerCustomView
- `EventViewerCustomView -Enable` - Create "Process Creation" custom view in Event Viewer
- `EventViewerCustomView -Disable` - Remove custom view (default)

### PowerShellModulesLogging
- `PowerShellModulesLogging -Enable` - Enable logging for all Windows PowerShell modules
- `PowerShellModulesLogging -Disable` - Disable (default)

### PowerShellScriptsLogging
- `PowerShellScriptsLogging -Enable` - Enable logging for all PowerShell scripts
- `PowerShellScriptsLogging -Disable` - Disable (default)

### AppsSmartScreen
- `AppsSmartScreen -Disable` - SmartScreen doesn't mark downloaded files as unsafe
- `AppsSmartScreen -Enable` - Mark downloaded files as unsafe (default)

### SaveZoneInformation
- `SaveZoneInformation -Disable` - Disable Attachment Manager marking files from Internet as unsafe
- `SaveZoneInformation -Enable` - Enable marking (default)

### WindowsScriptHost
- `WindowsScriptHost -Disable` - Disable Windows Script Host (blocks .js and .vbs)
- `WindowsScriptHost -Enable` - Enable (default)

### WindowsSandbox
- `WindowsSandbox -Enable` - Enable Windows Sandbox (Pro/Enterprise/Education only)
- `WindowsSandbox -Disable` - Disable (default)

### DNSoverHTTPS
- `DNSoverHTTPS -Enable -PrimaryDNS 1.0.0.1 -SecondaryDNS 1.1.1.1` - Enable DNS-over-HTTPS for IPv4
- `DNSoverHTTPS -Disable` - Disable (default)
- `DNSoverHTTPS -ComssOneDNS` - Enable via Comss.one DNS (Russia only)
- Valid IPv4 addresses: 1.0.0.1, 1.1.1.1, 149.112.112.112, 8.8.4.4, 8.8.8.8, 9.9.9.9

### LocalSecurityAuthority
- `LocalSecurityAuthority -Enable` - Enable LSA protection to prevent code injection
- `LocalSecurityAuthority -Disable` - Disable (default)

---

## Context Menu

### MSIExtractContext
- `MSIExtractContext -Show` - Show "Extract all" in .msi context menu
- `MSIExtractContext -Hide` - Hide (default)

### CABInstallContext
- `CABInstallContext -Show` - Show "Install" in .cab context menu
- `CABInstallContext -Hide` - Hide (default)

### EditWithClipchampContext
- `EditWithClipchampContext -Hide` - Hide "Edit with Clipchamp" from media files
- `EditWithClipchampContext -Show` - Show (default)

### EditWithPhotosContext
- `EditWithPhotosContext -Hide` - Hide "Edit with Photos" from media files
- `EditWithPhotosContext -Show` - Show (default)

### EditWithPaintContext
- `EditWithPaintContext -Hide` - Hide "Edit with Paint" from media files
- `EditWithPaintContext -Show` - Show (default)

### PrintCMDContext
- `PrintCMDContext -Hide` - Hide "Print" from .bat and .cmd context menu
- `PrintCMDContext -Show` - Show (default)

### CompressedFolderNewContext
- `CompressedFolderNewContext -Hide` - Hide "Compressed (zipped) Folder" from "New" menu
- `CompressedFolderNewContext -Show` - Show (default)

### MultipleInvokeContext
- `MultipleInvokeContext -Enable` - Enable "Open/Print/Edit" for >15 selected items
- `MultipleInvokeContext -Disable` - Disable (default)

### UseStoreOpenWith
- `UseStoreOpenWith -Hide` - Hide "Look for app in Microsoft Store" in "Open with" dialog
- `UseStoreOpenWith -Show` - Show (default)

### OpenWindowsTerminalContext
- `OpenWindowsTerminalContext -Show` - Show "Open in Windows Terminal" in folders (default)
- `OpenWindowsTerminalContext -Hide` - Hide

### OpenWindowsTerminalAdminContext
- `OpenWindowsTerminalAdminContext -Enable` - Open Terminal as admin by default from context menu
- `OpenWindowsTerminalAdminContext -Disable` - Don't open as admin (default)

---

## Update Policies

### ScanRegistryPolicies
- `ScanRegistryPolicies` - Scan registry and display all policies in gpedit.msc

---

## Special Functions

### InitialActions
- `InitialActions -Warning` - Mandatory checks with warning about preset customization
- `InitialActions` - Run without warning

### Logging
- `Logging` - Enable script logging to script folder

### CreateRestorePoint
- `CreateRestorePoint` - Create a system restore point

### PostActions
- `PostActions` - Environment refresh and necessary post-actions (run at end)

### Errors
- `Errors` - Display errors output (run at end)

---

## Notes

1. **Default values** are indicated in the descriptions
2. **Restart required** for some functions (noted in descriptions)
3. **Edition-specific** functions (Home/Pro/Enterprise/Education) are noted
4. **Hardware requirements** noted where applicable (e.g., GPU scheduling requires WDDM 2.7+)
5. **Regional functions** (Russia-only) are marked

## Usage Examples

### Run entire script:
```powershell
.\Sophia.ps1
```

### Run specific functions:
```powershell
.\Sophia.ps1 -Functions "DiagTrackService -Disable", "DiagnosticDataLevel -Minimal", UninstallUWPApps
```

### With tab completion:
```powershell
. .\Import-TabCompletion.ps1
```
