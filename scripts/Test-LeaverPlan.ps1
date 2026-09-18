param(
    [string]$CsvPath = "$PSScriptRoot\..\data\leaver-requests.csv"
)

if (-not (Test-Path $CsvPath)) {
    throw "Leaver input file was not found: $CsvPath"
}

if (-not (Get-MgContext).Account) {
    throw "No Microsoft Graph session exists."
}

$requiredFields = @(
    "EmployeeId",
    "UserPrincipalName",
    "EffectiveDate",
    "Reason",
    "Action"
)

$records = @(Import-Csv $CsvPath)
$planResults = @()

foreach ($record in $records) {
    try {
        foreach ($field in $requiredFields) {
            if ([string]::IsNullOrWhiteSpace([string]$record.$field)) {
                throw "Required field is empty: $field"
            }
        }

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
                $assignedIamGroups += $group.DisplayName
            }
        }

        if (-not $user.AccountEnabled -and $assignedIamGroups.Count -eq 0) {
            $status = "SKIP: Leaver state already applied"
        }
        elseif (-not $user.AccountEnabled) {
            $status = "BLOCKED: Account disabled but access remains"
        }
        else {
            $status = "READY: Disable, revoke sessions and remove access"
        }

        $planResults += [PSCustomObject]@{
            User              = $user.DisplayName
            AccountEnabled    = $user.AccountEnabled
            AccessToRemove    = $assignedIamGroups -join ", "
            EffectiveDate     = $record.EffectiveDate
            Status            = $status
        }
    }
    catch {
        $planResults += [PSCustomObject]@{
            User           = $record.UserPrincipalName
            AccountEnabled = "Unknown"
            AccessToRemove = "Unknown"
            EffectiveDate  = $record.EffectiveDate
            Status         = "BLOCKED: $($_.Exception.Message)"
        }
    }
}

Write-Host "`nLEAVER CHANGE PREVIEW" -ForegroundColor Cyan
$planResults | Format-List