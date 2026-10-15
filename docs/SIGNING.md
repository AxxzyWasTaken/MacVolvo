# Sign and launch MacVolvo 1.0

## Launch the local build now

From the repository root:

```sh
open runtime/build/release/MacVolvo.app
```

That path contains version 1.0, build 5. Old v0.x app bundles were removed.
The source-built copy remains at `runtime/build/v1.0/MacVolvo.app`. The local
build does not require a Developer ID certificate to be built or launched on
this development Mac. This is distinct from distributing a notarized download.

## Get the public-distribution certificate

1. Use an Apple Developer Program membership with permission to create Developer
   ID certificates. In Xcode → Settings → Accounts, select your team, open Manage
   Certificates, and create **Developer ID Application**. Alternatively, use
   Certificates, Identifiers & Profiles in your Apple Developer account.
2. Install the certificate and its matching private key in this Mac's login
   keychain. Check it locally:

   ```sh
   security find-identity -v -p codesigning
   ```

   The result must include `Developer ID Application: Your Name (TEAMID)`.
   The existing **Apple Development** certificate is not suitable for notarizing
   a public app download. Do not share the private key or credentials in chat/git.
3. Save notarization credentials in Keychain using the interactive prompts:

   ```sh
   xcrun notarytool store-credentials macvolvo-notary
   ```

   Use your Apple ID, team ID and app-specific password, or the supported App
   Store Connect API-key option. The profile name is used by the commands below.

Apple references: [Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/)
and [notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## Sign the runtime, then the launcher

The current runtime includes a locally ad-hoc-signed repair. Signing only the
outer app does not sign executables inside its embedded runtime archive.
Complete the source/dependency steps in [BUILDING.md](BUILDING.md), including
corresponding-source and license review, before public binary distribution.

Once the source-build outputs exist, assemble a new signed runtime:

```sh
export MACVOLVO_SIGN_ID='Developer ID Application: Your Name (TEAMID)'
python3 scripts/assemble_portable_runtime.py --workspace runtime/phase-2 \
  --version macvolvo-1.0-signed.1 --identity "$MACVOLVO_SIGN_ID"
```

This produces `runtime/phase-2/artifacts/macvolvo-1.0-signed.1.tar.gz` and its
manifest/proof. Update `runtimeVersion` and `runtimeSHA256` in
`app/Resources/release.json` to that archive's version and SHA-256. Keep the
archive filename field `runtime.tar.gz`; the app builder uses that embedded name.
Then build to a fresh output folder:

```sh
python3 scripts/build_native_app.py --output runtime/build/v1.0-signed/MacVolvo.app \
  --runtime-archive runtime/phase-2/artifacts/macvolvo-1.0-signed.1.tar.gz \
  --identity "$MACVOLVO_SIGN_ID"
codesign --verify --deep --strict runtime/build/v1.0-signed/MacVolvo.app
```

## Notarize and package

```sh
mkdir -p runtime/release
ditto -c -k --sequesterRsrc --keepParent runtime/build/v1.0-signed/MacVolvo.app \
  runtime/release/MacVolvo-1.0-notary.zip
xcrun notarytool submit runtime/release/MacVolvo-1.0-notary.zip \
  --keychain-profile macvolvo-notary --wait
```

Proceed only after the submission says **Accepted**. For a rejection, use
`xcrun notarytool log SUBMISSION_ID --keychain-profile macvolvo-notary` and fix the
reported issues; do not disable signature checks.

```sh
xcrun stapler staple runtime/build/v1.0-signed/MacVolvo.app
xcrun stapler validate runtime/build/v1.0-signed/MacVolvo.app
spctl --assess --type execute --verbose=2 runtime/build/v1.0-signed/MacVolvo.app
python3 scripts/build_release_dmg.py --app runtime/build/v1.0-signed/MacVolvo.app \
  --output runtime/release/MacVolvo-1.0.dmg --identity "$MACVOLVO_SIGN_ID" \
  --notary-profile macvolvo-notary --plain
```

`--plain` avoids the optional dmgbuild dependency. Omit it after installing
`dmgbuild==1.6.5` if you want the styled Finder window. The script signs,
notarizes and staples the DMG, then writes its SHA-256 file. Upload those two
files to the existing v1.0 draft release, test on another Mac, update the
release notes' signing status and publish when ready. Launch the signed app with:

```sh
open runtime/build/v1.0-signed/MacVolvo.app
```
