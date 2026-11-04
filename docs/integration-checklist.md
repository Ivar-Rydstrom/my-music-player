# Account validation

Use a signed Xcode build and a disposable playlist. Record macOS, iOS, Xcode versions, bundle ID, account storefront, and subscription status. Do not include account identifiers or tokens in shared logs.

| Check | Procedure | Result |
| --- | --- | --- |
| Authorization | Connect, allow access, load playlists. Repeat with permission denied. | Not run |
| Pagination | Compare full playlist count and a playlist with more than 100 songs against Music. | Not run |
| Independent playback | Quit Music.app, then play a playlist here. Check pause, seek, skip, repeat, and shuffle. | Not run |
| Queue | Add duplicate songs, insert next, append, reorder, and remove. Verify audible order, not only the displayed list. | Not run |
| Favorites | Favorite a catalog song and a library song. Confirm each on Mac and iPhone. Record delays. | Not run |
| Playlist addition | Add a song to the test playlist. Verify Mac and iPhone, then refresh this app. | Not run |
| Read after external edit | Add a song on iPhone. Refresh the library here and confirm it appears. | Not run |
| Play count | Capture a count for a library song before playback. Finish the song, capture again, and compare with Music after refresh. | Not run |
| Listening history | Complete a song and check Recently Played in Music with listening history enabled. | Not run |
| Replay | Observe over time. A local play-count change alone does not prove Replay attribution. | Not run |
| Sleep and output | Sleep/wake, switch headphones/output, and check playback state and progress. | Not run |
| Network | Disconnect during browsing and streaming, reconnect, and retry. Check errors and recovery. | Not run |
| Imported content | Try matched, uploaded, local-only, and unavailable tracks. Note omissions and playback failures. | Not run |
| Audio requirements | Verify desired lossless/Atmos and AirPlay behavior separately. No support claim yet. | Not run |

The app never fabricates a history write or manually increments play counts. Apple's service determines listening statistics. Copy the session log from Account & integration and add timestamps for observations from other devices.
