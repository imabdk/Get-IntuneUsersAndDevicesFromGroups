<#
.SYNOPSIS
    Assign Microsoft Graph permissions to Azure Automation managed identity

.DESCRIPTION
    This script assigns the necessary Microsoft Graph application permissions to an 
    Azure Automation managed identity for the Get-IntuneUsersAndDevicesFromGroups script.
    
    Required permissions:
    - DeviceManagementManagedDevices.Read.All
    - Group.Read.All / Group.ReadWrite.All
    - User.Read.All
    - GroupMember.Read.All
    - Device.Read.All

.PARAMETER managedIdentityName
    Name of the Azure Automation Account (for system-assigned) or managed identity name (for user-assigned)

.NOTES
    Authors: 
        Martin Bengtsson (https://imab.dk)
        Christian Frohn (https://christianfrohn.dk)
    Date: November 2025
    Requires Global Administrator or Application Administrator role
    Run this once per managed identity setup
#>

# Connect to Microsoft Graph as admin
Connect-MgGraph -Scopes "Application.Read.All", "AppRoleAssignment.ReadWrite.All"

# Get the managed identity service principal
# For system-assigned: use your Automation Account name
# For user-assigned: use your managed identity name
$managedIdentityName = ""  # or managed identity name
$managedIdentity = Get-MgServicePrincipal -Filter "displayName eq '$managedIdentityName'"

# Get Microsoft Graph service principal
$graphSP = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"

# Define required permissions for your script
$requiredPermissions = @(
    "DeviceManagementManagedDevices.Read.All",
    "Group.Read.All",
    "Group.ReadWrite.All",
    "User.Read.All",
    "GroupMember.Read.All",
    "Device.Read.All"
)

# Assign each permission
foreach ($permissionName in $requiredPermissions) {
    $appRole = $graphSP.AppRoles | Where-Object {
        $_.Value -eq $permissionName -and $_.AllowedMemberTypes -contains "Application"
    }
    
    if ($appRole) {
        try {
            New-MgServicePrincipalAppRoleAssignment `
                -ServicePrincipalId $managedIdentity.Id `
                -PrincipalId $managedIdentity.Id `
                -ResourceId $graphSP.Id `
                -AppRoleId $appRole.Id `
                -ErrorAction Stop
            
            Write-Host "[OK] Assigned: $permissionName" -ForegroundColor Green
        }
        catch {
            Write-Warning "Failed to assign $permissionName : $_"
        }
    }
}

Disconnect-MgGraph