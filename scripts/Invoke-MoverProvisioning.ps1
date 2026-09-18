param(
    [string]$CsvPath = "$PSScriptRoot\..\data\mover-requests.csv"
)

function Write-MoverAudit {
    param(
        [string]$EmployeeId,
        [string]$UserPrincipalName,
        [string]$Action,
        [string]$Status,
        [string]$Details
    )

    [PSCustomObject]@{
        Timestamp         = (Get-Date).ToString("s")
        EmployeeId        = $EmployeeId
        UserPrincipalName = $UserPrincipalName
        Action            = $Action
        Status            = $Status
        Details           = $Details
    } | Export-Csv `
        -Path "$PSScriptRoot\..\logs\mover-audit.csv" `
        -Append `
        -NoTypeInformation
}

if (-not (Test-Path $CsvPath)) {
    throw "Mover input file was not found: $CsvPath"
}

if (-not (Get-MgContext).Account) {
    throw "No Microsoft Graph session exists."
}

$departmentGroupMap = @{
    "Finance"                = "SG-IAM-Finance"
    "Human Resources"        = "SG-IAM-HumanResources"
    "Information Technology" = "SG-IAM-InformationTechnology"
}

$records = @(Import-Csv $CsvPath)

foreach ($record in $records) {
    $currentStage = "Validation"

    try {
        if ($record.Action -ne "Mover") {
            throw "Action must be Mover."
        }

        $user = Get-MgUser `
            -UserId $record.UserPrincipalName `
            -Property Id,EmployeeId,Department,JobTitle,UserPrincipalName `
            -ErrorAction Stop

        if ($user.EmployeeId -ne $record.EmployeeId) {
            throw "EmployeeId does not match the Entra account."
        }

        $oldGroupName = $departmentGroupMap[$record.CurrentDepartment]
        $newGroupName = $departmentGroupMap[$record.NewDepartment]

        if (-not $oldGroupName -or -not $newGroupName) {
            throw "A required department-to-group mapping is missing."
        }

        $oldGroup = Get-MgGroup `
            -Filter "displayName eq '$oldGroupName'" `
            -ErrorAction Stop

        $newGroup = Get-MgGroup `
            -Filter "displayName eq '$newGroupName'" `
            -ErrorAction Stop

        if (-not $oldGroup -or -not $newGroup) {
            throw "A required security group does not exist."
        }

        $oldMembership = (
            Get-MgGroupMember -GroupId $oldGroup.Id -All
        ).Id -contains $user.Id

        $newMembership = (
            Get-MgGroupMember -GroupId $newGroup.Id -All
        ).Id -contains $user.Id

        $alreadyComplete = (
            $user.Department -eq $record.NewDepartment -and
            $user.JobTitle -eq $record.NewJobTitle -and
            -not $oldMembership -and
            $newMembership
        )

        if ($alreadyComplete) {
            Write-Host "SKIPPED: Mover change already completed." `
                -ForegroundColor Yellow

            Write-MoverAudit `
                -EmployeeId $record.EmployeeId `
                -UserPrincipalName $record.UserPrincipalName `
                -Action "Mover lifecycle change" `
                -Status "Skipped" `
                -Details "Requested identity and access state already exists"

            continue
        }

        if ($user.Department -ne $record.CurrentDepartment) {
            throw "Current department does not match the approved request."
        }

        if (-not $oldMembership) {
            throw "User does not have the expected current access."
        }

        if ($newMembership) {
            throw "User already has the target access. Manual review required."
        }

        $currentStage = "Grant target access"

        New-MgGroupMember `
            -GroupId $newGroup.Id `
            -DirectoryObjectId $user.Id `
            -ErrorAction Stop

        $currentStage = "Update identity attributes"

        Update-MgUser `
            -UserId $user.Id `
            -Department $record.NewDepartment `
            -JobTitle $record.NewJobTitle `
            -ErrorAction Stop

        $currentStage = "Remove previous access"

        Remove-MgGroupMemberByRef `
            -GroupId $oldGroup.Id `
            -DirectoryObjectId $user.Id `
            -ErrorAction Stop

        Write-MoverAudit `
            -EmployeeId $record.EmployeeId `
            -UserPrincipalName $record.UserPrincipalName `
            -Action "Mover lifecycle change" `
            -Status "Success" `
            -Details "$oldGroupName removed; $newGroupName assigned"

        Write-Host "UPDATED: $($record.UserPrincipalName)" `
            -ForegroundColor Green

        Write-Host "DEPARTMENT: $($record.NewDepartment)" `
            -ForegroundColor Green

        Write-Host "JOB TITLE: $($record.NewJobTitle)" `
            -ForegroundColor Green

        Write-Host "REMOVED: $oldGroupName" `
            -ForegroundColor Green

        Write-Host "ASSIGNED: $newGroupName" `
            -ForegroundColor Green
    }
    catch {
        Write-MoverAudit `
            -EmployeeId $record.EmployeeId `
            -UserPrincipalName $record.UserPrincipalName `
            -Action "Mover lifecycle change" `
            -Status "Failed" `
            -Details "Stage: $currentStage; Error: $($_.Exception.Message)"

        Write-Host "FAILED during: $currentStage" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host "Review the user's identity and group state before retrying." `
            -ForegroundColor Yellow
    }
}