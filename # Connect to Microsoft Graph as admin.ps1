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