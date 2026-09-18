param(
    [string]$CsvPath = "$PSScriptRoot\..\data\new-hires.csv",

    [string]$EmployeeId
)

function New-TemporaryPassword {
    $randomBytes = [Security.Cryptography.RandomNumberGenerator]::GetBytes(12)
    $randomText = [Convert]::ToBase64String($randomBytes)

    return "Aa1!$randomText"
}

function Write-AuditRecord {
    param(
        [string]$EmployeeId,
        [string]$UserPrincipalName,
        [string]$Action,
        [string]$Status,
        [string]$Details
    )

    $auditPath = "$PSScriptRoot\..\logs\joiner-audit.csv"

    [PSCustomObject]@{
        Timestamp         = (Get-Date).ToString("s")
        EmployeeId       = $EmployeeId
        UserPrincipalName = $UserPrincipalName
        Action            = $Action
        Status            = $Status
        Details           = $Details
    } | Export-Csv -Path $auditPath -Append -NoTypeInformation
}

# Stop if the HR data fails validation.
& "$PSScriptRoot\Test-JoinerInput.ps1" -CsvPath $CsvPath

if (-not (Get-MgContext).Account) {
    throw "No Microsoft Graph session exists. Run Connect-MgGraph first."
}

$departmentGroupMap = @{
    "Finance"                = "SG-IAM-Finance"
    "Human Resources"        = "SG-IAM-HumanResources"
    "Information Technology" = "SG-IAM-InformationTechnology"
}

$records = @(Import-Csv $CsvPath)

if ($EmployeeId) {
    $records = @(
        $records | Where-Object EmployeeId -eq $EmployeeId
    )

    if ($records.Count -eq 0) {
        throw "EmployeeId was not found in the CSV: $EmployeeId"
    }
}

$credentialPath = "$PSScriptRoot\..\data\temporary-credentials.xml"

$encryptedCredentials = if (Test-Path $credentialPath) {
    @(Import-Clixml -Path $credentialPath)
}
else {
    @()
}

$encryptedCredentials = @($encryptedCredentials)

foreach ($record in $records) {
    try {
        $targetGroupName = $departmentGroupMap[$record.Department]

        if (-not $targetGroupName) {
            throw "No access group is mapped to department: $($record.Department)"
        }

        $targetGroup = Get-MgGroup `
            -Filter "displayName eq '$targetGroupName'" `
            -ErrorAction Stop

        if (-not $targetGroup) {
            throw "Target group does not exist: $targetGroupName"
        }

        $existingUser = Get-MgUser `
            -Filter "userPrincipalName eq '$($record.UserPrincipalName)'" `
            -ErrorAction Stop

        if ($existingUser) {
            Write-Host "SKIPPED: $($record.UserPrincipalName) already exists." `
                -ForegroundColor Yellow

            Write-AuditRecord `
                -EmployeeId $record.EmployeeId `
                -UserPrincipalName $record.UserPrincipalName `
                -Action "Create user" `
                -Status "Skipped" `
                -Details "User already exists"

            continue
        }

        $temporaryPassword = New-TemporaryPassword

        $userBody = @{
            accountEnabled    = $true
            displayName       = $record.DisplayName
            givenName         = $record.FirstName
            surname           = $record.LastName
            userPrincipalName = $record.UserPrincipalName
            mailNickname      = ($record.UserPrincipalName.Split("@")[0])
            employeeId        = $record.EmployeeId
            department        = $record.Department
            jobTitle          = $record.JobTitle
            usageLocation     = $record.UsageLocation
            passwordProfile   = @{
                password                      = $temporaryPassword
                forceChangePasswordNextSignIn = $true
            }
        }

        $newUser = New-MgUser `
            -BodyParameter $userBody `
            -ErrorAction Stop

        New-MgGroupMember `
            -GroupId $targetGroup.Id `
            -DirectoryObjectId $newUser.Id `
            -ErrorAction Stop

        $encryptedCredentials += [PSCustomObject]@{
            EmployeeId       = $record.EmployeeId
            UserPrincipalName = $record.UserPrincipalName
            TemporaryPassword = ConvertTo-SecureString `
                $temporaryPassword -AsPlainText -Force
        }

        Write-AuditRecord `
            -EmployeeId $record.EmployeeId `
            -UserPrincipalName $record.UserPrincipalName `
            -Action "Create user and assign group" `
            -Status "Success" `
            -Details "Assigned to $targetGroupName"

        Write-Host "CREATED: $($record.UserPrincipalName)" `
            -ForegroundColor Green

        Write-Host "ASSIGNED: $targetGroupName" `
            -ForegroundColor Green
    }
    catch {
        Write-AuditRecord `
            -EmployeeId $record.EmployeeId `
            -UserPrincipalName $record.UserPrincipalName `
            -Action "Joiner provisioning" `
            -Status "Failed" `
            -Details $_.Exception.Message

        Write-Host "FAILED: $($record.UserPrincipalName)" `
            -ForegroundColor Red

        Write-Host $_.Exception.Message -ForegroundColor Red
    }
}

if ($encryptedCredentials.Count -gt 0) {
    $credentialPath = "$PSScriptRoot\..\data\temporary-credentials.xml"

    $encryptedCredentials |
        Export-Clixml -Path $credentialPath

    Write-Host "`nEncrypted credentials saved locally to:" `
        -ForegroundColor Cyan

    Write-Host $credentialPath
    Write-Host "Do not upload this file to GitHub." `
        -ForegroundColor Yellow
}