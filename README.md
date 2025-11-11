# Get-IntuneUsersAndDevicesFromGroups

Find Intune devices from user groups, filter by OS version, and populate target groups with users or devices.

## Usage

```powershell

# Find iOS devices from user groups and add their users to notification group
.\Get-IntuneUsersAndDevicesFromGroups.ps1 -SourceGroupName @("Sales Team", "Marketing") -IOSVersion "18.0" -Operator "lt" -TargetGroupName "iOS-Update-Notifications" -AddToGroup Users

# Find Windows devices from groups and add devices to management group
.\Get-IntuneUsersAndDevicesFromGroups.ps1 -SourceGroupName @("IT Helpdesk", "Legal Team") -WindowsVersion "10.0.22000" -Operator "lt" -TargetGroupName "Windows-Devices-Outdated" -AddToGroup Devices

```

Supports nested groups and works with both users and devices. Requires Microsoft Graph modules.