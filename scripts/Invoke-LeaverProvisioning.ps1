param(
    [string]$CsvPath = "$PSScriptRoot\..\data\leaver-requests.csv"
)

function Write-LeaverAudit {
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
        -Path "$PSScriptRoot\..\logs\leaver-audit.csv" `
        -Append `
        -NoTypeInformation
}

if (-not (Test-Path $CsvPath)) {
    throw "Leaver input file was not found: $CsvPath"
}

if (-not (Get-MgContext).Account) {
    throw "No Microsoft Graph session exists."
}

$records = @(Import-Csv $CsvPath)

foreach ($record in $records) {
    $currentStage = "Validation"

    try {
        if ($record.Action -ne "Leaver") {
            throw "Action must be Leaver."
        }

        $effectiveDate = [datetime]::ParseExact(
            $record.EffectiveDate,
            "yyyy-MM-dd",
            [Globalization.CultureInfo]::InvariantCulture
        )

        if ($effectiveDate.Date -gt (Get-Date).Date) {
            throw "The effective date is in the future."
        }

        $user = Get-MgUser `
            -UserId $record.UserPrincipalName `
            -Property Id,EmployeeId,DisplayName,AccountEnabled `
            -ErrorAction Stop

        if ($user.EmployeeId -ne $record.EmployeeId) {
            throw "EmployeeId does not match the Entra account."
        }

        $iamGroups = @(
            Get-MgGroup -All |
                Where-Object DisplayName -like "SG-IAM-*"
        )

        $assignedIamGroups = @()

        foreach ($group in $iamGroups) {
            $isMember = (
                Get-MgGroupMember -GroupId $group.Id -All
            ).Id -contains $user.Id

            if ($isMember) {
                $assignedIamGroups += $group
            }
        }

        if (-not $user.AccountEnabled -and $assignedIamGroups.Count -eq 0) {
            Write-Host "SKIPPED: Leaver state already applied." `
                -ForegroundColor Yellow

            Write-LeaverAudit `
                -EmployeeId $record.EmployeeId `
                -UserPrincipalName $record.UserPrincipalName `
                -Action "Leaver lifecycle change" `
                -Status "Skipped" `
                -Details "Account already disabled and IAM access already removed"

            continue
        }

        if ($user.AccountEnabled) {
            $currentStage = "Disable account"

            Update-MgUser `
                -UserId $user.Id `
                -AccountEnabled:$false `
                -ErrorAction Stop

            Write-Host "DISABLED: $($record.UserPrincipalName)" `
                -ForegroundColor Green
        }
        else {
            Write-Host "ALREADY DISABLED: $($record.UserPrincipalName)" `
                -ForegroundColor Yellow
        }

        $currentStage = "Revoke active sessions"

        Revoke-MgUserSignInSession `
            -UserId $user.Id `
            -ErrorAction Stop |
            Out-Null

        Write-Host "SESSIONS REVOKED" -ForegroundColor Green

        $removedGroups = @()

        foreach ($group in $assignedIamGroups) {
            $currentStage = "Remove access: $($group.DisplayName)"

            Remove-MgGroupMemberByRef `
                -GroupId $group.Id `
                -DirectoryObjectId $user.Id `
                -ErrorAction Stop

            $removedGroups += $group.DisplayName

            Write-Host "REMOVED: $($group.DisplayName)" `
                -ForegroundColor Green
        }

        $removedText = if ($removedGroups.Count -gt 0) {
            $removedGroups -join ", "
        }
        else {
            "No IAM group access remained"
        }

        Write-LeaverAudit `
            -EmployeeId $record.EmployeeId `
            -UserPrincipalName $record.UserPrincipalName `
            -Action "Leaver lifecycle change" `
            -Status "Success" `
            -Details "Account disabled; sessions revoked; removed: $removedText"

        Write-Host "LEAVER PROCESS COMPLETED" -ForegroundColor Green
    }
    catch {
        Write-LeaverAudit `
            -EmployeeId $record.EmployeeId `
            -UserPrincipalName $record.UserPrincipalName `
            -Action "Leaver lifecycle change" `
            -Status "Failed" `
            -Details "Stage: $currentStage; Error: $($_.Exception.Message)"

        Write-Host "FAILED during: $currentStage" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host "Review the account state before retrying." `
            -ForegroundColor Yellow
    }
}