# Distributing Stick Pad

Three routes, in increasing order of effort:

| Route | Cost | What the user sees |
| --- | --- | --- |
| Unsigned `.dmg` / `.pkg` | free | Gatekeeper blocks it; they must right-click ▸ Open |
| Signed + notarised `.dmg` | $99/yr | Opens normally, like any downloaded app |
| Mac App Store | $99/yr | Installs from the App Store |

`./build.sh --dist` produces the first one today. The other two need an Apple
Developer Program membership, and the App Store additionally needs real code
changes — see [Part 3](#part-3-mac-app-store).

---

## Part 1 — Building the disk image and installer

```bash
./build.sh --dmg     # build/Stick Pad 1.0.dmg
./build.sh --pkg     # build/Stick Pad 1.0.pkg
./build.sh --dist    # both
```

**The `.dmg`** is the normal way to ship a Mac app outside the App Store. It
opens to a window holding `Stick Pad.app` and a symlink to `/Applications`, so
the user drags one onto the other. Compressed (UDZO), about 1 MB.

**The `.pkg`** is a double-click installer that puts the app straight into
`/Applications`. Prefer the `.dmg` for a plain app like this — a `.pkg` runs an
installer with admin rights, which is more than a sticky-note app needs and
makes some people (rightly) suspicious. The `.pkg` matters mainly for managed
Mac fleets, where admins deploy via MDM.

### The Gatekeeper problem

These are **ad-hoc signed**, meaning signed with no identity. macOS will refuse
to open the app from a download with *"Apple could not verify Stick Pad is free
of malware."* The workaround is right-click ▸ **Open**, then **Open** again.

That's fine for you. It is not fine for anyone else — it trains people to bypass
a security warning. If you want to hand this to other people, sign and notarise.

## Part 2 — Signing and notarising for direct distribution

Needs the $99/year Apple Developer Program. One-time setup:

1. Create a **Developer ID Application** certificate in Xcode ▸ Settings ▸
   Accounts ▸ Manage Certificates, or on developer.apple.com.
2. Create an **app-specific password** at appleid.apple.com (Sign-In & Security
   ▸ App-Specific Passwords). This is *not* your Apple ID password.
3. Store it for `notarytool`:

```bash
xcrun notarytool store-credentials "stickpad" --apple-id "you@example.com" --team-id "YOURTEAMID" --password "abcd-efgh-ijkl-mnop"
```

Then for each release:

```bash
codesign --force --options runtime --timestamp --sign "Developer ID Application: Your Name (YOURTEAMID)" "build/Stick Pad.app"
```

```bash
./build.sh --dmg && xcrun notarytool submit "build/Stick Pad 1.0.dmg" --keychain-profile "stickpad" --wait
```

```bash
xcrun stapler staple "build/Stick Pad 1.0.dmg"
```

`--options runtime` enables the Hardened Runtime, which notarisation requires.
Stapling writes the notarisation ticket into the file so it validates offline.

Verify before you send it anywhere:

```bash
spctl --assess --type open --context context:primary-signature -vv "build/Stick Pad 1.0.dmg"
```

You want `source=Notarized Developer ID`. Note that notarisation is **not** App
Review — it is an automated malware scan, usually finished in minutes.

---

## Part 3 — Mac App Store

### Stick Pad cannot be submitted as it stands

**The App Sandbox is mandatory for the Mac App Store**, and Stick Pad is not
sandboxed. This is the one item on this page that is a code change rather than a
command to run. Everything else is paperwork.

Sandboxing this app is not difficult — it never touches the network, and it only
reads files the user explicitly picks — but it has one consequence worth
understanding before you start:

> **Sandboxing moves where notes are stored.** `~/Library/Application
> Support/StickPad/` becomes `~/Library/Containers/<bundle id>/Data/Library/
> Application Support/StickPad/`. A sandboxed build will not see notes written
> by the current build. If you have notes you care about, save an encrypted
> backup first (**Security ▸ Save Encrypted Backup…**), or write a one-time
> migration that copies the old folder in on first launch.

`Packaging/StickPad.entitlements` in this repo is ready to use. It grants the
sandbox, user-selected file access for the open/save panels and drag-and-drop,
and a keychain access group for the AES key. Replace `com.example.stickpad` with
your own bundle identifier. It deliberately does **not** request network access —
Stick Pad has no network code, and asking for it on an app whose pitch is
"nothing is uploaded anywhere" invites questions in review.

### Prerequisites

1. **Apple Developer Program**, $99/year — developer.apple.com/programs.
2. **Xcode** installed and selected:
   ```bash
   sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
   ```
3. **A bundle identifier you own.** The current `com.stickpad.app` is a
   placeholder — use reverse-DNS of a domain you control, e.g.
   `com.hegdekarthik.stickpad`. Register it under Certificates, Identifiers &
   Profiles ▸ Identifiers.

### An Xcode project

Swift Package Manager alone cannot produce a signed, provisioned App Store
archive. Create a thin Xcode app target that wraps the existing code — the
package is already split into a `StickPadKit` library precisely so this is easy:

1. Xcode ▸ File ▸ New ▸ Project ▸ macOS ▸ App. Name it `StickPad`, uncheck
   tests, interface **AppKit**, language Swift.
2. Delete the generated `AppDelegate`/`main`.
3. File ▸ Add Package Dependencies ▸ Add Local, and choose this repo. Link
   `StickPadKit` to the app target.
4. Replace the app's entry point with the same three lines as
   `Sources/StickPad/Main.swift`:
   ```swift
   import StickPadKit

   @main
   @MainActor
   struct StickPadMain {
       static func main() { StickPadApp.run() }
   }
   ```
5. Signing & Capabilities ▸ **+ Capability ▸ App Sandbox**, then set the file
   access to *User Selected File* → **Read/Write**.
6. Drop `Tools/makeicon.swift` output into an asset catalog, or point
   `CFBundleIconFile` at `AppIcon.icns` as `build.sh` does.

### App Store Connect

At appstoreconnect.apple.com ▸ Apps ▸ **+** ▸ New App, then fill in:

- **Screenshots** — at least one, 1280×800 or 1440×900. Grab them with `⇧⌘4`
  or reuse `docs/note.png`.
- **Description, keywords, support URL.** Your GitHub repo works as the support
  URL.
- **Privacy policy URL** — required for every app, even one that collects
  nothing. A short page saying Stick Pad stores notes only on the user's Mac,
  encrypted, and transmits nothing is enough.
- **App Privacy** — answer **Data Not Collected**. That is accurate: there is no
  network code.
- **Export compliance.** Stick Pad uses AES-256-GCM, so you *will* be asked.
  Because the encryption comes entirely from Apple's CryptoKit and protects only
  the user's own local data, it normally falls under the exemption for
  encryption provided by the operating system — but confirm this yourself
  against Apple's current export-compliance questionnaire rather than taking my
  word for it, and be aware some jurisdictions (France, notably) want a separate
  declaration. Once settled you can record the answer in `Info.plist` as
  `ITSAppUsesNonExemptEncryption` so you are not asked on every upload.

### Upload

With the Xcode project, this is the whole thing:

**Product ▸ Archive**, then in the Organizer, **Distribute App ▸ App Store
Connect ▸ Upload.** Xcode handles the Apple Distribution certificate, the
provisioning profile, the installer package and the upload.

`CFBundleVersion` must increase on every upload, even for the same
`CFBundleShortVersionString`.

If you would rather not use the Organizer, sign and package by hand and upload
with the free **Transporter** app from the Mac App Store:

```bash
codesign --force --options runtime --timestamp --entitlements Packaging/StickPad.entitlements --sign "Apple Distribution: Your Name (YOURTEAMID)" "build/Stick Pad.app"
```

```bash
productbuild --component "build/Stick Pad.app" /Applications --sign "3rd Party Mac Developer Installer: Your Name (YOURTEAMID)" "build/StickPad-appstore.pkg"
```

The app bundle also needs the Mac App Store provisioning profile copied to
`Contents/embedded.provisionprofile` before signing. This route is fiddlier than
the Organizer and easy to get subtly wrong; use it only if you have a reason to.

### Things likely to come up in review

- **Sandbox.** The rejection reason if you forget it.
- **"Export Encryption Key…"** shows a raw key in an alert. That is a reasonable
  feature for an E2EE app, but expect a reviewer to look at it. The alert
  already explains what the key is and warns how to store it.
- **A floating, always-on-top window** is fine, but reviewers test that notes
  can be dismissed and that the app is usable without them. `⌘W`, the menu bar
  item and **All Notes** all cover this.
- **Sample content.** Ship with no notes, or one obviously-sample note. Do not
  ship with test data.

### Honest expectation

The App Store route is mostly waiting: $99 and a day or two for the account,
an afternoon to sandbox and wrap the app in an Xcode project, then 24–48 hours
for review. If your goal is just to give the app to a handful of people, **Part 2
(signed and notarised `.dmg`) gets you there for the same $99 and none of the
sandboxing work.**
