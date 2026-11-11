# Creates a self-signed certificate for unattended Entra app authentication.
# Run once in 64-bit Windows PowerShell as Administrator on the automation server.
# Prompts for settings; no configuration edits are required.
# This script creates a certificate, NOT an Entra app registration.
# The private key stays in LocalMachine\My; only the public .cer is exported.

$ErrorActionPreference = 'Stop'

# Confirm the script is elevated.
$CurrentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$Principal = [Security.Principal.WindowsPrincipal]::new($CurrentIdentity)
$IsAdministrator = $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdministrator) {
    throw 'Run this script from PowerShell as Administrator.'
}

# Prompt for the app name and derive all certificate names from it.
do {
    $AppName = (Read-Host 'App name (for example, Intune-Automation)').Trim()
    $ValidAppName = (
        $AppName.Length -ge 1 -and $AppName.Length -le 100 -and
        $AppName -match '^[\p{L}\p{N}][\p{L}\p{N} ._()-]*$' -and
        -not $AppName.EndsWith('.') -and
        $AppName -notmatch '^(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(?:\.|$)'
    )
    if (-not $ValidAppName) {
        Write-Warning 'Enter 1-100 characters, starting with a letter or number. Use letters, numbers, spaces, dots, hyphens, underscores or parentheses; no trailing dot or reserved Windows filename.'
    }
} until ($ValidAppName)

$CertificateSubject = "CN=$AppName"
$PublicCertificateFileName = "$AppName.cer"

# Press Enter to keep the original one-year validity.
do {
    $ValidityInput = (Read-Host 'Certificate validity in years (1-10) [1]').Trim()
    $ValidityYears = 1
    $ValidYears = [string]::IsNullOrWhiteSpace($ValidityInput)
    if (-not $ValidYears) {
        $ValidYears = [int]::TryParse($ValidityInput, [ref]$ValidityYears)
        $ValidYears = $ValidYears -and $ValidityYears -ge 1 -and $ValidityYears -le 10
    }
    if (-not $ValidYears) {
        Write-Warning 'Enter a whole number from 1 to 10, or press Enter for 1.'
    }
} until ($ValidYears)

$ExportFolder = (Read-Host 'Public certificate export folder [C:\temp]').Trim()
if ([string]::IsNullOrWhiteSpace($ExportFolder)) {
    $ExportFolder = 'C:\temp'
}
if (-not [System.IO.Path]::IsPathRooted($ExportFolder)) {
    throw 'Enter an absolute Windows folder path, such as C:\temp, then run the script again.'
}
if (-not (Test-Path -LiteralPath $ExportFolder)) {
    New-Item -ItemType Directory -Path $ExportFolder -Force | Out-Null
}
$ExportDirectory = Get-Item -LiteralPath $ExportFolder
if (-not $ExportDirectory.PSIsContainer -or $ExportDirectory.PSProvider.Name -ne 'FileSystem') {
    throw 'The export location must be a filesystem folder.'
}
$ExportFolder = $ExportDirectory.FullName

$PublicCertificatePath = Join-Path $ExportFolder $PublicCertificateFileName
if (Test-Path -LiteralPath $PublicCertificatePath) {
    throw "The export file already exists: $PublicCertificatePath. Rename or remove it before continuing."
}

# Warn if a currently valid certificate already uses the same subject.
$ExistingCertificates = @(Get-ChildItem Cert:\LocalMachine\My | Where-Object {
    $_.Subject -eq $CertificateSubject -and $_.NotAfter -gt (Get-Date)
})
if ($ExistingCertificates.Count -gt 0) {
    Write-Warning "A valid certificate already exists with subject '$CertificateSubject':"
    $ExistingCertificates | Select-Object Subject, Thumbprint, NotAfter | Format-Table -AutoSize
    $Confirmation = Read-Host 'Create another certificate with the same subject? Type YES to continue'
    if ($Confirmation -cne 'YES') {
        Write-Host 'Certificate creation canceled.' -ForegroundColor Yellow
        return
    }
}

Write-Host "Creating certificate in Cert:\LocalMachine\My..." -ForegroundColor Cyan
$Certificate = New-SelfSignedCertificate `
    -Subject $CertificateSubject `
    -CertStoreLocation 'Cert:\LocalMachine\My' `
    -KeyAlgorithm RSA `
    -KeyLength 2048 `
    -HashAlgorithm SHA256 `
    -KeySpec Signature `
    -KeyExportPolicy NonExportable `
    -KeyUsage DigitalSignature `
    -NotAfter (Get-Date).AddYears($ValidityYears) `
    -FriendlyName $AppName

if (-not $Certificate -or -not $Certificate.HasPrivateKey) {
    throw 'Certificate creation failed or the certificate has no private key.'
}

Export-Certificate `
    -Cert $Certificate `
    -FilePath $PublicCertificatePath `
    -NoClobber `
    -Type CERT | Out-Null

$Verification = Get-Item -LiteralPath "Cert:\LocalMachine\My\$($Certificate.Thumbprint)"

Write-Host "`nCertificate created successfully." -ForegroundColor Green
[pscustomobject]@{
    Subject               = $Verification.Subject
    AppName               = $AppName
    Thumbprint            = $Verification.Thumbprint
    ValidFrom             = $Verification.NotBefore
    Expires               = $Verification.NotAfter
    HasPrivateKey         = $Verification.HasPrivateKey
    CertificateStore      = 'Cert:\LocalMachine\My'
    PublicCertificatePath = $PublicCertificatePath
} | Format-List

Write-Host 'NEXT STEPS' -ForegroundColor Cyan
Write-Host "1. In Entra admin center, open App registrations > $AppName > Certificates & secrets > Certificates."
Write-Host "2. Upload the public certificate: $PublicCertificatePath"
Write-Host '3. Do NOT export or upload a PFX/private key.'
Write-Host '4. Configure your automation scripts to use the certificate thumbprint below:'
Write-Host "   `$CertificateThumbprint = '$($Verification.Thumbprint)'" -ForegroundColor Yellow
Write-Host '5. Grant the scheduled-task account Read access to the private key:'
Write-Host '   certlm.msc > Personal > Certificates > certificate > All Tasks > Manage Private Keys.'
Write-Host '6. Test automation scripts that use certificate-based authentication under the account that will run them; use a dry-run mode if supported.'
Write-Host "7. Set a renewal reminder before $($Verification.NotAfter.ToString('yyyy-MM-dd'))."
