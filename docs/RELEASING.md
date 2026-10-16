# Publishing MacVolvo 1.0

The source branch, intro page and draft release can be reviewed independently
of the final signed installer. App version: 1.0; signed candidate build: 6.
Runtime: macvolvo-1.0-signed.1.
The earlier unsigned candidate remains build 5 with phase2-20261014.1.

## Current release candidate

The app and `runtime/release/MacVolvo-1.0.dmg` are Developer ID signed,
Apple notarized, stapled and Gatekeeper-verified. The earlier unsigned ZIP is
retained as a historical build 5 artifact. See [SIGNING.md](SIGNING.md) for the
commands, submission IDs and installer checksum.

Runtime source identities and patches are in `SOURCES.json`. Before public
binary publication, finish the dependency source/license closure and full-runtime
rebuild described in `BUILDING.md`. Preserve required notices and make
corresponding dependency sources available.

## Signed public installer

Supply a Developer ID Application identity and a configured notarytool profile.
An Apple Development identity is not a substitute.

1. Build with `scripts/build_native_app.py --identity "Developer ID Application: …"`.
2. Submit the packaged app with `xcrun notarytool submit`, then staple and validate
   the app. Do not bypass failed signature or notarization checks.
3. Package with `scripts/build_release_dmg.py` using the same identity and
   notary profile. It checks the app's signature/staple and notarizes the DMG.
4. Upload `MacVolvo-1.0.dmg` and `MacVolvo-1.0.dmg.sha256` to the draft release.
5. Recheck install, Steam/game launch, return from a full match, and known issues.
   Replace the test-package instructions with final installation notes.
6. Publish the release. Keep `<!-- minimum-macos: 26.5 -->` in its body.

## GitHub intro site

`docs/index.html`, `docs/site.css` and `docs/.nojekyll` form a static site.
No package installs, external fonts, analytics or build dependencies.

Preview: `python3 -m http.server 8000 --directory docs`.

After merging the release PR, in repository Settings → Pages choose
**Deploy from a branch → main → /docs**. The site URL is
`https://haeli05.github.io/MacVolvo/`. Set the repository's About website to it.
Download buttons point to this repository's Releases page, not Recall's downloads.
Once a public release exists, update candidate wording on the site and README.

Reference: [GitHub Pages publishing sources](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site).

For exact certificate, Keychain profile, signing and notarization commands,
see [SIGNING.md](SIGNING.md). The initial Pages preview uses the release/v1.0
branch's /docs folder; switch its source to main after merging the release PR.
