# Still

A native macOS music player built around playlists. SwiftUI renders the interface, and Music.app handles real playback and account sync through macOS automation. No paid developer membership is needed for this local setup. The independent MusicKit implementation is retained as an optional backend for later.

Requires macOS 14 or later. No third-party dependencies.

## Run locally and connect Music

Open `StillPlayer.xcodeproj` in Xcode, select the StillPlayer scheme, and run. The project defaults to local ad hoc signing. Or build and launch from the terminal:

```sh
zsh scripts/run-local.sh
```

Open **Settings** with Command-comma or the sidebar button, select **Connection**, then **Connect Music.app**. Allow Still to control Music when macOS prompts. Music must be signed into the account whose playlists you want to use. Enable Sync Library in Music for account changes to reach your other devices. Connecting only reads data and does not start playback.

To open the connection panel and attempt the read-only connection on launch, use `zsh scripts/run-local.sh --connect-music`. Close an older running build first so macOS launches the updated executable. Once a connection succeeds, it restores on later launches; **Use sample library** disables restoration and leaves Music's playback alone.

The app has an Apple Events usage description, hardened-runtime Apple Events access, and sandbox scripting-target permissions scoped to Music's library and playback groups. It also includes an Apple-events sandbox exception limited to `com.apple.Music`: Music can reject playlist reads with privilege error -10004 despite the advertised scripting groups. The app remains sandboxed. It does not request Accessibility access or automate mouse clicks. If you decline permission, enable it in **System Settings > Privacy & Security > Automation**, then reconnect. Local rebuilds can cause macOS to ask again because an ad hoc signature changes with the executable.

Or run `swift run StillPlayer` for the sample interface. That executable is not a configured app bundle and intentionally rejects account connections.

Sample playback is simulated, with no audio files or streaming. The timer, seek, skip, queue edits, repeat, favorites, and sample playlist additions are interactive. Sample playlist additions reset when switching modes or restarting. Pins, sample favorites, last selected playlist, queue visibility, and appearance persist locally. Recently played contains up to 100 unique songs from the current session and can be cleared. It resets when changing library connections.

## Interface

- Playlists in the sidebar, with local pinning through the context menu and a playlist-name filter.
- Song table with sortable columns, multiple selection, filtering, and track context menus.
- Double-click a song to play it in Music, retaining its source playlist context. Music controls the subsequent playback order. Filtering or sorting Still's table does not reorder Music's playlist or Up Next. Single-click only selects.
- Right-click tracks to favorite/unfavorite in Music or add to an editable playlist. Smart, subscription, and special playlists are excluded as addition targets. Additions can affect your real library; use a test playlist first.
- Search with Command-K. Music.app mode searches your library. Catalog search stays in Music, accessible with the Open Music button. Sample mode uses fixtures; the optional MusicKit mode searches the library or catalog and returns up to 25 songs.
- Space toggles playback when a text field isn't consuming the key. Command-P also toggles playback. Command-Left/Right skips songs, Command-R refreshes the library, and Command-Shift-U toggles the queue where supported.
- The queue panel and toggle are hidden for Music.app playback because its actual Up Next queue is not scriptable. Queue insertion, movement, removal, and clearing remain available in sample and MusicKit modes. See [the capability investigation](docs/ui-polish.md).
- A moon menu sets a 15, 30, 45, or 60 minute sleep timer. Playback pauses at the deadline. The timer continues with the main window closed while Still is running, and changing connections cancels it. Quitting Still cancels the timer.
- Settings has six appearance presets and a custom theme editor. Drag across the color field, adjust color depth, and choose light or dark to generate companion colors automatically. Turn off Automatic palette for native color pickers and exact hex values. Changes apply live across windows and save on this Mac.
- Music.app mode has a real Music volume slider. Playback position, current track, shuffle, repeat, volume, and favorite state are polled from Music. Closing Still or switching to samples does not stop Music.

Search opens separately, keeping the underlying playlist view intact. Playlist filter text and selections survive navigation during a session. Exact table scroll restoration and persistent column configuration are deferred.

Music.app metadata uses generated placeholder artwork for now. Library playlist reads use bulk Apple events rather than a network API. Playlist names, song metadata, and logs are not uploaded by Still. Music itself handles streaming and cloud sync.

## Optional independent MusicKit player

This backend is retained for a future migration. It is not required for Music.app mode. Follow the [MusicKit setup guide](docs/musickit-setup.md) if you obtain developer-team access.

