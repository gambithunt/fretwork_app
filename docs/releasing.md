# Releasing Fretwork

How a change on `main` becomes an app on someone's Mac, and how to verify it
did.

Fretwork is distributed from [fretwork.org/mac](https://fretwork.org/mac) as a
signed but deliberately un-notarized disk image, and updates itself with
Sparkle. There is no Apple Developer Program account behind it, which shapes
almost every decision below.

## The mental model

One thing triggers everything: **pushing a tag beginning with `v`**. Nothing
else publishes — pushing to `main` runs no release.

```
git push origin v0.3.0
        │
        ▼
GitHub Actions (macos-26)  ──►  R2 bucket  ──►  downloads.fretwork.org
                                                      │
                                    ┌─────────────────┴──────────────────┐
                                    ▼                                    ▼
                          appcast.xml (Sparkle)              version.json (the website)
```

The website is **not** redeployed for a release. `fretwork.org/mac` fetches
`version.json` at runtime, so a new version appears there within five minutes
without the site repo being touched. If that fetch fails the page falls back
to `Fretwork-latest.dmg`, which the release repoints every time — so the
download works with JavaScript disabled and with the metadata unreachable.

## Cutting a release

The tag is only a trigger. **Every version string in the artifacts comes from
the built app's `Info.plist`**, never from the tag. So the bump comes first.

1. In `Fretlight.xcodeproj/project.pbxproj`, in *both* the Debug and Release
   configurations of the `Fretlight` target:
   - `MARKETING_VERSION` — `0.MINOR.PATCH`. MINOR for a feature workstream,
     PATCH for a bugfix-only one.
   - `CURRENT_PROJECT_VERSION` — plain integer, +1.
2. Add a `CHANGELOG.md` entry, newest on top, written from the root cause.
3. Commit, tag, push:

```bash
git add -A && git commit -m "..." && git tag v0.3.0 && git push origin main --tags
```

`CURRENT_PROJECT_VERSION` is the one that must always increase. It becomes
`CFBundleVersion`, which is the only value Sparkle compares to decide whether
an update exists; `generate_appcast` also keys its entries on it.
`MARKETING_VERSION` is display-only as far as Sparkle is concerned.

> **The footgun.** Tag `v0.3.0` without bumping the version and CI will
> happily build another `Fretwork-0.2.0.dmg`, overwrite the published one, and
> offer nobody anything. Nothing fails; it just silently does nothing.

## What the job does

`.github/workflows/release.yml`, on `macos-26`:

| Step | Why it exists |
| --- | --- |
| Select Xcode | Picks the newest installed. Release artifacts must come from the toolchain the app is developed and smoke-tested against — Xcode 16's SDK rejects an `AVAudioEngine` capture in `AudioEngine.swift` that Xcode 26's permits. |
| Import signing certificate | Decodes the `.p12` secret into a throwaway keychain. `set-key-partition-list` is what stops `codesign` blocking on a GUI prompt no one can answer headlessly. |
| Ensure the AWS CLI | R2 is driven through its S3-compatible API. |
| — | There is no package-resolution step. Sparkle is vendored, so a release needs no network beyond the R2 upload. |
| Fetch published releases | Syncs the bucket **down**. `generate_appcast` rewrites the feed from the directory it is given, so without the existing images every older version would drop out of the appcast. Excludes `Fretwork-latest.dmg`, which would otherwise be read as a duplicate release. |
| Build release | Runs `scripts/build-release.sh` — the same script you can run locally. |
| Publish disk images | Versioned filenames never change, so `immutable, max-age=1y`. |
| Point the stable alias | Server-side copy to `Fretwork-latest.dmg`. Needs `--metadata-directive REPLACE`, or the copy inherits the source's `immutable` header — the one header a mutable alias must never carry. |
| Publish appcast + version.json | Last, and cached for five minutes. Ordering is deliberate: nothing should announce a version before the file it points at is fetchable. |
| Purge the edge cache | For the three mutable files. |
| Attach to a GitHub release | So the tag has a downloadable asset too. |

## What `build-release.sh` does

```bash
./scripts/build-release.sh build
```

Archives universal Release → verifies the binary really is `x86_64 arm64` →
builds a dmg carrying an `/Applications` symlink → signs the archive with the
EdDSA key → writes `appcast.xml` and `version.json`.

It **fails the build if the designated requirement does not name the signing
certificate**. That requirement is what a user's microphone grant is pinned
to. Signed with the certificate it reads:

```
identifier "org.fretwork.app" and certificate root = H"059ced65..."
```

which is stable across rebuilds. An ad-hoc signature degrades it to a bare
per-build `cdhash`, and every existing install re-prompts for microphone
access on its next update. A silent fallback would look fine and quietly
break everyone, so it is an error rather than a warning.

The `/Applications` symlink is not decoration either: dragging the app out of
the image is what stops macOS running it translocated from a random read-only
path, which breaks self-update.

## Testing

**Locally — publishes nothing.** Exercises everything except the upload:

```bash
./scripts/build-release.sh /tmp/rel
```

**Verifying a release landed:**

```bash
curl -s https://downloads.fretwork.org/version.json
```

```bash
curl -sI https://downloads.fretwork.org/Fretwork-latest.dmg | grep -iE "^HTTP|cache-control"
```

```bash
curl -s https://downloads.fretwork.org/appcast.xml
```

**Verifying what a user actually gets** — download, mount, and check the
signature and architectures:

```bash
curl -sL -o /tmp/f.dmg https://downloads.fretwork.org/Fretwork-latest.dmg
hdiutil attach -quiet -nobrowse -mountpoint /tmp/fmnt /tmp/f.dmg
codesign --verify --deep --strict /tmp/fmnt/Fretwork.app && codesign -d -r- /tmp/fmnt/Fretwork.app
lipo -archs /tmp/fmnt/Fretwork.app/Contents/MacOS/Fretwork
hdiutil detach -quiet /tmp/fmnt
```

**Verifying Sparkle will accept the update** — the appcast's signature against
the published image. Silence means verified:

```bash
SIG=$(curl -s https://downloads.fretwork.org/appcast.xml | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
./Tools/sparkle/sign_update --verify /tmp/f.dmg "$SIG"
```

### There is no sandbox

Any `v*` tag publishes for real. Because `generate_appcast` derives the feed
from every image in the bucket, **a test release becomes a live update offer
to real users.** Undoing one means deleting the object from R2 and running
another release to regenerate the appcast.

If the publish path needs testing repeatedly, add a Sparkle **channel**:
`generate_appcast --channel beta` puts prerelease builds in a separate track
that only opted-in installs see. Worth doing before there are users.

## When it breaks

```bash
gh run list --repo gambithunt/fretwork_app --workflow=release.yml --limit 5
```

```bash
gh run view --repo gambithunt/fretwork_app --log-failed
```

A green run is not proof. Both failures during the initial setup were
instructive: the compile error was loud and obvious, but a wrong
`Cache-Control` on the stable alias passed CI happily and showed up only in
the response headers. Check the published artifacts, not the tick.

## The two keys

Neither is recoverable, neither is in this repo, and GitHub Actions secrets
are write-only — that copy is not a backup.

| Key | Where it lives | If lost |
| --- | --- | --- |
| **"Fretwork Code Signing" certificate** — self-signed, valid to 2046 | login keychain, My Certificates | A replacement changes the designated requirement: every user re-prompts for microphone access, and Sparkle rejects the update as improperly signed. They must reinstall by hand. |
| **Sparkle EdDSA private key** | login keychain, service `https://sparkle-project.org`, account `ed25519` | No further update can ever be offered. Every install is frozen at its current version. |

Exporting them for backup:

```bash
security export -k login.keychain-db -t identities -f pkcs12 -o ~/Desktop/fretwork-signing-backup.p12
```

```bash
./Tools/sparkle/generate_keys -x ~/Desktop/sparkle-private-key.txt
```

Store both in a password manager, then delete the files and empty the Trash.

## The third irreplaceable thing

The recorded note-sample masters in `SampleMasters/` are not a key, but they
are in the same category: losing them costs another session with the guitar,
the same interface, the same gain setting, and 138 verified takes — and the
new library will not quite match the old one, so a partial restore is worse
than none. They are git-ignored deliberately (roughly 120 MB of 24-bit audio),
which means nothing else is keeping a copy.

Back the folder up wherever the keys go. What ships in the app bundle is a
trimmed, converted derivative; it is not a substitute for the masters, because
the conversion is lossy in ways a re-record cannot reproduce.

## Infrastructure

- **R2 bucket** `fretwork-downloads`, custom domain `downloads.fretwork.org`
  (proxied, so the images are edge-cached; `.dmg` is a default-cacheable type,
  and the appcast and `version.json` deliberately are not).
- **CORS** allows `https://fretwork.org` so the site can read `version.json`.
  Without it the download still works, but no version number renders.

### CI secrets

| Name | What |
| --- | --- |
| `SIGNING_CERTIFICATE_P12` | base64 of the signing certificate exported as .p12 |
| `SIGNING_CERTIFICATE_PASSWORD` | that .p12's password |
| `KEYCHAIN_PASSWORD` | any throwaway value; scopes the runner's temp keychain |
| `SPARKLE_PRIVATE_KEY` | output of `generate_keys -x` |
| `R2_ACCESS_KEY_ID` / `R2_SECRET_ACCESS_KEY` | R2 token with Object Read & Write |
| `CLOUDFLARE_ACCOUNT_ID` | for the R2 S3 endpoint |
| `CLOUDFLARE_ZONE_ID`, `CLOUDFLARE_CACHE_PURGE_TOKEN` | to purge the mutable files at the edge |

Plus a repository **variable** `R2_BUCKET` naming the bucket.

## What users see

The app is signed but not notarized, so macOS blocks the first launch and the
user has to allow it once in System Settings → Privacy & Security. Sparkle
strips the quarantine attribute from updates it installs and, on macOS 14.4+,
pre-warms Gatekeeper with `gktool` — so this happens on **first install only**,
never on an update. [fretwork.org/mac](https://fretwork.org/mac) walks through
it, including the detail that the "Open Anyway" button disappears about an
hour after the blocked launch.

## Upgrading Sparkle

Sparkle is **vendored**, not resolved as a Swift package:
`Frameworks/Sparkle.xcframework` is linked and embedded directly, and its
signing tools live in `Tools/sparkle/`. This is deliberate. SPM's binary-target
cache repeatedly wedged itself — `already exists in file system` on the
artifact path, then a resolution that silently stopped with `"artifacts": []`
— and package resolution is not something a release should be able to fail on.
Builds are now hermetic and need no network.

To move to a new Sparkle version:

```bash
VERSION=2.9.7
curl -fsSL -o /tmp/sparkle.zip \
  "https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/Sparkle-for-Swift-Package-Manager.zip"
```

Check the download against the checksum Sparkle publishes in its own
`Package.swift` for that tag before trusting it:

```bash
shasum -a 256 /tmp/sparkle.zip
curl -fsSL "https://raw.githubusercontent.com/sparkle-project/Sparkle/$VERSION/Package.swift" | grep checksum
```

Then replace the framework and tools:

```bash
rm -rf /tmp/sparkle && mkdir /tmp/sparkle && (cd /tmp/sparkle && unzip -q /tmp/sparkle.zip)
rm -rf Frameworks/Sparkle.xcframework
ditto /tmp/sparkle/Sparkle.xcframework Frameworks/Sparkle.xcframework
rm -rf Frameworks/Sparkle.xcframework/macos-arm64_x86_64/dSYMs
/usr/libexec/PlistBuddy -c "Delete :AvailableLibraries:0:DebugSymbolsPath" Frameworks/Sparkle.xcframework/Info.plist
for t in generate_appcast sign_update generate_keys BinaryDelta; do ditto "/tmp/sparkle/bin/$t" "Tools/sparkle/$t"; done
```

Deleting `DebugSymbolsPath` is required: the dSYMs are 20MB of the 23MB
download and are not worth versioning, but Xcode fails the build with
`Missing path ... as defined by 'DebugSymbolsPath'` if the key still points at
a directory that is not there.
