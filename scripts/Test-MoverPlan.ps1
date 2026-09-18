param(
    [string]$CsvPath = "$PSScriptRoot\..\data\mover-requests.csv"
)

if (-not (Test-Path $CsvPath)) {
    throw "Mover input file was not found: $CsvPath"
}

if (-not (Get-MgContext).Account) {
    throw "No Microsoft Graph session exists."
}

$requiredFields = @(
    "EmployeeId",
    "UserPrincipalName",
    "CurrentDepartment",
    "NewDepartment",
    "NewJobTitle",
    "Action"
)

$departmentGroupMap = @{
    "Finance"                = "SG-IAM-Finance"
    "Human Resources"        = "SG-IAM-HumanResources"
    "Information Technology" = "SG-IAM-InformationTechnology"
}

$records = @(Import-Csv $CsvPath)
$planResults = @()

foreach ($record in $records) {
    $missingValue = $requiredFields |
        Where-Object {
            [string]::IsNullOrWhiteSpace([string]$record.$_)
        }

    if ($missingValue) {
        $planResults += [PSCustomObject]@{
            User   = $record.UserPrincipalName
            Change = "Unknown"
            Status = "BLOCKED: Required value missing"
        }

        continue
    }

    if ($record.Action -ne "Mover") {
        $planResults += [PSCustomObject]@{
            User   = $record.UserPrincipalName
            Change = "Unknown"
            Status = "BLOCKED: Action must be Mover"
        }

        continue
    }

    $user = Get-MgUser `
        -UserId $record.UserPrincipalName `
        -Property Id,EmployeeId,Department,JobTitle,UserPrincipalName `
        -ErrorAction Stop

    if ($user.EmployeeId -ne $record.EmployeeId) {
        $planResults += [PSCustomObject]@{
            User   = $record.UserPrincipalName
            Change = "Identity verification"
            Status = "BLOCKED: EmployeeId mismatch"
        }

        continue
    }

    if ($user.Department -ne $record.CurrentDepartment) {
        $planResults += [PSCustomObject]@{
            User   = $record.UserPrincipalName
            Change = "Department verification"
            Status = "BLOCKED: Current department mismatch"
        }

        continue
    }

    $oldGroupName = $departmentGroupMap[$record.CurrentDepartment]
    $newGroupName = $departmentGroupMap[$record.NewDepartment]

    if (-not $oldGroupName -or -not $newGroupName) {
        $planResults += [PSCustomObject]@{
            User   = $record.UserPrincipalName
            Change = "$($record.CurrentDepartment) -> $($record.NewDepartment)"
            Status = "BLOCKED: Department mapping missing"
        }

        continue
    }

    $oldGroup = Get-MgGroup `
        -Filter "displayName eq '$oldGroupName'" `
        -ErrorAction Stop

    $newGroup = Get-MgGroup `
        -Filter "displayName eq '$newGroupName'" `
        -ErrorAction Stop

    if (-not $oldGroup -or -not $newGroup) {
        $planResults += [PSCustomObject]@{
            User   = $record.UserPrincipalName
            Change = "$oldGroupName -> $newGroupName"
            Status = "BLOCKED: Required group missing"
        }

        continue
    }

    $oldMembership = (
        Get-MgGroupMember -GroupId $oldGroup.Id -All
    ).Id -contains $user.Id

    $newMembership = (
        Get-MgGroupMember -GroupId $newGroup.Id -All
    ).Id -contains $user.Id

    $status = if (-not $oldMembership) {
        "BLOCKED: Existing access not found"
    }
    elseif ($newMembership) {
        "BLOCKED: Target access already exists"
    }
    else {
        "READY: Update identity and access"
    }

    $planResults += [PSCustomObject]@{
        User   = $record.UserPrincipalName
        Change = "$oldGroupName -> $newGroupName"
        Status = $status
    }
}

Write-Host "`nMOVER CHANGE PREVIEW" -ForegroundColor Cyan
$planResults | Format-List User, Change, Status