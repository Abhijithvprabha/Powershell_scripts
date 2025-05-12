# Script: Update Email Addresses and Azure UPNs for Entra-Synced Users

# Purpose:
# - Update primary SMTP (proxyAddresses) in Active Directory
# - Preserve existing email aliases
# - Update the mail attribute
# - Validate email uniqueness across AD and Exchange Online
# - Trigger Azure AD Connect delta sync (via remote server)
# - Update Azure UPN via Microsoft Graph

Import-Module ActiveDirectory

function IsValidEmail {
    param ($email)
    return $email -match '^[\w\.\-]+@[\w\-]+\.[a-zA-Z]{2,}$'
}

# Step 1: Connect to Exchange Online using certificate
$CertficateRepo = "C:\Path\To\certs.csv"  # Update with actual path
$currentUser = $env:USERNAME
$thumbprint = (Import-Csv -Path $CertficateRepo | Where-Object { $_.username -eq $currentUser }).Thumbprint

if (-not $thumbprint) {
    Write-Host "[!] Certificate thumbprint not found for user $currentUser." -ForegroundColor Red
    return
}

try {
    if (-not (Get-Module ExchangeOnlineManagement -ListAvailable)) {
        Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force
    }

    Import-Module ExchangeOnlineManagement -ErrorAction Stop
    Connect-ExchangeOnline -CertificateThumbprint $thumbprint `
        -AppId "<AppId-GUID>" `  # Replace with your App Registration ID
        -ShowBanner:$false `
        -Organization "<yourtenant>.onmicrosoft.com"  # Replace with your tenant
}
catch {
    Write-Host "`n[!] Failed to connect to Exchange Online using certificate authentication." -ForegroundColor Red
    return
}

# Step 2–4: Get samAccountName and validate
while ($true) {
    $empID = Read-Host "Enter the Employee ID (employeeID) of the user"

    $user = Get-ADUser -Filter { employeeID -eq $empID } -Properties Name, mail, employeeID, SamAccountName

    if (!$user) {
        Write-Host "No user found with Employee ID $empID. Try again." -ForegroundColor Red
        continue
    }

    $sam = $user.SamAccountName
    $oldEmailAddress = $user.mail

    Write-Host "Employee Name         : $($user.Name)"
    Write-Host "Employee ID           : $($user.employeeID)"
    Write-Host "samAccountName        : $($user.SamAccountName)"
    Write-Host "Current Primary Email : $($user.mail)"

    $confirm = Read-Host "Do you want to continue? (Y/N)"
    if ($confirm -ne 'Y') {
        Write-Host "Operation cancelled." -ForegroundColor Yellow
        Disconnect-ExchangeOnline -Confirm:$false
        return
    }

    $newEmail = Read-Host "Enter the new primary email address"

    if (-not (IsValidEmail $newEmail)) {
        Write-Host "Invalid email format. Exiting." -ForegroundColor Red
        Disconnect-ExchangeOnline -Confirm:$false
        return
    }

    $verifyEmail = Read-Host "Re-enter the new email to verify"
    if ($newEmail -ne $verifyEmail) {
        Write-Host "Emails do not match. Exiting." -ForegroundColor Red
        Disconnect-ExchangeOnline -Confirm:$false
        return
    }

    # Check in AD
    $emailInUse = Get-ADUser -Filter {
        (mail -eq $newEmail) -or (proxyAddresses -contains "SMTP:$newEmail") -or (proxyAddresses -contains "smtp:$newEmail")
    } -Properties mail, proxyAddresses | Where-Object { $_.SamAccountName -ne $sam }

    if ($emailInUse) {
        Write-Host "`n[!] Email '$newEmail' already in use by AD user ($($emailInUse.SamAccountName))." -ForegroundColor Red
        Disconnect-ExchangeOnline -Confirm:$false
        return
    }

    # Check in Exchange Online
    try {
        $mailboxCheck = Get-EXOMailbox -Filter "EmailAddresses -eq 'SMTP:$newEmail'" -ErrorAction SilentlyContinue
        if ($mailboxCheck) {
            Write-Host "`n[!] Email '$newEmail' already assigned to a mailbox in Exchange Online." -ForegroundColor Red
            Disconnect-ExchangeOnline -Confirm:$false
            return
        }
    }
    catch {
        Write-Host "`n[!] Could not validate email against Exchange Online." -ForegroundColor Yellow
        Disconnect-ExchangeOnline -Confirm:$false
        return
    }

    Write-Host "Email format and uniqueness verified. Proceeding with update..."
    break
}

