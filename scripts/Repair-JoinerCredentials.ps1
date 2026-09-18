param(
    [string[]]$UserPrincipalName = @(
        "maya.brooks@contoso.onmicrosoft.com",
        "ethan.cole@contoso.onmicrosoft.com"
    )
)

function New-TemporaryPassword {
    $randomBytes = [Security.Cryptography.RandomNumberGenerator]::GetBytes(12)
    $randomText = [Convert]::ToBase64String($randomBytes)

    return "Aa1!$randomText"
}

$credentialPath = "$PSScriptRoot\..\data\temporary-credentials.xml"
$auditPath = "$PSScriptRoot\..\logs\joiner-audit.csv"

$encryptedCredentials = if (Test-Path $credentialPath) {
    @(Import-Clixml -Path $credentialPath)
}
else {
    @()
}

$encryptedCredentials = @($encryptedCredentials)

foreach ($upn in $UserPrincipalName) {
    $temporaryPassword = $null

    try {
        $user = Get-MgUser `
   	 -UserId $upn `
   	 -Property Id,EmployeeId,DisplayName,UserPrincipalName `
   	 -ErrorAction Stop

        $temporaryPassword = New-TemporaryPassword

        $passwordProfile = @{
            Password                      = $temporaryPassword
            ForceChangePasswordNextSignIn = $true
        }

        Update-MgUser `
            -UserId $user.Id `
            -PasswordProfile $passwordProfile `
            -ErrorAction Stop

        $encryptedCredentials = @(
            $encryptedCredentials |
                Where-Object UserPrincipalName -ne $upn
        )

        $encryptedCredentials += [PSCustomObject]@{
            EmployeeId        = $user.EmployeeId
            UserPrincipalName = $upn
            TemporaryPassword = ConvertTo-SecureString `
                $temporaryPassword -AsPlainText -Force
        }

        $encryptedCredentials |
            Export-Clixml -Path $credentialPath

        [PSCustomObject]@{
            Timestamp         = (Get-Date).ToString("s")
            EmployeeId        = $user.EmployeeId
            UserPrincipalName = $upn
            Action            = "Credential recovery"
            Status            = "Success"
            Details           = "Password reset and encrypted credential preserved"
        } | Export-Csv -Path $auditPath -Append -NoTypeInformation

        Write-Host "RECOVERED: $upn" -ForegroundColor Green
    }
    catch {
        [PSCustomObject]@{
            Timestamp         = (Get-Date).ToString("s")
            EmployeeId        = $user.EmployeeId
            UserPrincipalName = $upn
            Action            = "Credential recovery"
            Status            = "Failed"
            Details           = $_.Exception.Message
        } | Export-Csv -Path $auditPath -Append -NoTypeInformation

        Write-Host "FAILED: $upn" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
    }
    finally {
        $temporaryPassword = $null
        $passwordProfile = $null
    }
}