<#
.SYNOPSIS
    Creates a new shared mailbox in a hybrid Active Directory and Exchange Online environment.

.DESCRIPTION
    This script automates the process of creating a shared mailbox by:
    - Creating the account in on-premises Active Directory
    - Syncing it to Microsoft 365 (Azure AD/Exchange Online)
    - Converting it to a shared mailbox
    - Assigning Full Access and Send As permissions
    - Removing licenses and disabling the account after provisioning

.INPUTS
    User input for shared mailbox details (EmpID, Display Name, Email, etc.)

.OUTPUTS
    New shared mailbox credentials (email and temporary password)

.NOTES
    Version:        1.0
    Author:         <Your Name>
    Creation Date:  <Date>
    Requirements:   ActiveDirectory & ExchangeOnlineManagement modules, ADConnect
#>

#-----------------------------------------------------------[Modules & Connection]-----------------------------------------------------------

Import-Module ActiveDirectory

$certificateRepoPath = "C:\Path\To\certs.csv"
$currentUser = $env:USERNAME
$thumbprint = (Import-Csv -Path $certificateRepoPath | Where-Object { $_.username -eq $currentUser }).Thumbprint

if ($thumbprint) {
    Connect-ExchangeOnline -CertificateThumbprint $thumbprint -AppId "<Your-App-ID>" -Organization "<Your-Tenant>.onmicrosoft.com" -ShowBanner:$false
}

#-----------------------------------------------------------[Configuration]-----------------------------------------------------------

$fullAccessListPath = "C:\Path\To\FullAccess_Accounts.txt"
$sendAsListPath = "C:\Path\To\SendAs_Accounts.txt"
$ouPath = "OU=Shared,OU=Mailboxes,OU=YourOrgUnit,DC=domain,DC=com"
$syncServer = "Your-ADConnect-Server"
$groupsToAdd = @("<Temporary-License-Group>", "<Compliance-Policy-Group>")

$FullAccess = Get-Content -Path $fullAccessListPath
$SendAs = Get-Content -Path $sendAsListPath

#-----------------------------------------------------------[User Input]-----------------------------------------------------------

$employeeID = Read-Host "Enter the EmpID of the mailbox owner"
if (-not $employeeID) { Write-Host "EmpID is required." -ForegroundColor Red; return }

$existingUser = Get-ADUser -Filter { employeeID -like $employeeID } -ErrorAction SilentlyContinue
if (-not $existingUser) { Write-Host "Invalid EmpID." -ForegroundColor Red; return }

$employeeID += "-MBX"
$description = Read-Host "Enter description for the shared mailbox"
if (-not $description) { Write-Host "Description is required." -ForegroundColor Red; return }

$account = Read-Host "Enter SamAccountName (max 20 chars)"
if (-not $account -or (Get-ADUser -Filter { SamAccountName -eq $account })) {
    Write-Host "SamAccountName is invalid or already in use." -ForegroundColor Red; return
}

$displayName = Read-Host "Enter display name"
if (-not $displayName) { Write-Host "Display name is required." -ForegroundColor Red; return }

$email = Read-Host "Enter email address"
if (-not $email -or (Get-EXORecipient -Identity $email -ErrorAction SilentlyContinue)) {
    Write-Host "Email is invalid or already in use." -ForegroundColor Red; return
}

#-----------------------------------------------------------[Confirmation]-----------------------------------------------------------

Write-Host "\nPlease review the information below:" -ForegroundColor Cyan
Write-Host "Name: $displayName\nEmail: $email\nDescription: $description\nSamAccountName: $account\nEmpID: $employeeID"

$confirmation = Read-Host "Is the above information correct? (Y/N)"
if ($confirmation -notin @("Y", "y")) {
    Disconnect-ExchangeOnline -Confirm:$false
    Write-Host "Exiting..." -ForegroundColor Red
    return
}

#-----------------------------------------------------------[Account Creation & Sync]-----------------------------------------------------------

$password = -join ((65..90)+(97..122)+(48..57) | Get-Random -Count 16 | ForEach-Object { [char]$_ })
$newUser = New-ADUser -SamAccountName $account -UserPrincipalName $email -Name $displayName -GivenName $displayName -Description $description -EmployeeID $employeeID -OtherAttributes @{proxyAddresses = "SMTP:$email"} -EmailAddress $email -Path $ouPath -AccountPassword (ConvertTo-SecureString $password -AsPlainText -Force) -Enabled $true -PassThru

Write-Host "\nMailbox created. Email: $email | Password: $password" -ForegroundColor Yellow

foreach ($group in $groupsToAdd) {
    Add-ADGroupMember -Identity $group -Members $account
}

Start-Sleep -Seconds 30

# Trigger sync loop until mailbox appears in Exchange Online
Do {
    Invoke-Command -ComputerName $syncServer -ScriptBlock { Start-ADSyncSyncCycle -PolicyType Delta }
    Start-Sleep -Seconds 300
    $mailboxProvisioned = Get-Mailbox -Identity $email -ErrorAction SilentlyContinue
} Until ($mailboxProvisioned)

#-----------------------------------------------------------[Post-Provisioning Configuration]-----------------------------------------------------------

Set-Mailbox -Identity $email -Type Shared
Start-Sleep -Seconds 30

foreach ($user in $FullAccess) {
    Add-MailboxPermission -Identity $email -User $user -AccessRights FullAccess -InheritanceType All
}

foreach ($user in $SendAs) {
    Add-RecipientPermission -Identity $email -AccessRights SendAs -Trustee $user -Confirm:$false
}

foreach ($group in $groupsToAdd) {
    Remove-ADGroupMember -Identity $group -Members $account -Confirm:$false
}

Disable-ADAccount -Identity $account
Invoke-Command -ComputerName $syncServer -ScriptBlock { Start-ADSyncSyncCycle -PolicyType Delta }

Write-Host "\nShared mailbox setup complete!" -ForegroundColor Green

#-----------------------------------------------------------[Cleanup]-----------------------------------------------------------

Disconnect-ExchangeOnline -Confirm:$false
