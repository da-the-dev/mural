# Releasing Mural (signing & notarization)

You can ship **unsigned** DMGs right now — the release workflow builds and uploads
them with no configuration. When you want macOS to stop warning users ("unidentified
developer"), set up a **Developer ID** and the secrets below; the workflow signs and
notarizes automatically once they exist.

## 0. Prerequisites

- An **Apple Developer Program** membership (US$99/yr). Free accounts cannot create
  *Developer ID* certificates or notarize.
- Enroll at <https://developer.apple.com/programs/>; approval can take a day or two.

## 1. Create a "Developer ID Application" certificate

Easiest via Xcode:

1. Xcode → **Settings → Accounts** → sign in with your Apple ID.
2. Select your team → **Manage Certificates…** → **＋** → **Developer ID Application**.
3. In **Keychain Access**, find the new certificate under *My Certificates*, expand it
   (it has a private key), select **both**, right-click → **Export…**, save as
   `Cert.p12` with a password. Keep that password — it becomes
   `MACOS_CERTIFICATE_PASSWORD`.

Get your signing identity string:

```sh
security find-identity -v -p codesigning
# "Developer ID Application: Your Name (ABCDE12345)"
```

That whole quoted string is `MACOS_SIGNING_IDENTITY`; `ABCDE12345` is your
`APPLE_TEAM_ID`.

## 2. Create an app-specific password (for notarization)

1. Go to <https://appleid.apple.com> → **Sign-In & Security → App-Specific Passwords**.
2. Generate one (e.g. "mural-ci"). That's `APPLE_APP_PASSWORD` (looks like `abcd-efgh-ijkl-mnop`).
3. `APPLE_ID` is your Apple ID email.

> Prefer an API key? You can use an **App Store Connect API key** with
> `xcrun notarytool submit --key AuthKey_XXXX.p8 --key-id XXXX --issuer XXXX` instead
> of `--apple-id/--password/--team-id`. Swap the notarize step if you like.

## 3. Base64 the certificate

```sh
base64 -i Cert.p12 | pbcopy     # macOS
# Linux: base64 -w0 Cert.p12
```

## 4. Add the repo secrets

Via the GitHub UI (Settings → Secrets and variables → Actions), or the CLI:

```sh
gh secret set MACOS_CERTIFICATE          < <(base64 -i Cert.p12)
gh secret set MACOS_CERTIFICATE_PASSWORD --body 'your-p12-password'
gh secret set MACOS_SIGNING_IDENTITY     --body 'Developer ID Application: Your Name (ABCDE12345)'
gh secret set KEYCHAIN_PASSWORD          --body "$(openssl rand -hex 16)"
gh secret set APPLE_ID                   --body 'you@example.com'
gh secret set APPLE_APP_PASSWORD         --body 'abcd-efgh-ijkl-mnop'
gh secret set APPLE_TEAM_ID              --body 'ABCDE12345'
```

## 5. Release

```sh
git tag v0.1.0
git push origin v0.1.0
```

Watch the **Release** workflow: it builds, signs (hardened runtime), packages the
DMG, notarizes it (`notarytool … --wait`), staples the ticket, and publishes the
GitHub Release. When the secrets above are present it does all of that; when they
aren't, it publishes an unsigned DMG with a warning.

## Verifying locally

```sh
codesign --verify --deep --strict --verbose=2 Mural.app
spctl -a -vv Mural.app          # "accepted, source=Notarized Developer ID"
xcrun stapler validate Mural-0.1.0.dmg
```
