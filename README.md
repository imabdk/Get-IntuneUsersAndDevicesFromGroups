# Get-IntuneUsersAndDevicesFromGroups

Find Intune devices from user groups, filter by OS version, and populate target groups with users or devices.

## Usage

```powershell

# Find iOS devices from user groups and add their users to toast notification group
.\Get-IntuneUsersAndDevicesFromGroups.ps1 -SourceGroupName @("Sales Team", "Marketing") -IOSVersion "18.0" -Operator "lt" -TargetGroupName "Toast-Notification-Group" -AddToGroup Users

# Find Windows devices from user groups and add devices to management group
.\Get-IntuneUsersAndDevicesFromGroups.ps1 -SourceGroupName @("IT Helpdesk", "Legal Team") -WindowsVersion "10.0.22000" -Operator "lt" -TargetGroupName "Windows-Devices-Outdated" -AddToGroup Devices

# Get all iOS devices with version less than 26.0.0 and add their users to the toast notification group
.\Get-IntuneUsersAndDevicesFromGroups.ps1 -IOSVersion "26.0.0" -Operator "lt" -TargetGroupName "Toast-Notification-Group" -AddToGroup Users

```

Supports nested groups and works with both users and devices. Requires Microsoft Graph modules.

## Authentication

- **Interactive Mode**: Uses delegated permissions for manual execution
- **Azure Automation**: Automatically detects and uses managed identity

Required permissions:
- `DeviceManagementManagedDevices.Read.All`
- `Group.Read.All` / `Group.ReadWrite.All`
- `GroupMember.Read.All`
- `User.Read.All`
- `Device.Read.All`

## Parameters

**ClearTargetGroup**: Enabled by default, removes existing members from the target group before adding new ones. Essential in automated scenarios to prevent users from receiving notifications for devices they no longer own or that have been updated.

**WhatIf**: Preview mode that shows what changes would be made without executing them. Always start by running the script with `-WhatIf` to verify the expected results before making actual changes to your groups.

## Authors

- Martin Bengtsson ([https://imab.dk](https://imab.dk))
- Christian Frohn ([https://christianfrohn.dk/](https://christianfrohn.dk))