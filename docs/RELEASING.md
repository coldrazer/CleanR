# Releasing CleanR (signed & notarized)

Releases are built, **signed with our Developer ID**, and **notarized by Apple**
automatically by `.github/workflows/release.yml` whenever `VERSION` changes on
`main`. No certificates, keys, or passwords are ever committed to the repo. They
live only as encrypted GitHub Actions secrets, are imported into an ephemeral
keychain at build time, and that keychain is deleted when the job finishes.

## Required GitHub Actions secrets

Add these under **Settings → Secrets and variables → Actions → New repository
secret**.

| Secret | What it is | How to get it |
|--------|-----------|---------------|
| `APPLE_DEVELOPER_ID` | The signing identity string | Exactly `Developer ID Application: Iliya Mirzaei (H3XLS95QV4)` |
| `DEVID_CERT_P12_BASE64` | Your Developer ID Application cert + private key, base64-encoded | See "Exporting the certificate" below |
| `DEVID_CERT_PASSWORD` | The password you set when exporting the `.p12` | You choose it during export |
| `KEYCHAIN_PASSWORD` | Throwaway password for the ephemeral CI keychain | Any random string |
| `ASC_KEY_ID` | App Store Connect API key ID | App Store Connect → Users and Access → Integrations → Keys |
| `ASC_ISSUER_ID` | App Store Connect issuer ID | Same Keys page (shown above the table) |
| `ASC_KEY_P8_BASE64` | The `.p8` API key file, base64-encoded | `base64 -i AuthKey_XXXX.p8 \| pbcopy` |
| `TAP_PUSH_TOKEN` | PAT that can push to `coldrazer/homebrew-cleanr` | GitHub → Settings → Developer settings → Fine-grained token, Contents: write on the tap repo |

## Exporting the certificate

1. Open **Keychain Access**, find `Developer ID Application: Iliya Mirzaei (H3XLS95QV4)`
   under **login → My Certificates** (it must show the disclosure triangle with a
   private key under it).
2. Right-click it → **Export** → save as `devid.p12`, set an export password
   (this becomes `DEVID_CERT_PASSWORD`).
3. Base64-encode it for the secret:
   ```bash
   base64 -i devid.p12 | pbcopy   # paste into DEVID_CERT_P12_BASE64
   ```

## Creating the App Store Connect API key (notarization auth)

1. App Store Connect → **Users and Access → Integrations → Keys** → **+**.
2. Give it the **Developer** role (sufficient for notarization), download the
   `AuthKey_XXXX.p8` (you can only download it once).
3. Note the **Key ID** (`ASC_KEY_ID`) and **Issuer ID** (`ASC_ISSUER_ID`).
4. Base64-encode the key:
   ```bash
   base64 -i AuthKey_XXXX.p8 | pbcopy   # paste into ASC_KEY_P8_BASE64
   ```

## What the pipeline does

1. Imports the Developer ID cert into an ephemeral, job-scoped keychain.
2. Stores notarytool credentials (API key) in that same keychain.
3. Runs `scripts/build-dmg.sh --notarize`, which signs with hardened runtime,
   notarizes the **app** (stapled) and the **DMG** (stapled), and verifies.
4. Publishes the GitHub release and updates the Homebrew cask in
   `coldrazer/homebrew-cleanr` with the new version and the DMG's SHA-256.
5. Deletes the ephemeral keychain (runs even if earlier steps fail).

## Building a notarized DMG locally

```bash
export APPLE_DEVELOPER_ID="Developer ID Application: Iliya Mirzaei (H3XLS95QV4)"
xcrun notarytool store-credentials "CleanR" \
  --apple-id "YOUR_APPLE_ID" --team-id "H3XLS95QV4" --password "APP_SPECIFIC_PASSWORD"
export NOTARY_PROFILE="CleanR"
bash scripts/build-dmg.sh --notarize
```
