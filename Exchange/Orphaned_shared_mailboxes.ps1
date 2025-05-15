<#
.SYNOPSIS
    Identifies orphaned shared mailboxes in Exchange Online with no delegations or permissions.

.DESCRIPTION
    This PowerShell script connects to Exchange Online using certificate-based authentication.
    It scans all shared mailboxes in the tenant and identifies orphaned ones—defined as shared
    mailboxes that have no assigned FullAccess, SendAs, or SendOnBehalf permissions.

.NOTES
    Author: Your Name
    Created: Date
    Version: 1.0

.INPUTS
    - CSV file containing thumbprints mapped to usernames

.OUTPUTS
    - Console output of orphaned shared mailboxes (if any)
    - CSV report file

.EXAMPLE
    .\orphaned_shared_mailboxes.ps1
#>

# Path to the CSV file storing certificate thumbprints per user
$CertificateRepo = "C:\Path\To\certs.csv"  # <-- Replace with actual path

# Get the current Windows username
$currentUser = $env:USERNAME

# Read the thumbprint from the CSV for the current user
$thumbprint = (Import-Csv -Path $CertificateRepo | Where-Object { $_.username -eq $currentUser }).Thumbprint

if (-not $thumbprint) {
    Write-Warning "No thumbprint found for user '$currentUser' in the CSV."
    return
}

# Attempt connection using certificate-based authentication
try {
    Connect-ExchangeOnline -CertificateThumbprint $thumbprint `
        -AppId "<YOUR-APP-ID>" `                         # <-- Replace with your App ID
        -Organization "<yourtenant>.onmicrosoft.com" `   # <-- Replace with your tenant
        -ShowBanner:$false

    Write-Host "Connected to Exchange Online using certificate for $currentUser`n"
}
catch {
    Write-Warning "Failed to connect to Exchange Online: $_"
    return
}

# Get all shared mailboxes
Write-Host "Gathering shared mailboxes..."
$sharedMailboxes = Get-Mailbox -RecipientTypeDetails SharedMailbox -ResultSize Unlimited

$orphanedMailboxes = @()

foreach ($mailbox in $sharedMailboxes) {
    Write-Host "Checking mailbox: $($mailbox.DisplayName)"
    $hasDelegation = $false

    # Check Full Access permissions (excluding system/self)
    $fullAccess = Get-MailboxPermission -Identity $mailbox.Identity -ErrorAction SilentlyContinue | Where-Object {
        $_.User.ToString() -notlike "NT AUTHORITY*" -and $_.User -notlike "S-1-5-*" -and $_.User -ne "SELF" -and $_.AccessRights -contains "FullAccess"
    }

    # Check SendAs permissions
    $sendAs = Get-RecipientPermission -Identity $mailbox.Identity -ErrorAction SilentlyContinue | Where-Object {
        $_.Trustee -notlike "NT AUTHORITY*" -and $_.Trustee -notlike "S-1-5-*" -and $_.Trustee -ne "SELF"
    }

    # Check SendOnBehalf
    $sendOnBehalf = $mailbox.GrantSendOnBehalfTo
    $hasSendOnBehalf = $sendOnBehalf -and $sendOnBehalf.Count -gt 0

    if ($fullAccess -or $sendAs -or $hasSendOnBehalf) {
        $hasDelegation = $true
    }

    if (-not $hasDelegation) {
        $orphanedMailboxes += [PSCustomObject]@{
            DisplayName     = $mailbox.DisplayName
            PrimarySMTP     = $mailbox.PrimarySmtpAddress
            Identity        = $mailbox.Identity
        }
    }
}

# Output results
if ($orphanedMailboxes.Count -eq 0) {
    Write-Host "No orphaned shared mailboxes found."
} else {
    Write-Host "Found $($orphanedMailboxes.Count) orphaned shared mailboxes:"
    $orphanedMailboxes | Format-Table

    # Export to CSV
    $outputPath = "C:\Path\To\OrphanedSharedMailboxes.csv"  # <-- Replace with desired path
    $orphanedMailboxes | Export-Csv -Path $outputPath -NoTypeInformation
    Write-Host "Exported to $outputPath"
}

# Disconnect session
Disconnect-ExchangeOnline -Confirm:$false
