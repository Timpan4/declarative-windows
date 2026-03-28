<#
	.SYNOPSIS
	Custom Sophia Script Preset for declarative-windows

	.DESCRIPTION
	This preset file contains customized Windows 11 tweaks and configurations.
	Verified against Sophia Script v7.1.4 for Windows 11.

	This preset handles ALL UI tweaks, registry customizations, and OS settings.
	AutoUnattend.xml only handles installation-time tasks (manual disk selection flow, bloatware removal).

	.NOTES
	Tested with: Sophia Script v7.1.4
	Windows 11: 24H2 or later
	Reference: SOPHIA-FUNCTIONS-REFERENCE.md

	.LINK
	https://github.com/farag2/Sophia-Script-for-Windows

	USAGE:
	1. Download Sophia Script for Windows 11 from GitHub releases
	2. Extract the archive
	3. Copy this preset file into the extracted Sophia Script folder
	4. Run: .\Sophia.ps1 -Preset .\Sophia-Preset.ps1
#>

#region Privacy & Telemetry
# Disable telemetry diagnostic tracking service
DiagTrackService -Disable

# Set diagnostic data collection to minimal
DiagnosticDataLevel -Minimal

# Turn off Windows Error Reporting
ErrorReporting -Disable

# Disable Windows feedback requests
FeedbackFrequency -Never

# Turn off diagnostics tracking scheduled tasks
ScheduledTasks -Disable

# Don't let websites access language list
LanguageListAccess -Disable

# Disable advertising ID for personalized ads
AdvertisingID -Disable

# Hide Windows welcome experiences after updates
WindowsWelcomeExperience -Hide

# Don't get tips and suggestions when using Windows
WindowsTips -Disable

# Hide suggested content in Settings app
SettingsSuggestedContent -Hide

# Turn off automatic installing of suggested apps
AppsSilentInstalling -Disable

# Don't suggest ways to finish setting up device
WhatsNewInWindows -Disable

# Don't let Microsoft use diagnostic data for personalized tips/ads
TailoredExperiences -Disable

# Disable Bing search in Start Menu
BingSearch -Disable

# Don't show recommendations in Start
StartRecommendationsTips -Hide

# Don't show account-related notifications in Start
StartAccountNotifications -Hide
#endregion Privacy & Telemetry

#region UI & Personalization
# Show file extensions in Explorer
FileExtensions -Show

# Show hidden files, folders, and drives
HiddenItems -Enable

# Show "This PC" on desktop
ThisPC -Show

# Set Windows color mode to dark
WindowsColorMode -Dark

# Set app color mode to dark
AppColorMode -Dark

# Open File Explorer to "This PC"
OpenFileExplorerTo -ThisPC

# Hide search highlights
SearchHighlights -Hide

# Hide widgets icon on taskbar
TaskbarWidgets -Hide

# Set taskbar alignment to left (classic style)
TaskbarAlignment -Left

# Show search icon on taskbar (no label/box)
TaskbarSearch -SearchIcon

# Hide task view button from taskbar
TaskViewButton -Hide

# Show seconds in system clock
SecondsInSystemClock -Show

# Disable snap assist flyout
SnapAssist -Disable

# Show detailed file transfer dialog
FileTransferDialog -Detailed

# Hide Quick Access recent files
QuickAccessRecentFiles -Hide

# Hide Quick Access frequent folders
QuickAccessFrequentFolders -Hide

# Disable Print Screen key to open Snipping Tool
PrtScnSnippingTool -Disable

# Disable Aero Shake
AeroShaking -Disable

# Don't show "how to use Windows" tips
WindowsTips -Disable
#endregion UI & Personalization

#region OneDrive
# Uninstall OneDrive (if you don't use it, its uninstalled in unattend.xml)
# OneDrive -Uninstall
#endregion OneDrive

#region System
# Enable storage sense (auto cleanup)
StorageSense -Enable

# Keep hibernation at the Windows default unless you explicitly want it off
# Hibernation -Disable

# Keep the default balanced power plan for main-machine use
# PowerPlan -High

