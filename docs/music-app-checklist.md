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

- Press Shuffle playlist on a cloud playlist, skip several songs, and verify each belongs to that playlist. Compare the player cover with its table row, including after switching the browsed playlist.
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
- Tracks without available artwork use generated placeholders.
- Playlist operations are not transactional. If a multi-song addition fails partway through, some tracks may already have been added. Check Music before retrying.
- Local ad hoc builds may need Automation permission again after rebuilding. Signed distribution and notarization are separate future work.

The retained MusicKit backend remains available in Account & integration and has its own [setup guide](musickit-setup.md).

### Artwork

- Connect to Music.app and open a playlist with known cover art. Its cover should appear in the sidebar and playlist header.
- Include a cloud playlist containing songs not saved in your main Music library. Those rows must load covers using their source playlist.
- Scroll through songs, search the library, open favorites, and change playback in Music. Track covers should appear in the table, player, and queue.
- Playlist artwork is requested directly from Music. If unavailable, the first track's cover is used. Empty playlists and tracks without artwork retain the generated placeholder.
- Artwork requests run separately from metadata and playback polling. Visible track rows and playlist headers take priority over sidebar covers and prefetch. The sidebar creates rows lazily, while a separate background worker warms all sidebar covers and all tracks in the open playlist without scrolling. It fetches one background image at a time, yields without a fixed per-image sleep, and gives sidebar artwork a turn after every eight tracks. Switching playlists cancels the old background pass and replaces unstarted track work. Failed offscreen images receive bounded retry passes after the first pass finishes.
- Requests for the same artwork share a fetch. Music supplies original image data, which is downsampled off the UI thread to 320 pixels for storage and 96 pixels for rows. These cover Retina display sizes without loading originals into table cells. MusicKit connections continue to use Apple's artwork URLs.
- The memory cache retains up to 512 cover images and 512 row thumbnails, evicting only the least recently used entry at capacity. Scrolling reuses row thumbnails instead of re-encoding them. The disk cache survives restarts, expires after seven days, and periodically trims to 512 entries by last access. Cache reads update recency without extending artwork expiry. Visible rows automatically retry transient misses after 0.3, 1, 3, 10, and 30 seconds without navigation. Retries stop when the row disappears. Speculative prefetch suppresses repeated misses for 30 seconds. Cached covers may remain unchanged until expiry.
- Quit and reopen Still. Cached rows should appear without another Music artwork request. Change playlists while covers load and confirm playback controls remain responsive.
- Replace a cover in Music and verify it refreshes after cache expiry.

- In “2013-2015 EDM Hits,” check “If I Lose Myself,” “Find You,” and “Wasted” on the first visit. Transient fetch failures should recover in place without switching playlists. Permanently missing artwork stops after six attempts.

- Leave a long playlist at the top without scrolling. Confirm covers for its final tracks reach the disk cache in the background. Opening another playlist should replace pending work; visible rows must keep priority over background requests.

- Open the 275-track “tik tok songs trending in 2026” playlist. Verify the table remains responsive during artwork warming, unchanged playback polls do not republish favorite state, and returning to previously viewed rows reuses their thumbnails.
