# Create-AppCertificate

A PowerShell utility that creates a self-signed certificate for unattended Microsoft Entra application authentication.

## What it does

- Prompts for an app name, certificate validity, and export folder.
- Creates an RSA 2048 / SHA-256 certificate in `Cert:\LocalMachine\My`.
- Marks the private key as non-exportable.
- Exports only the public `.cer` file.
- Displays the certificate thumbprint, expiration, and setup instructions.
- Warns about existing valid certificates with the same subject and prevents overwriting an existing export file.

## Requirements

- Windows with the `New-SelfSignedCertificate` and `Export-Certificate` cmdlets available.
- 64-bit Windows PowerShell, running as Administrator.

## Usage

Save the script as `Create-AppCertificate.ps1`, open PowerShell as Administrator, and run:

```powershell
.\Create-AppCertificate.ps1
```

Follow the prompts. Certificate validity defaults to **1 year** and accepts **1–10 years**; use a duration approved by your organization.

## After creation

1. Upload the public `.cer` to your existing Entra app registration under **Certificates & secrets → Certificates**.
2. Grant the automation run account **Read** access to the certificate’s private key using `certlm.msc`.
3. Configure your automation to use the new thumbprint and test under its run account.
4. Set a renewal reminder before expiration.

The script does **not** create an app registration, assign API permissions, upload the certificate, or update your automation configuration.

## Security and renewal

- Never commit private keys, PFX files, or sensitive configuration to source control.
- The private key remains on the computer where the script runs; copying the `.cer` elsewhere does not enable authentication.
- Rerunning creates a new certificate and thumbprint—it does not extend the existing certificate.
- During renewal, register and test the replacement before removing the old certificate.
- This is a self-signed certificate utility, not a complete production credential-management solution.

Test in a non-production environment before use.