# Enable long path support (>260 characters)
Win32LongPathsSupport -Enable

# Don't let Windows manage default printer
WindowsManageDefaultPrinter -Disable

# Ask for restart notification
RestartNotification -Show

# Set active hours automatically
ActiveHours -Automatically

# Disable reserved storage
ReservedStorage -Disable

# Disable F1 help key
F1HelpPage -Disable

# Turn on Num Lock on startup
NumLock -Enable

# Disable Sticky Shift key
StickyShift -Disable

# Disable autoplay for all media
Autoplay -Disable

# Keep zone information on downloaded files for SmartScreen/Attachment Manager
# SaveZoneInformation -Disable
#endregion System

#region Windows Features
# Install Windows Subsystem for Linux when explicitly needed
# Install-WSL

# Note: .NET 3.5 can be installed via WindowsCapabilities if needed
# WindowsCapabilities -Install -Names "NetFx3~~~~"
#endregion Windows Features

#region Start Menu
# Use default Start layout (removes pins)
StartLayout -Default
#endregion Start Menu

#region UWP Apps
# Uninstall bloatware UWP apps using pop-up dialog
# UninstallUWPApps

# Note: AutoUnattend.xml already removes these during installation:
# - Microsoft Teams/Chat, Bing News/Weather, Office Hub, OneNote, Solitaire, etc.
#endregion UWP Apps

#region Gaming
# Disable Xbox Game Bar
XboxGameBar -Disable

# Disable Xbox Game tips
XboxGameTips -Disable

# Enable hardware-accelerated GPU scheduling (requires restart, dedicated GPU)
# GPUScheduling -Enable
#endregion Gaming

#region Scheduled Tasks
# Delete Sophia Windows cleanup scheduled task if it exists
CleanupTask -Delete

# Delete Sophia SoftwareDistribution cleanup task if it exists
SoftwareDistributionTask -Delete

# Delete Sophia temp cleanup task if it exists
TempTask -Delete
#endregion Scheduled Tasks

#region Microsoft Defender & Security
# Enable Microsoft Defender Exploit Guard network protection
NetworkProtection -Enable

# Enable detection for potentially unwanted applications
PUAppsDetection -Enable

# Enable Microsoft Defender Sandbox
DefenderSandbox -Enable

# Keep SmartScreen enabled for apps and downloaded files
# AppsSmartScreen -Disable

# Optional: enable DNS-over-HTTPS with a named provider if you want to force it
# DNSoverHTTPS -Cloudflare
#endregion Microsoft Defender & Security

#region Context Menu
# Show "Extract all" in .msi context menu
MSIExtractContext -Show

# Show "Install" in .cab context menu
CABInstallContext -Show

# Hide "Edit with Clipchamp" from media files
EditWithClipchampContext -Hide

# Show "Open in Windows Terminal" in folders
OpenWindowsTerminalContext -Show

# Note: Classic context menu is handled by AutoUnattend.xml (registry tweak)
#endregion Context Menu

<#
	VERIFIED AGAINST: Sophia Script v7.1.4
	REFERENCE: SOPHIA-FUNCTIONS-REFERENCE.md

	DIVISION OF RESPONSIBILITIES:
	- AutoUnattend.xml: Installation tasks, bloatware removal, classic context menu, mouse acceleration
	- Sophia Script: All UI tweaks, privacy settings, performance tuning (this file)

	WHAT THIS PRESET INCLUDES:
	1. Privacy: Disabled telemetry, Bing, tips, suggested content, tailored experiences
	2. UI: Dark mode, show file extensions/hidden files, left taskbar, minimal icons
	3. System: storage sense, long paths, conservative main-machine defaults
	4. Security: Network protection, PUA detection, Defender sandbox
	5. Debloat: Disabled Xbox features, autoplay, unnecessary scheduled tasks

	TO CUSTOMIZE:
	- Comment out lines you don't want (add # at the beginning)
	- Uncomment lines you want (remove # at the beginning)
	- Refer to SOPHIA-FUNCTIONS-REFERENCE.md for all available functions

	TESTING:
	Always test in a VM before applying to your main system!
#>
