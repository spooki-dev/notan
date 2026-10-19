---
title: Code Signing
description: What it takes to stop macOS and Windows calling the build an unknown developer — Apple Developer ID and notarization, Windows Authenticode — and the environment variables scripts/release.sh reads once you have the certificates.
order: 9
---

Builds are ad-hoc signed today, which is enough to run them on the machine that made them and nothing more. Everywhere else the operating system treats them as coming from nobody in particular. This page is the research: what each platform actually checks, what it costs to satisfy it, and the hooks already in `scripts/release.sh` waiting for the credentials.

Nothing here is set up yet. The script builds and releases exactly as before until the variables in [Wiring it up](#wiring-it-up) are set.

## What a person sees now

**macOS.** The `.app` is quarantined on download, Gatekeeper finds no Developer ID signature and no notarization ticket, and the first launch is refused: *"Notan" cannot be opened because Apple cannot check it for malicious software.* Since macOS Sequoia the old Control-click → **Open** escape hatch is gone; the only route is System Settings → Privacy & Security → **Open Anyway**, and that button appears for roughly an hour after the blocked launch before it has to be re-triggered. It is several steps, it is phrased as a malware warning, and most people stop there.

**Windows.** The exe is unsigned, so Microsoft Defender SmartScreen shows *Windows protected your PC* with the publisher listed as **Unknown publisher**. Running it means clicking **More info** and then **Run anyway**.

Both are reputation systems, and both are answered by signing with an identity a platform vendor has verified.

## macOS: Developer ID and notarization

Three separate things, in order, and all three are required:

1. **Enrol in the Apple Developer Program.** $99 a year for individuals and organizations alike. An organization enrolment also needs a D-U-N-S number and takes longer; an individual enrolment is the quicker path and puts a personal legal name on the certificate. A free Apple ID cannot issue the certificate below.
2. **Issue a *Developer ID Application* certificate.** This is the one for distributing outside the Mac App Store. Xcode can create it, or the Certificates page of the developer portal. It lands in the login keychain; `security find-identity -v -p codesigning` prints it, and the full string, `Developer ID Application: Name (TEAMID)`, is what `codesign` wants.
3. **Notarize.** Apple scans the signed build, and a Mac then has to see a ticket for it. Notarization is free once enrolled, usually takes a few minutes, and says nothing about the app being good — only that it is cleanly signed and carries no known malware.

### The LuaJIT problem

Notarization requires the **hardened runtime** (`codesign --options runtime`), and the hardened runtime blocks writing memory and then executing it. That is exactly what LuaJIT does on desktop LÖVE: it compiles Lua to machine code at runtime. A signed, notarized build without the right entitlements launches, runs for a while, then dies the moment a hot path gets compiled — a crash that cannot be reproduced in an unsigned local build.

`scripts/macos-entitlements.plist` is in the repo for this, and `release.sh` passes it when signing:

```xml
<key>com.apple.security.cs.allow-jit</key><true/>
<key>com.apple.security.cs.allow-unsigned-executable-memory</key><true/>
```

If the app ever loads a dylib that Apple did not sign, `com.apple.security.cs.disable-library-validation` goes in too.

### Signing inside out

`codesign --deep` is deprecated and does not apply entitlements to nested code, so `sign_macos_app` in `release.sh` signs every `.dylib`, `.so` and `.framework` inside the bundle first and the bundle itself last. It then runs `codesign --verify --strict`, which fails the release rather than shipping a bundle that will be rejected.

### Credentials for notarytool

`notarytool` replaced `altool`. Store the credentials once, under a profile name:

```sh
xcrun notarytool store-credentials "notan-notary" \
  --apple-id you@example.com --team-id TEAMID --password <app-specific-password>
```

The password is an app-specific password from appleid.apple.com, not the Apple ID password. An App Store Connect API key (issuer ID, key ID and a `.p8`) works too and is the better choice for CI, because it is revocable on its own.

### Stapling

The ticket is attached to the **bundle**, not to a zip, so the archive has to be rebuilt around the stapled `.app` afterwards; `release.sh` does that. (A `.dmg` can be stapled directly.) Stapling is what makes the first launch work on a machine that is offline — without it, Gatekeeper has to reach Apple to check.

### In CI

Export the certificate as a `.p12`, base64 it into a repository secret, and at the start of the job import it into a throwaway keychain rather than the default one:

```sh
security create-keychain -p "$KEYCHAIN_PASSWORD" build.keychain
security default-keychain -s build.keychain
security unlock-keychain -p "$KEYCHAIN_PASSWORD" build.keychain
security import cert.p12 -k build.keychain -P "$P12_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" build.keychain
```

That last line is the one everybody forgets; without it `codesign` blocks on a GUI prompt that never appears.

## Windows: Authenticode

One certificate, but the ground moved recently and the old advice is wrong.

### You cannot keep the key in a file any more

Since the CA/Browser Forum tightened its Baseline Requirements, the private key for a publicly trusted code signing certificate has to live on hardware meeting FIPS 140-2 Level 2 or Common Criteria EAL4+ — a USB token, an HSM, or a CA's cloud signing service. A `.pfx` sitting in a repository secret is no longer an option for a new certificate. Certificates are also capped at about 15 months (459 days) rather than the three years they used to run.

That rules out the simple `signtool -f cert.pfx` recipe most older guides give, and it is the main thing that makes Windows signing awkward from a Mac and awkward in CI.

### EV no longer buys instant reputation

The reason indie developers used to pay the EV premium was an immediate SmartScreen pass. Microsoft removed that distinction: EV and OV certificates now build SmartScreen reputation the same way, through download volume over time. So a new signed build can still raise a SmartScreen warning for a while — but it says the publisher's name instead of *Unknown publisher*, and the warning goes away as downloads accumulate. **There is no longer a reason to buy EV for this project.**

### The options worth considering

| Route | Rough cost | Notes |
|---|---|---|
| **Azure Artifact Signing** (was Trusted Signing) | ~$10/month basic tier | Cloud signing on Microsoft's own FIPS 140-2 Level 3 infrastructure, no token to own or lose. Individual developers are eligible. Identity validation up front, and some tenants need an Entra licence to assign the signing role, which has caught people out. |
| **Certum Open Source Code Signing** | ~$60–100/year | Aimed at open source projects; their SimplySign cloud service drives `signtool` without a USB token. The long-standing cheap option for indie projects. |
| **Standard OV from Sectigo / DigiCert / SSL.com** | ~$200–400/year | Comes with a hardware token, or their cloud HSM at extra cost. |
| **EV** | ~$400+/year | No longer worth it here, per above. |

### What to sign, and when

Every exe that ships: the game exe, and the installer if there is one. Order matters twice over:

- The `.love` is **appended** to `love.exe` to make the game exe. Sign after that, never before — anything added to a PE after signing falls outside the signature and invalidates it.
- An installer must be built from already-signed files and then signed itself, or the files it lays down on disk are unsigned.

Tooling is `signtool.exe` from the Windows SDK, or `osslsigncode` (`brew install osslsigncode`) cross-platform — though with a hardware-backed key you generally end up using whatever client the CA or cloud service provides. Because that differs per vendor, `release.sh` does not try to know it; it calls a hook, described below.

## The `.love`

Nothing to do. It is not executable on its own; whoever runs it already has LÖVE installed and has already made that decision.

## Wiring it up

`scripts/release.sh` reads three environment variables. Each is empty by default and an empty one skips its step, so the script behaves exactly as it does today until they are set.

| Variable | Example | Effect |
|---|---|---|
| `MACOS_SIGN_IDENTITY` | `Developer ID Application: George Butter (AB12CD34EF)` | Signs the bundle inside out with the hardened runtime and `scripts/macos-entitlements.plist`, then verifies it. Unset, the app is ad-hoc signed as before. |
| `MACOS_NOTARY_PROFILE` | `notan-notary` | Submits the archive with `notarytool --wait`, staples the ticket to the `.app` and rebuilds the archive around it. Requires `MACOS_SIGN_IDENTITY`; the script stops if it is set without one, because Apple will not notarize an ad-hoc build. |
| `WINDOWS_SIGN_HOOK` | `scripts/sign-windows.sh` | An executable taking one argument, a file to sign in place. Called on each `<PKG>.exe` after the `.love` is appended. |

A release with everything set:

```sh
export MACOS_SIGN_IDENTITY="Developer ID Application: George Butter (AB12CD34EF)"
export MACOS_NOTARY_PROFILE="notan-notary"
export WINDOWS_SIGN_HOOK="scripts/sign-windows.sh"
VERSION=0.2.0 scripts/release.sh
```

The script prints what it did at the end, so an unsigned release is never a silent one:

```
Signing: macOS Developer ID, notarized; Windows signed via scripts/sign-windows.sh.
```

A hook is a few lines. With Azure Artifact Signing, roughly:

```sh
#!/usr/bin/env bash
# scripts/sign-windows.sh — signs one file in place. Not in the repo; it holds
# nothing secret, but it is specific to whichever certificate you end up with.
set -euo pipefail
azuresigntool sign \
  --azure-key-vault-url "$AZURE_VAULT_URL" \
  --azure-key-vault-client-id "$AZURE_CLIENT_ID" \
  --azure-key-vault-tenant-id "$AZURE_TENANT_ID" \
  --azure-key-vault-client-secret "$AZURE_CLIENT_SECRET" \
  --azure-key-vault-certificate "$AZURE_CERT_NAME" \
  --timestamp-rfc3161 http://timestamp.acs.microsoft.com \
  --file-digest sha256 \
  "$1"
```

Always timestamp. Without a timestamp the signature expires with the certificate, and every copy already downloaded stops verifying.

## What it comes to

| | Up front | Per year |
|---|---|---|
| macOS, Developer ID + notarization | enrolment, a day or two | $99 |
| Windows, Authenticode | identity validation, a few days | ~$60–400 depending on route |

Roughly $160–200 a year to stop both platforms warning people off. If only one is worth doing first it is **macOS**, because Gatekeeper's refusal is a hard block that needs a trip into System Settings, while SmartScreen is one extra click and improves by itself as downloads accumulate.

Until then the release notes link to install instructions, and the Windows side avoids compounding the problem: nothing in the build asks for administrator rights, because an elevation prompt naming an unknown publisher is a second thing to talk people past.
