# Music.app validation

Build with `zsh scripts/run-local.sh`. No developer membership, API token, or signing certificate is required for local ad hoc signing. Music and an appropriate listening account/subscription handle streaming.

The first connection reads playlists and current playback, leaving playback and the library unchanged. The app requests macOS Automation permission scoped to Music. It uses Apple events directly, not Accessibility or UI scripting. Its sandbox permits Music's advertised scripting groups plus an Apple-events exception limited to `com.apple.Music` for playlist reads that Music otherwise rejects with -10004. That privilege error is distinct from denied Automation consent, -1743.

## Read-only checks

- Allow Still to control Music in the macOS prompt. Check that playlists appear.
- Decline permission and confirm the app explains how to enable it in Privacy & Security > Automation.
- Open a playlist and compare count and track order with Music. Check duplicate song occurrences.
- Search by title, artist, or album. Try apostrophes, quotes, backslashes, and Unicode text.
- Open Favorite songs and compare against Music's favorites.
- Observe playback started outside Still. Confirm track, position, favorite, shuffle, repeat, and volume update.
- Quit Music while connected. Confirm Still reports the error and stops retrying automatically; open Music and reconnect.

## Playback and write checks

These checks change playback or the library, so perform them deliberately in the UI.

- Double-click a playlist song. Confirm that exact song plays and Music supplies subsequent songs. Table sorting/filtering does not change the source playlist's order.
- Test pause/resume, seek, next, previous, shuffle, repeat, and volume. Seek and volume are sent on slider release to avoid flooding Music with Apple events.
- Favorite and unfavorite a song. Confirm in Music and on iPhone after sync.
- Add a track to a regular disposable playlist. Verify it in Music and on iPhone. Smart and read-only playlists should not appear as targets.
- Change a playlist in Music or on iPhone, then refresh Still.
- Close Still or switch to sample mode during playback. Music should continue.
- Complete a song and record its play count before/after. Music owns listening history and Replay attribution; Still never increments counts.

## Known limits

- Actual Up Next cannot be read or edited through Music's scripting dictionary. Still offers an Open Music button instead of a simulated queue in this mode.
- Catalog search stays in Music. Library search uses scriptable library tracks.
- A song must be addressable in Music's scripting library or source playlist. Some catalog-only streams, stations, or cloud items may not be addressable.
- Placeholder artwork is used. Artwork extraction and caching are deferred.
- Playlist operations are not transactional. If a multi-song addition fails partway through, some tracks may already have been added. Check Music before retrying.
- Local ad hoc builds may need Automation permission again after rebuilding. Signed distribution and notarization are separate future work.

The retained MusicKit backend remains available in Account & integration and has its own [setup guide](musickit-setup.md).

### Artwork

- Connect to Music.app and open a playlist with known cover art. Its cover should appear in the sidebar and playlist header.
- Scroll through songs, search the library, open favorites, and change playback in Music. Track covers should appear in the table, player, and queue.
- Playlist artwork is requested directly from Music. If unavailable, the first track's cover is used. Empty playlists and tracks without artwork retain the generated placeholder.
- Artwork requests run separately from metadata and playback polling. Concurrent requests share a fetch, and up to 256 results are cached in memory for five minutes. MusicKit connections continue to use Apple's artwork URLs.
- Replace a cover in Music and reopen the playlist after five minutes to check cache expiry.
