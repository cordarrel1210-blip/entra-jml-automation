$departmentGroups = @(
    @{
        DisplayName  = "SG-IAM-Finance"
        MailNickname = "sgiamfinance"
        Description  = "Role-based access group for Finance employees"
    },
    @{
        DisplayName  = "SG-IAM-HumanResources"
        MailNickname = "sgiamhumanresources"
        Description  = "Role-based access group for Human Resources employees"
    },
    @{
        DisplayName  = "SG-IAM-InformationTechnology"
        MailNickname = "sgiaminformationtechnology"
        Description  = "Role-based access group for Information Technology employees"
    }
)

foreach ($groupDefinition in $departmentGroups) {
    $displayName = $groupDefinition.DisplayName

    try {
        $existingGroup = Get-MgGroup `
            -Filter "displayName eq '$displayName'" `
            -ErrorAction Stop

        if ($existingGroup) {
            Write-Host "EXISTS: $displayName" -ForegroundColor Yellow
            continue
        }

        $newGroup = New-MgGroup `
            -DisplayName $displayName `
            -Description $groupDefinition.Description `
            -MailEnabled:$false `
            -MailNickname $groupDefinition.MailNickname `
            -SecurityEnabled:$true `
            -ErrorAction Stop

        Write-Host "CREATED: $($newGroup.DisplayName)" -ForegroundColor Green
    }
    catch {
        Write-Host "FAILED: $displayName" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
    }
}