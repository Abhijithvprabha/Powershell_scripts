# Update Email and UPN for Entra-Synced Users

This PowerShell script is designed to assist system administrators in updating the primary email address (SMTP), mail attribute, and Azure User Principal Name (UPN) for users synchronized from on-prem Active Directory to Entra ID (Azure AD).

## ✅ Features

- Validates email format and ensures uniqueness in both Active Directory and Exchange Online.
- Updates:
  - `proxyAddresses` with new primary SMTP
  - `mail` attribute in AD
  - Azure UPN using Microsoft Graph
- Preserves existing email aliases.
- Triggers Azure AD Connect delta sync on a specified remote sync server.
- Connects to Exchange Online using certificate-based authentication.

## 🔧 Requirements

- PowerShell 5.1 or later
- AD PowerShell Module
- ExchangeOnlineManagement module
- Microsoft.Graph module (`User.ReadWrite.All` permission)
- Remote access to the Azure AD Connect sync server
- Certificate-based authentication for Exchange Online

## 🔄 Workflow

1. Connects to Exchange Online using a certificate.
2. Prompts for the user’s `employeeID`.
3. Validates and verifies new email.
4. Ensures the new email is not in use.
5. Updates AD attributes.
6. Triggers a delta sync via remote command.
7. Updates the user's Azure UPN via Microsoft Graph.
8. Displays updated user attributes.

## 📝 Configuration Notes

Update these placeholders in the script before use:

- `<AppId-GUID>` — your Azure App Registration ID.
- `<yourtenant>.onmicrosoft.com` — your tenant domain.
- `<SyncServerName>` — name of the Azure AD Connect server.
- `C:\Path\To\certs.csv` — path to your certificate thumbprint mapping file.

## ⚠️ Disclaimer

Use this script at your own risk. Always test in a development environment before deploying to production.

---

## 📁 Example Output


Employee Name : John Doe
Employee ID : 123456
samAccountName : jdoe
Current Primary Email : john.doe@oldcompany.com

Updated Information:
First Name Last Name Email Address
John Doe john.doe@newdomain.com

Employee ID : 123456

Proxy Addresses :
SMTP:john.doe@newdomain.com
smtp:john.doe@oldcompany.com
smtp:j.doe@newdomain.com

