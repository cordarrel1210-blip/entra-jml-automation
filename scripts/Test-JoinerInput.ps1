param(
    [string]$CsvPath = "$PSScriptRoot\..\data\new-hires.csv"
)

$requiredFields = @(
    "EmployeeId",
    "FirstName",
    "LastName",
    "DisplayName",
    "UserPrincipalName",
    "Department",
    "JobTitle",
    "UsageLocation",
    "Action"
)

if (-not (Test-Path $CsvPath)) {
    throw "CSV file not found: $CsvPath"
}

$records = @(Import-Csv $CsvPath)
$validationErrors = @()

if ($records.Count -eq 0) {
    $validationErrors += "The CSV contains no employee records."
}

foreach ($record in $records) {
    foreach ($field in $requiredFields) {
        if ([string]::IsNullOrWhiteSpace([string]$record.$field)) {
            $validationErrors += "$($record.EmployeeId): $field is empty."
        }
    }

    if ($record.EmployeeId -notmatch "^LAB\d{4}$") {
        $validationErrors += "$($record.EmployeeId): Invalid EmployeeId format."
    }

    if (
        $record.UserPrincipalName -notmatch
        "^[^@\s]+@contoso\.onmicrosoft\.com$"
    ) {
        $validationErrors += "$($record.EmployeeId): Invalid UPN."
    }
}

$duplicateIds = $records |
    Group-Object EmployeeId |
    Where-Object Count -gt 1

$duplicateUPNs = $records |
    Group-Object UserPrincipalName |
    Where-Object Count -gt 1

foreach ($duplicate in $duplicateIds) {
    $validationErrors += "Duplicate EmployeeId: $($duplicate.Name)"
}

foreach ($duplicate in $duplicateUPNs) {
    $validationErrors += "Duplicate UPN: $($duplicate.Name)"
}

if ($validationErrors.Count -gt 0) {
    Write-Host "`nINPUT VALIDATION FAILED" -ForegroundColor Red

    $validationErrors | ForEach-Object {
        Write-Host " - $_" -ForegroundColor Red
    }

    throw "Correct the input file before provisioning."
}

Write-Host "`nINPUT VALIDATION PASSED" -ForegroundColor Green
Write-Host "$($records.Count) employee records are ready for processing."