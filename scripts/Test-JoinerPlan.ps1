param(
    [string]$CsvPath = "$PSScriptRoot\..\data\new-hires.csv"
)

# Validate the HR input before processing.
& "$PSScriptRoot\Test-JoinerInput.ps1" -CsvPath $CsvPath

if (-not (Get-MgContext).Account) {
    throw "No Microsoft Graph session exists. Run Connect-MgGraph first."
}

$departmentGroupMap = @{
    "Finance"               = "SG-IAM-Finance"
    "Human Resources"       = "SG-IAM-HumanResources"
    "Information Technology" = "SG-IAM-InformationTechnology"
}

$records = @(Import-Csv $CsvPath)
$planResults = @()

foreach ($record in $records) {
    $targetGroupName = $departmentGroupMap[$record.Department]

    if (-not $targetGroupName) {
        $planResults += [PSCustomObject]@{
            EmployeeId = $record.EmployeeId
            User        = $record.DisplayName
            Department  = $record.Department
            TargetGroup = "None"
            Status      = "BLOCKED: Unsupported department"
        }

        continue
    }

    $targetGroup = Get-MgGroup `
        -Filter "displayName eq '$targetGroupName'" `
        -ErrorAction Stop

    if (-not $targetGroup) {
        $planResults += [PSCustomObject]@{
            EmployeeId = $record.EmployeeId
            User        = $record.DisplayName
            Department  = $record.Department
            TargetGroup = $targetGroupName
            Status      = "BLOCKED: Group not found"
        }

        continue
    }

    $existingUser = Get-MgUser `
        -Filter "userPrincipalName eq '$($record.UserPrincipalName)'" `
        -ErrorAction Stop

    $status = if ($existingUser) {
        "SKIP: User already exists"
    }
    else {
        "READY: Create and assign"
    }

    $planResults += [PSCustomObject]@{
        EmployeeId = $record.EmployeeId
        User        = $record.DisplayName
        Department  = $record.Department
        TargetGroup = $targetGroupName
        Status      = $status
    }
}

Write-Host "`nJOINER PROVISIONING PREVIEW" -ForegroundColor Cyan
$planResults | Format-Table -AutoSize