# Step 5: Update proxyAddresses and mail in AD
$user = Get-ADUser -Identity $sam -Properties proxyAddresses, mail
$currentProxies = $user.proxyAddresses
$oldPrimary = $currentProxies | Where-Object { $_ -cmatch '^SMTP:' }
$aliasesOnly = $currentProxies | Where-Object { $_ -cmatch '^smtp:' }

$newPrimaryProxy = "SMTP:$newEmail"
$oldPrimaryAlias = $oldPrimary -replace '^SMTP:', 'smtp:'
$updatedProxies = $newPrimaryProxy + $oldPrimaryAlias + $aliasesOnly

Set-ADUser -Identity $sam -Replace @{
    proxyAddresses = $updatedProxies
    mail = $newEmail
}

Write-Host "`nActive Directory attributes updated successfully."

# Step 6: Trigger Azure AD Connect sync
try {
    Write-Host "`nTriggering Azure AD Connect Delta Sync on sync server..."
    Invoke-Command -ComputerName <SyncServerName> -ScriptBlock {
        Import-Module ADSync
        Start-ADSyncSyncCycle -PolicyType Delta
    }
    Write-Host "Azure AD sync triggered successfully." -ForegroundColor Green
    Start-Sleep -Seconds 30
}
catch {
    Write-Host "[!] Could not trigger Azure AD sync. Run it manually if needed." -ForegroundColor Yellow
}

# Step 6.5: Update Azure UPN using Microsoft Graph
if (-not (Get-Module Microsoft.Graph.Users -ListAvailable)) {
    Install-Module Microsoft.Graph -Scope CurrentUser -Force
}
Import-Module Microsoft.Graph.Users
Connect-MgGraph -Scopes "User.ReadWrite.All"

Write-Host "... updating the UPN in Azure to match the new email address" -ForegroundColor White

try {
    $azureUser = Get-MgUser -Filter "userPrincipalName eq '$oldEmailAddress'" -ErrorAction Stop
    Update-MgUser -UserId $azureUser.Id -UserPrincipalName $newEmail
    Write-Host "Azure UPN successfully updated to $newEmail" -ForegroundColor Green
}
catch {
    Write-Host "   [!] ERROR updating the UPN in Azure. The error was: $($_.Exception.Message)" -ForegroundColor Red
}

# Step 7: Display updated user info
$user = Get-ADUser -Identity $sam -Properties GivenName, Surname, mail, proxyAddresses, employeeID

Write-Host ""
Write-Host "Updated Information:" -ForegroundColor Cyan
Write-Host "---------------------------------------------------------"
Write-Host ("{0,-15} {1,-15} {2,-35}" -f "First Name", "Last Name", "Email Address")
Write-Host ("{0,-15} {1,-15} {2,-35}" -f $user.GivenName, $user.Surname, $user.mail)
Write-Host ""
Write-Host "Employee ID     : $($user.employeeID)"
Write-Host ""
Write-Host "Proxy Addresses :"
$user.proxyAddresses | ForEach-Object { Write-Host "  $_" }
Write-Host "---------------------------------------------------------"

# Cleanup Sessions
Disconnect-ExchangeOnline -Confirm:$false
Disconnect-MgGraph