1. Add your active developer account to Xcode and create an Apple Development signing certificate.
2. Register an explicit App ID in the developer portal and enable **MusicKit under App Services**. This is not an Xcode signing capability and does not require a MusicKit-specific entitlement.
3. Put your team ID and registered bundle ID in `Config/Local.xcconfig`, using the example file or `scripts/configure-signing.py`. This ignored file survives project regeneration.
4. Run the signed Xcode app on a Mac signed into the intended Media & Purchases account. An active Apple Music subscription is required for catalog streaming. Use the same listening account and enable Sync Library on your other devices.
5. Open **Settings > Connection**, expand **Independent MusicKit player**, and select **Connect using MusicKit**. This connection checks the app bundle, identifier, and signing team before requesting MusicKit access.

Native MusicKit manages developer and user tokens for the configured app. No private signing key, manually pasted token, or separate backend is used. Don't add developer credentials to this repository.

Connecting reads the library. It verifies an authenticated storefront request, checks subscription and cloud-library availability, and loads playlists before marking the session connected. Errors include the failed connection stage and an error domain/code in the session log. Favoriting and playlist additions are explicit actions in track menus and can change the real account. Use a disposable test playlist for the experiment.

Successful connections are restored on launch when music permission is still allowed and the build passes setup checks. Switching to samples disables automatic restoration.

## Account experiment

The account panel includes a session log, a play-count snapshot action, and a copy button that includes your observations. Logs stay in memory and are never uploaded. See [the validation checklist](docs/integration-checklist.md).

Music.app connection, transport, metadata reads, library search, favorites, and playlist additions use `MusicAppLibrary` and its serial automation bridge. Use the [Music.app checklist](docs/music-app-checklist.md) to record actual account behavior. Automated tests compile all scripts against the installed Music dictionary and check string round trips, identifier rejection, and numeric bounds. They do not grant permissions or start music.

Retained MusicKit paths:

- Signing/setup checks, authorization, authenticated storefront verification, and subscription/cloud-library availability.
- Paginated playlist and playlist-song reads.
- Library or catalog song search.
- Independent `ApplicationMusicPlayer` playback, seeking, skipping, shuffle/repeat, and queue edits.
- Apple Music API favorite requests and additions to existing playlists through `MusicDataRequest`.
- On-demand library play-count reads for the current song.

These paths compile against the local SDK. They have **not** been validated against a signed-in account. An accepted write is not proof that another device has received it. Some favorite IDs can be ignored by the service. Imported music, unavailable songs, playlist permissions, large libraries, queue-update behavior, listening history, Replay, lossless audio, and AirPlay need real-device verification.

In MusicKit mode, Favorites contains only requests accepted during this session. Music.app mode reads existing favorite library tracks and supports removing favorites. Downloads and full playlist editing are outside this prototype.

## Build and test

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Core tests cover duplicate queue occurrences, insertion order, protected current/played entries, queue movement, shuffle invariants, end/repeat behavior, search matching, and duration formatting. Appearance tests check preset and generated palette contrast, hex input, exact custom colors, and preference serialization. Player tests cover sleep deadlines, cancellation, history, and clearing the queue. They do not test Apple's service.

The Xcode project is checked in and has no generator dependency. If you add or remove source files, regenerate it with `python3 scripts/generate_project.py`. Local signing settings in `Config/Local.xcconfig` are preserved. Don't regenerate merely to build.

## Code

- `Sources/PlayerCore`: models, sample fixtures, sample queue behavior, and safe AppleScript builders.
- `MusicAppLibrary.swift`: Music.app library and transport adapter, serialized Apple events, and response decoding.
- `MusicLibraryService.swift`: library abstraction, sample implementation, and Apple Music integration.
- `PlaybackController.swift`: sample, Music.app, and MusicKit playback modes with capability checks.
- `AppModel.swift`: browsing state, preferences, session transitions, and errors.
- `ContentView.swift`, `PlayerViews.swift`, `SearchView.swift`: native interface.
- `Theme.swift`, `SettingsView.swift`, `ThemeColors.swift`: saved appearance, live palette editor, and sRGB contrast calculations.
- `DiagnosticsView.swift`: account connection and integration observations.

API references: [MusicKit](https://developer.apple.com/musickit/), [ApplicationMusicPlayer](https://developer.apple.com/documentation/musickit/applicationmusicplayer), [favorite resource](https://developer.apple.com/documentation/applemusicapi/add-resource-to-favorites), and [playlist additions](https://developer.apple.com/documentation/applemusicapi/add-tracks-to-a-library-playlist).
