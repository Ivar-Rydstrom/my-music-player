# Appearance and playback polish

Settings opens from the gear, the sidebar button, or Command-comma. Appearance changes apply to the library, player, search, queue, and connection settings. The six presets include a light option. Custom themes have automatic light/dark palettes, a draggable hue/saturation field, color depth, and manual background, surface, accent, and companion colors.

Automatic palettes derive their surfaces and companion color from the selected color. Label colors and control accents use sRGB contrast calculations. Custom hex fields retain the last valid color while incomplete input is being edited. Exact background and surface colors remain under the user's control. Mixed light and dark custom surfaces can reduce text contrast; the editor recommends keeping them similarly bright. Accent controls adjust for readability, so the selected accent is also used unmodified in decorative gradients.

The interaction takes inspiration from [Arc's color and gradient themes](https://start.arc.net/paint-the-internet). Hummery uses native SwiftUI controls and its own palette calculations.

## Music.app queue investigation

Checked on macOS 26.6.2 against the installed dictionary at:

```
/System/Applications/Music.app/Contents/Resources/com.apple.Music.sdef
```

The dictionary has `play`, `pause`, `next track`, `previous track`, `current track`, and a read-only `current playlist`. It exposes playlist tracks and playlist duplication. It has no Up Next collection or queue insertion, removal, reordering, or observation commands. A playlist's tracks do not represent an edited Up Next queue. [Apple describes the scripting dictionary as the source of an app's supported scripting commands](https://developer.apple.com/library/archive/documentation/LanguagesUtilities/Conceptual/MacAutomationScriptingGuide/AboutScriptingTerminology.html).

The [music-mcp project's workaround](https://github.com/pedrocid/music-mcp) creates temporary playlists and explicitly plays those playlists. This is a separate playing order, not access to Music's existing queue. It writes playlists into the account and requires replacing the current playback context. It cannot faithfully display or edit an existing Up Next list, or preserve external queue edits. UI scripting would require Accessibility permission and depend on Music's current window and localized controls. A web player would require a different playback backend and session.

The current setup uses the public Music scripting interface, without UI scripting or account playlist creation for queue management. The unsupported panel and its toggle are therefore hidden in Music.app mode. Sample and independent MusicKit playback retain their real queue editors, including Clear. This change does not claim that every possible integration with Music is incapable of queue management.

## Native app validation

Screenshots in [screenshots](screenshots) come from the built macOS app, using the sample library with simulated playback and no audio. Capture builds use a separate bundle identifier so appearance experiments and sample mode do not overwrite the normal app's connection preferences.

Automated tests cover color parsing and contrast, preset and generated light/dark palettes, custom color serialization, sleep expiration and cancellation, session history, and clearing upcoming songs without removing the current song. Existing script tests still compile against the installed Music dictionary. Account playback, subscription streaming, and cross-device sync require a connected account and are not implied by sample validation.
