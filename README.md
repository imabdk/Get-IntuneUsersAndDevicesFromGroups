# Multi-Platform Device Update Checker

This PowerShell script automatically finds iOS, iPadOS, and Windows devices in Microsoft Intune that are not up to date and adds their primary users to an Entra ID group for toast notification deployment.

## Prerequisites

### Required PowerShell Modules
```powershell
Install-Module Microsoft.Graph.DeviceManagement -Scope CurrentUser
Install-Module Microsoft.Graph.Groups -Scope CurrentUser  
Install-Module Microsoft.Graph.Users -Scope CurrentUser
```

### Microsoft Graph API Permissions
Your app registration needs the following permissions:
- `DeviceManagementManagedDevices.Read.All`
- `GroupMember.ReadWrite.All`
- `User.Read.All`
- `Group.ReadWrite.All`

## Usage

### Basic Usage
```powershell
# Run with default settings (all platforms)
.\Find-OutdatedIOSDevices.ps1

# Query specific platforms only
.\Find-OutdatedIOSDevices.ps1 -Platforms @("iOS", "Windows")

# Specify custom minimum versions
.\Find-OutdatedIOSDevices.ps1 -MinimumVersions @{"iOS"="18.1"; "Windows"="10.0.22000"}

# Use existing group by ID
.\Find-OutdatedIOSDevices.ps1 -TargetGroupId "12345678-1234-1234-1234-123456789012"

# Test run without making changes
.\Find-OutdatedIOSDevices.ps1 -WhatIf

# Test with limited users
.\Find-OutdatedIOSDevices.ps1 -TestLimit 5 -WhatIf
```

### Parameters

| Parameter | Type | Description | Default |
|-----------|------|-------------|---------|
| `MinimumVersions` | Hashtable | Minimum versions for each platform | `@{"iOS"="18.0"; "iPadOS"="18.0"; "Windows"="10.0.22621"}` |
| `Platforms` | String[] | Platforms to query (iOS, iPadOS, Windows) | `@("iOS", "iPadOS", "Windows")` |
| `TargetGroupId` | String | ID of Entra ID group to add users to | Required |
| `TestLimit` | Int | Limit number of users for testing (0 = no limit) | 10 |
| `WhatIf` | Switch | Preview changes without executing | True (enabled by default) |

## What the Script Does

1. **Connects to Microsoft Graph** with required permissions
2. **Queries Intune** for devices across specified platforms (iOS, iPadOS, Windows)
3. **Filters devices** with OS versions below the minimum requirements
4. **Extracts primary users** from outdated devices
5. **Adds users to target group** (avoiding duplicates)
6. **Provides detailed summary** of actions taken

## Output Example

```
Starting Multi-Platform Device Update Check...
Connecting to Microsoft Graph...
Getting target group...
Using group: Device-Update-Notifications (ID: 12345678-1234-1234-1234-123456789012)
Clearing existing group members...
Removed 5 existing members from group
Querying Intune for iOS devices (minimum version: 18.0)...
Found 150 iOS devices total
Found 12 outdated iOS devices
Querying Intune for iPadOS devices (minimum version: 18.0)...
Found 85 iPadOS devices total
Found 8 outdated iPadOS devices
Querying Intune for Windows devices (minimum version: 10.0.22621)...
Found 320 Windows devices total
Found 45 outdated Windows devices

Total outdated devices across all platforms: 65
Processing users...
  ✅ John Doe (john.doe@company.com) - Device: iPhone 12 (iOS 17.5.1)
  ✅ Jane Smith (jane.smith@company.com) - Device: Surface Pro (Windows 10.0.19045)
Found 58 unique users to add to notification group

⚠️  TEST MODE: Limiting to first 10 users (out of 58 total)
Adding users to group 'Device-Update-Notifications'...
  WHATIF: Would add John Doe to group
  WHATIF: Would add Jane Smith to group

--- SUMMARY ---
🧪 TEST MODE ACTIVE (Limited to 10 users)
Platforms queried: iOS, iPadOS, Windows
Total outdated devices: 65
Existing members removed: 5
Users processed: 10
Users added to group: 10
Errors: 0
Target group: Device-Update-Notifications (12345678-1234-1234-1234-123456789012)
```

## Features

- **Multi-Platform Support**: Handles iOS, iPadOS, and Windows devices with platform-specific version logic
- **Smart Version Comparison**: Different comparison logic for Windows builds vs semantic versioning
- **Group Management**: Clears existing members before adding new ones to prevent accumulation
- **Test Mode**: Built-in testing with user limits and WhatIf mode enabled by default
- **User Deduplication**: Handles users with multiple outdated devices intelligently
- **Comprehensive Logging**: Detailed analysis of device-to-user mapping and filtering
- **Error Handling**: Robust error handling with detailed logging and recovery
- **WhatIf Support**: Preview mode to test without making changes
- **Detailed Reporting**: Comprehensive summary of all actions

## Integration with Toast Notifications

After running this script, you can deploy your existing toast notification Win32 app to the populated Entra ID group:

1. **In Intune Admin Center**: Apps > All Apps > [Your Toast Notification App]
2. **Assignments**: Add the target group with "Required" assignment
3. **Configure**: Set appropriate installation timeline and notification settings

## Scheduling

You can schedule this script to run automatically using:

- **Azure Automation**: Recommended for cloud-native approach
- **Windows Task Scheduler**: For on-premises execution
- **Azure Functions**: For serverless execution with timer triggers

## Error Handling

The script includes comprehensive error handling for:
- Microsoft Graph connection issues
- Device query failures
- User lookup problems
- Group membership errors
- Version comparison edge cases

## Security Considerations

- Uses least-privilege Microsoft Graph permissions
- Supports interactive and non-interactive authentication
- Includes audit trail through detailed logging
- Handles sensitive user data appropriately

## Troubleshooting

### Common Issues

1. **Authentication Errors**: Ensure proper app registration and permissions
2. **Device Not Found**: Verify device is enrolled in Intune and synced recently
3. **User Not Found**: Check if user account still exists and is active
4. **Group Permission Errors**: Confirm `GroupMember.ReadWrite.All` permission is granted

### Debug Mode

Run with `-Verbose` for additional debugging information:
```powershell
.\Find-OutdatedIOSDevices.ps1 -Verbose -WhatIf
```

### Version Compatibility

- **Windows**: Uses build numbers for comparison (e.g., 10.0.22621 for Windows 11 22H2)
- **iOS/iPadOS**: Uses semantic versioning (e.g., 18.0, 17.5.1)
- Mixed environments are fully supported with platform-specific logic