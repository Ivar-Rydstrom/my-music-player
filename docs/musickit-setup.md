# Connect Hummery to Apple Music

This guide covers the optional independent MusicKit backend. Music.app playback is now the default real-library integration and needs no developer enrollment. See README.md for local setup.

## Current prerequisite

The Mac used for this prototype has no valid Apple code-signing identity, and the developer has not enrolled in the Apple Developer Program. The app integration can be built and tested with sample data, but the real account connection has not run.

## 1. Enroll and add the account to Xcode

Enroll as an individual through [Apple Developer Program enrollment](https://developer.apple.com/programs/enroll/), unless you intend to use an existing organization's developer team. Complete Apple's identity verification and membership activation on Apple's site or in its Developer app.

Once membership is active:

1. Open Xcode > Settings > Accounts.
2. Add your developer Apple Account and select the active developer team.
3. Under Manage Certificates, create an **Apple Development** certificate if one does not exist. Let Xcode create and keep its private key locally.
4. Note the team ID from your developer account's membership details. The ID is not a secret.

The Apple Music subscription used for listening is the Mac's Media & Purchases account. Developer membership enables app integration; it does not provide a music subscription. End users of a properly configured app do not each need developer memberships.

## 2. Register the App ID and enable MusicKit

In [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list):

1. Select Identifiers, then register a new **App ID**.
2. Use an explicit bundle identifier you control, such as `com.yourdomain.Hummery`. Do not use the checked-in `com.example.Hummery` placeholder.
3. In the **App Services** tab, enable **MusicKit** and save the registration.

MusicKit is a server-side App Service. There is no MusicKit signing capability or MusicKit-specific entitlement to add to the app. Do not add `com.apple.developer.music-user-token` or `com.apple.developer.musickit` to an entitlements file. Do not look for these in a provisioning profile.

References: [Apple's MusicKit account steps](https://developer.apple.com/help/account/services/musickit/), [automatic token generation](https://developer.apple.com/documentation/musickit/using-automatic-token-generation-for-apple-music-api), and [Apple DTS on entitlements and App Services](https://developer.apple.com/forums/thread/799000).

## 3. Set local signing identifiers

Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and replace the two identifiers. Alternatively:

```sh
python3 scripts/configure-signing.py \
  --team-id YOURTEAMID \
  --bundle-id com.yourdomain.Hummery
```

Replace those example values. `Local.xcconfig` is ignored by git, overrides `Signing.xcconfig`, and survives project regeneration. No `.p8` key, pasted token, server, or password in the source tree is needed for this native setup.

Open `Hummery.xcodeproj`. In the target's Signing & Capabilities tab, confirm automatic signing, the correct team, and the registered bundle ID. Leave App Sandbox and outgoing network access enabled. The existing Info.plist supplies the Apple Music usage description and app version.

Run with Command-R. Xcode may prompt for keychain access to use the signing key. If automatic signing reports a problem, resolve the account/certificate issue in Xcode rather than bypassing signing.

## 4. Connect from Hummery

1. Ensure Music is signed into the intended Media & Purchases account. Enable Sync Library for cloud playlists.
2. Click the sample-library status at the bottom of Hummery's sidebar.
3. Confirm the bundle ID and signing team in Account & integration. The connection button is disabled until the build identity checks pass.
4. Click **Connect Apple Music** and allow the macOS music permission prompt.

The app then verifies an authenticated storefront request, checks subscription and cloud-library availability, loads all playlist pages, and opens the selected playlist. Merely granting macOS permission is not reported as a successful account connection.

After a successful connection, subsequent launches reconnect only when music permission remains authorized and the build passes setup checks. **Use sample library** turns this off. It does not revoke macOS permission; revoke that in System Settings if desired.

## 5. Validate playback and sync

Use a disposable playlist and the [integration checklist](integration-checklist.md). Start with playing one song, then verify a favorite and a playlist addition on the iPhone. Playback never requires Music.app to stay open.

## Troubleshooting

| Where it stops | What to check |
| --- | --- |
| Build setup | Run the Xcode app bundle with your own registered bundle ID and Apple signing certificate. An unsigned or ad hoc sample build is insufficient for this setup. |
| Music permission | Enable Hummery in System Settings > Privacy & Security > Media & Apple Music. Restricted permission can come from Screen Time or device policy. |
| Verifying Apple Music access | Confirm the exact bundle ID, developer team, MusicKit App Service registration, network connection, and Media & Purchases sign-in. Permission alone doesn't prove token generation works. |
| Checking subscription | Confirm the listening account has an active subscription. A service failure isn't automatically evidence that the subscription expired. |
| Loading playlists | Check Sync Library, retry, and inspect the failed stage and error domain/code in the session log. An empty library is different from a failed request. |

The connection panel does not display or export developer tokens, music user tokens, or private keys. Apple issues and manages tokens through MusicKit.
