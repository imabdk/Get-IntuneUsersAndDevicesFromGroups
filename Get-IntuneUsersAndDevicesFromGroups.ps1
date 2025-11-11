<#
.SYNOPSIS
    Get Intune devices from Entra ID groups and populate target groups by OS version

.DESCRIPTION
    Finds devices from user/device groups, filters by iOS/Windows versions, and adds 
    users or devices to target groups. Supports nested groups and Azure Automation.

.EXAMPLE
    # Find users with iOS devices < 18.0 and add to notification group
    .\Get-IntuneUsersAndDevicesFromGroups.ps1 -SourceGroupName @("Sales", "Marketing") -IOSVersion "18.0" -Operator "lt" -TargetGroupName "iOS-Update-Notifications" -AddToGroup Users

.EXAMPLE
    # Get all Windows devices from Finance team and add devices to group (no version filter)
    .\Get-IntuneUsersAndDevicesFromGroups.ps1 -SourceGroupName @("Finance Team") -TargetGroupName "Finance-Windows-Devices" -AddToGroup Devices

.EXAMPLE
    # Discovery mode - report only, no changes
    .\Get-IntuneUsersAndDevicesFromGroups.ps1 -WhatIf

.NOTES
    Authors: 
        Martin Bengtsson (https://imab.dk)
        Christian Frohn (https://www.christianfrohn.dk)
    Date: November 2025
#>

[CmdletBinding()]
param(
    [string[]]$SourceGroupName = @('Team - IT Helpdesk', 'Team - Legal Tech & AI', 'Team - Security and Identity management'),
    [string]$IOSVersion = "26.0.1",
    [string]$WindowsVersion,
    [ValidateSet("eq", "ne", "lt", "le", "gt", "ge")]
    [string]$Operator = "lt",
    [string]$TargetGroupName = "Intune-IT-Users-Needs-iOS-Update",
    [ValidateSet("Users", "Devices", "Both")]
    [string]$AddToGroup = "Users",
    [switch]$ClearTargetGroup = $true,
    [switch]$WhatIf
)

# Output script start immediately
Write-Output "--- SCRIPT STARTING ---"
Write-Output "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Output "PowerShell Version: $($PSVersionTable.PSVersion)"
Write-Output "Parameters received:"
Write-Output "  SourceGroupName: $($SourceGroupName -join ', ')"
Write-Output "  IOSVersion: $IOSVersion"
Write-Output "  WindowsVersion: $WindowsVersion"
Write-Output "  Operator: $Operator"
Write-Output "  TargetGroupName: $TargetGroupName"
Write-Output "  AddToGroup: $AddToGroup"

# Check for required modules
Write-Output ""
Write-Output "Checking for required modules..."
$requiredModules = @(
    'Microsoft.Graph.Authentication',
    'Microsoft.Graph.DeviceManagement',
    'Microsoft.Graph.Groups',
    'Microsoft.Graph.Users'
)

foreach ($moduleName in $requiredModules) {
    $module = Get-Module -ListAvailable -Name $moduleName | Select-Object -First 1
    if ($module) {
        Write-Output "  [OK] $moduleName - Version $($module.Version)"
    } else {
        Write-Output "  [MISSING] $moduleName - NOT FOUND"
        throw "Required module '$moduleName' is not installed"
    }
}

Write-Output ""
Write-Output "Importing modules..."
try {
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
    Write-Output "  [OK] Imported Microsoft.Graph.Authentication"
    Import-Module Microsoft.Graph.DeviceManagement -ErrorAction Stop
    Write-Output "  [OK] Imported Microsoft.Graph.DeviceManagement"
    Import-Module Microsoft.Graph.Groups -ErrorAction Stop
    Write-Output "  [OK] Imported Microsoft.Graph.Groups"
    Import-Module Microsoft.Graph.Users -ErrorAction Stop
    Write-Output "  [OK] Imported Microsoft.Graph.Users"
}
catch {
    Write-Output "ERROR importing modules: $($_.Exception.Message)"
    throw
}

# Connect to Graph
# Detect if running in Azure Automation
if ($env:AUTOMATION_ASSET_ACCOUNTID) {
    # Running in Azure Automation - use managed identity
    Write-Output "Detected Azure Automation environment - using managed identity..."
    
    try {
        # For system-assigned managed identity:
        Connect-MgGraph -Identity -NoWelcome
        Write-Output "Successfully connected to Microsoft Graph using managed identity"
    }
    catch {
        Write-Output "FAILED to connect using managed identity: $($_.Exception.Message)"
        throw
    }
    
    # For user-assigned managed identity, uncomment and set ClientId:
    # $ClientId = "YOUR-USER-ASSIGNED-MANAGED-IDENTITY-CLIENT-ID"
    # Connect-MgGraph -Identity -ClientId $ClientId -NoWelcome
}
else {
    # Running interactively - use delegated permissions
    Write-Output "Running in interactive mode - using delegated permissions..."
    $scopes = @(
        "DeviceManagementManagedDevices.Read.All",
        "Group.Read.All", 
        "Group.ReadWrite.All", 
        "User.Read.All",
        "GroupMember.Read.All",
        "Device.Read.All"
    )
    
    Write-Verbose "Connecting to Microsoft Graph with delegated permissions..."
    Connect-MgGraph -Scopes $scopes -NoWelcome
    Write-Verbose "Connected successfully"
}

# Helper function to compare versions
function Compare-DeviceVersion {
    param(
        [string]$CurrentVersion,
        [string]$TargetVersion,
        [string]$Operator
    )
    
    try {
        # Ensure version strings have at least 2 parts (Major.Minor)
        $currentVer = $CurrentVersion
        $targetVer = $TargetVersion
        if ($currentVer -notmatch '\.') { $currentVer += '.0' }
        if ($targetVer -notmatch '\.') { $targetVer += '.0' }
        
        $current = [version]$currentVer
        $target = [version]$targetVer
        
        switch ($Operator) {
            "eq" { return $current -eq $target }
            "ne" { return $current -ne $target }
            "lt" { return $current -lt $target }
            "le" { return $current -le $target }
            "gt" { return $current -gt $target }
            "ge" { return $current -ge $target }
        }
    } catch {
        Write-Verbose "Failed to parse version: Current=$CurrentVersion, Target=$TargetVersion"
        return $false
    }
}

# Helper function to get devices by OS and version
function Get-DevicesByOSVersion {
    param(
        [string]$OS,
        [string]$Version,
        [string]$Operator
    )
    
    $filter = "operatingSystem eq '$OS'"
    if ($Operator -eq "eq") { $filter += " and osVersion eq '$Version'" }
    elseif ($Operator -eq "ne") { $filter += " and osVersion ne '$Version'" }
    
    $foundDevices = Get-MgDeviceManagementManagedDevice -Filter $filter -All
    
    # Client-side filtering for lt/le/gt/ge operators
    if ($Operator -in @("lt", "le", "gt", "ge")) {
        $foundDevices = $foundDevices | Where-Object {
            Compare-DeviceVersion -CurrentVersion $_.OsVersion -TargetVersion $Version -Operator $Operator
        }
    }
    
    return $foundDevices
}

# Helper function to add members to a group
function Add-MembersToGroup {
    param(
        [array]$Members,
        [string]$GroupId,
        [string]$MemberType,
        [string]$GroupName,
        [bool]$WhatIfMode
    )
    
    if ($Members.Count -eq 0) {
        Write-Output ""
        Write-Output "No $MemberType found to add to group."
        return
    }
    
    Write-Output ""
    Write-Output "Adding $($Members.Count) $MemberType to '$GroupName':"
    
    $counter = 0
    foreach ($member in $Members) {
        $counter++
        
        if ($WhatIfMode) {
            Write-Output "  WHATIF: Would add $($member.DisplayName)"
        } else {
            try {
                New-MgGroupMember -GroupId $GroupId -DirectoryObjectId $member.Id -ErrorAction Stop
                Write-Output "  ADDED: $($member.DisplayName)"
            } catch {
                if ($_.Exception.Message -like "*already exist*" -or $_.Exception.Message -like "*already a member*") {
                    Write-Output "  ALREADY MEMBER: $($member.DisplayName)"
                } else {
                    Write-Output "  FAILED: $($member.DisplayName) - $($_.Exception.Message)"
                }
            }
        }
    }
}

# Helper function to apply version filter to a device
function Test-DeviceVersionFilter {
    param(
        [string]$DeviceOS,
        [string]$DeviceVersion,
        [string]$IOSVersion,
        [string]$WindowsVersion,
        [string]$Operator
    )
    
    # If iOS filter specified and device is iOS, check version
    if ($IOSVersion -and $DeviceOS -eq "iOS") {
        return Compare-DeviceVersion -CurrentVersion $DeviceVersion -TargetVersion $IOSVersion -Operator $Operator
    }
    
    # If Windows filter specified and device is Windows, check version
    if ($WindowsVersion -and $DeviceOS -eq "Windows") {
        return Compare-DeviceVersion -CurrentVersion $DeviceVersion -TargetVersion $WindowsVersion -Operator $Operator
    }
    
    # If a version filter is specified but doesn't match this device's OS, exclude it
    if ($IOSVersion -or $WindowsVersion) {
        return $false
    }
    
    # No version filter specified, include device
    return $true
}

# Helper function to get group members recursively (handles nested groups)
function Get-GroupMembersRecursive {
    param(
        [string]$GroupId,
        [hashtable]$ProcessedGroups = @{}
    )
    
    # Prevent circular references (Group A -> Group B -> Group A)
    if ($ProcessedGroups.ContainsKey($GroupId)) {
        Write-Verbose "Skipping already processed group: $GroupId (circular reference prevention)"
        return @()
    }
    
    $ProcessedGroups[$GroupId] = $true
    Write-Verbose "Retrieving members from group: $GroupId"
    
    $members = Get-MgGroupMember -GroupId $GroupId -All
    $allMembers = @()
    
    foreach ($member in $members) {
        $memberType = $member.AdditionalProperties.'@odata.type'
        
        if ($memberType -eq '#microsoft.graph.group') {
            # Nested group found - recurse into it
            $nestedGroupName = $member.AdditionalProperties.displayName
            Write-Verbose "Found nested group: $nestedGroupName - expanding recursively"
            $nestedMembers = Get-GroupMembersRecursive -GroupId $member.Id -ProcessedGroups $ProcessedGroups
            $allMembers += $nestedMembers
        }
        else {
            # Direct member (user or device) - add it
            $allMembers += $member
        }
    }
    
    return $allMembers
}

try {
    Write-Output "Script started - validating parameters..."
    
    # Validate parameters
    if ($TargetGroupName -and -not $AddToGroup) {
        throw "When using -TargetGroupName, you must specify -AddToGroup (Users, Devices, or Both)"
    }
    
    Write-Output "Parameters validated successfully"
    
    # Enable discovery mode if no TargetGroupName specified
    if (-not $TargetGroupName) {
        Write-Output ""
        Write-Output "--- DISCOVERY MODE - No changes will be made ---"
        Write-Output "Use -TargetGroupName and -AddToGroup to add items to a target group"
        Write-Output ""
    }
    
    # Get devices
    $devices = @()
    
    if ($SourceGroupName) {
        Write-Output ""
        Write-Output "Processing $($SourceGroupName.Count) source group(s)..."
        
        # Pre-fetch all managed devices once if processing any user groups (optimization)
        $allDevicesCached = $null
        $hasUserGroups = $false
        $groupMembersCache = @{}  # Cache recursive member lookups
        
        # First pass: check if any groups contain users and cache members (including nested groups)
        Write-Output "Scanning groups and caching members..."
        foreach ($groupName in $SourceGroupName) {
            Write-Output "  Looking up group: $groupName"
            $checkGroup = Get-MgGroup -Filter "displayName eq '$groupName'" -ErrorAction SilentlyContinue
            if ($checkGroup) {
                $checkMembers = Get-GroupMembersRecursive -GroupId $checkGroup.Id
                $groupMembersCache[$groupName] = $checkMembers
                Write-Output "  Cached $($checkMembers.Count) members from: $groupName"
                
                if ($checkMembers | Where-Object { $_.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.user' }) {
                    $hasUserGroups = $true
                }
            }
            else {
                Write-Output "  WARNING: Group '$groupName' not found"
            }
        }
        
        # If we have user groups, fetch all devices once
        if ($hasUserGroups) {
            Write-Output ""
            Write-Output "Detected user groups - pre-fetching all managed devices..."
            $allDevicesCached = Get-MgDeviceManagementManagedDevice -All -Property "id,deviceName,operatingSystem,osVersion,userId"
            Write-Output "Cached $($allDevicesCached.Count) devices for efficient processing"
        }
        
        foreach ($groupName in $SourceGroupName) {
            Write-Output ""
            Write-Output "Processing group: $groupName"
            $group = Get-MgGroup -Filter "displayName eq '$groupName'"
            if (!$group) { 
                Write-Output "  WARNING: Group not found, skipping..."
                continue 
            }
            
            # Use cached members
            if ($groupMembersCache.ContainsKey($groupName)) {
                $members = $groupMembersCache[$groupName]
            } else {
                $members = Get-GroupMembersRecursive -GroupId $group.Id
            }
            
            # Analyze group membership
            $groupDevices = $members | Where-Object { $_.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.device' }
            $groupUsers = $members | Where-Object { $_.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.user' }
            
            Write-Output "  Group members: $($members.Count) total, $($groupDevices.Count) devices, $($groupUsers.Count) users"
            
            if ($groupDevices.Count -gt 0) {
                Write-Output "  Processing $($groupDevices.Count) devices from group..."
                
                foreach ($device in $groupDevices) {
                    $deviceOS = $device.AdditionalProperties.operatingSystem
                    $deviceVersion = $device.AdditionalProperties.operatingSystemVersion
                    $deviceName = $device.AdditionalProperties.displayName
                    
                    if (Test-DeviceVersionFilter -DeviceOS $deviceOS -DeviceVersion $deviceVersion -IOSVersion $IOSVersion -WindowsVersion $WindowsVersion -Operator $Operator) {
                        # Look up the device in Intune to get userId
                        $intuneDevice = Get-MgDeviceManagementManagedDevice -Filter "deviceName eq '$deviceName'" -ErrorAction SilentlyContinue | Select-Object -First 1
                        
                        $devices += [PSCustomObject]@{
                            Name = $deviceName
                            OS = $deviceOS
                            Version = $deviceVersion
                            UserId = $intuneDevice.UserId
                        }
                    }
                }
                Write-Output "  Found $($devices.Count) matching devices so far"
            }
            
            if ($groupUsers.Count -gt 0) {
                Write-Output "  Processing $($groupUsers.Count) users from group..."
                
                # Use cached devices if available, otherwise fetch
                if ($allDevicesCached) {
                    $allDevices = $allDevicesCached
                } else {
                    $allDevices = Get-MgDeviceManagementManagedDevice -All -Property "id,deviceName,operatingSystem,osVersion,userId"
                }
                
                $userIds = $groupUsers | ForEach-Object { $_.Id }
            
            foreach ($device in $allDevices) {
                if ($device.UserId -in $userIds) {
                    # Apply OS version filtering
                    if (Test-DeviceVersionFilter -DeviceOS $device.OperatingSystem -DeviceVersion $device.OsVersion -IOSVersion $IOSVersion -WindowsVersion $WindowsVersion -Operator $Operator) {
                        $devices += [PSCustomObject]@{
                            Name = $device.DeviceName
                            OS = $device.OperatingSystem
                            Version = $device.OsVersion
                            UserId = $device.UserId
                        }
                    }
                }
            }
            Write-Output "  Found $($devices.Count) matching devices so far"
            }
            
            if ($groupDevices.Count -eq 0 -and $groupUsers.Count -eq 0) {
                Write-Output "  WARNING: Group appears to be empty or contains unsupported member types"
            }
        }
        
        Write-Output ""
        Write-Output "Total devices found: $($devices.Count)"
    }
    else {
        # Get devices by version (organization-wide)
        Write-Output ""
        Write-Output "Querying organization-wide devices by version..."
        if ($IOSVersion) {
            $iosDevices = Get-DevicesByOSVersion -OS "iOS" -Version $IOSVersion -Operator $Operator
            Write-Output "Found $($iosDevices.Count) iOS devices"
            
            foreach ($device in $iosDevices) {
                $devices += [PSCustomObject]@{
                    Name = $device.DeviceName
                    OS = "iOS"
                    Version = $device.OsVersion
                    UserId = $device.UserId
                }
            }
        }
        
        if ($WindowsVersion) {
            $winDevices = Get-DevicesByOSVersion -OS "Windows" -Version $WindowsVersion -Operator $Operator
            Write-Output "Found $($winDevices.Count) Windows devices"
            
            foreach ($device in $winDevices) {
                $devices += [PSCustomObject]@{
                    Name = $device.DeviceName
                    OS = "Windows"
                    Version = $device.OsVersion
                    UserId = $device.UserId
                }
            }
        }
    }
    
    if ($devices.Count -eq 0) {
        Write-Output ""
        Write-Output "No devices found matching criteria"
        return
    }
    
    Write-Output ""
    Write-Output "Looking up primary users for $($devices.Count) devices..."
    
    $uniqueUsers = @{}
    
    # Collect all unique user IDs first
    $allUserIds = @()
    foreach ($device in $devices) {
        if ($device.UserId -and $device.UserId -notin $allUserIds) {
            $allUserIds += $device.UserId
        }
    }
    
    # Batch lookup users if we have any
    if ($allUserIds.Count -gt 0) {
        Write-Output "Querying $($allUserIds.Count) unique users..."
        
        # Query users in batch (Graph supports up to 15 IDs in a filter OR clause, so we batch them)
        $batchSize = 15
        for ($i = 0; $i -lt $allUserIds.Count; $i += $batchSize) {
            $batch = $allUserIds[$i..[Math]::Min($i + $batchSize - 1, $allUserIds.Count - 1)]
            $filterParts = $batch | ForEach-Object { "id eq '$_'" }
            $filter = $filterParts -join " or "
            
            $batchUsers = Get-MgUser -Filter $filter -All -ErrorAction SilentlyContinue
            foreach ($user in $batchUsers) {
                $uniqueUsers[$user.Id] = $user
            }
        }
    }
    
    # Display devices with user info
    Write-Output ""
    Write-Output "--- DEVICES FOUND ---"
    foreach ($device in $devices) {
        $userName = "Unknown User"
        $userId = $device.UserId
        
        # Look up user from our cached batch
        if ($userId -and $uniqueUsers.ContainsKey($userId)) {
            $userName = $uniqueUsers[$userId].DisplayName
        }
        
        Write-Output "$($device.Name) ($($device.OS) $($device.Version)) - $userName"
    }
    
    # Add users or devices to target group
    if ($TargetGroupName) {
        $targetGroup = Get-MgGroup -Filter "displayName eq '$TargetGroupName'"
        if (!$targetGroup) { throw "Target group '$TargetGroupName' not found" }
        
        # Clear target group if requested
        if ($ClearTargetGroup) {
            Write-Output ""
            Write-Output "Clearing existing members from '$TargetGroupName'..."
            $existingMembers = Get-MgGroupMember -GroupId $targetGroup.Id -All
            
            if ($existingMembers.Count -gt 0) {
                Write-Output "Found $($existingMembers.Count) existing members to remove"
                
                $removeCounter = 0
                foreach ($member in $existingMembers) {
                    $removeCounter++
                    $memberType = $member.AdditionalProperties.'@odata.type' -replace '#microsoft.graph.', ''
                    
                    if ($WhatIf) {
                        Write-Output "  WHATIF: Would remove $memberType $($member.AdditionalProperties.displayName)"
                    } else {
                        try {
                            Remove-MgGroupMemberByRef -GroupId $targetGroup.Id -DirectoryObjectId $member.Id
                            Write-Output "  REMOVED: $memberType $($member.AdditionalProperties.displayName)"
                        } catch {
                            Write-Output "  FAILED TO REMOVE: $($member.Id) - $($_.Exception.Message)"
                        }
                    }
                }
                Write-Output "Target group cleared successfully"
            } else {
                Write-Output "Target group is already empty"
            }
        }
        
        # Add devices to group
        if ($AddToGroup -eq "Devices" -or $AddToGroup -eq "Both") {
            if ($devices.Count -gt 0) {
                # Convert devices to Azure AD device objects
                $azureDevices = @()
                foreach ($device in $devices) {
                    $azureDevice = Get-MgDevice -Filter "displayName eq '$($device.Name)'" -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($azureDevice) {
                        $azureDevices += [PSCustomObject]@{
                            Id = $azureDevice.Id
                            DisplayName = $device.Name
                        }
                    } else {
                        Write-Output "  WARNING: Device '$($device.Name)' not found in Azure AD"
                    }
                }
                Add-MembersToGroup -Members $azureDevices -GroupId $targetGroup.Id -MemberType "devices" -GroupName $TargetGroupName -WhatIfMode $WhatIf
            } else {
                Write-Output ""
                Write-Output "No devices found to add to group."
            }
        }
        
        # Add users to group
        if ($AddToGroup -eq "Users" -or $AddToGroup -eq "Both") {
            $userObjects = @($uniqueUsers.Values | ForEach-Object { [PSCustomObject]@{ Id = $_.Id; DisplayName = $_.DisplayName } })
            Add-MembersToGroup -Members $userObjects -GroupId $targetGroup.Id -MemberType "users" -GroupName $TargetGroupName -WhatIfMode $WhatIf
        }
    }
    else {
        # No target group specified - show summary
        Write-Output ""
        Write-Output "--- SUMMARY ---"
        Write-Output "Devices found: $($devices.Count)"
        Write-Output "Unique users: $($uniqueUsers.Count)"
        Write-Output ""
        Write-Output "To add these to a group, use -TargetGroupName and -AddToGroup parameters"
    }
}
catch {
    Write-Output ""
    Write-Output "--- FATAL ERROR ---"
    Write-Output "Error Type: $($_.Exception.GetType().FullName)"
    Write-Output "Error Message: $($_.Exception.Message)"
    Write-Output "Stack Trace: $($_.ScriptStackTrace)"
    Write-Output "Line Number: $($_.InvocationInfo.ScriptLineNumber)"
    Write-Output "Line: $($_.InvocationInfo.Line)"
    throw
}
finally {
    Write-Output ""
    Write-Output "Disconnecting from Microsoft Graph..."
    Disconnect-MgGraph | Out-Null
    Write-Output "Script completed at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
}