import Foundation

public enum MusicAppScriptError: LocalizedError {
    case invalidID
    public var errorDescription: String? { "Music returned an invalid persistent identifier. Refresh the library and try again." }
}

/// User text is encoded as an AppleScript literal; identifiers are validated separately.
public enum MusicAppScripts {
    public static func literal(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t") + "\""
    }
    public static func identifier(_ id: String) throws -> String {
        guard id.range(of: "^[0-9A-Fa-f]{16}$", options: .regularExpression) != nil else { throw MusicAppScriptError.invalidID }
        return literal(id)
    }
    public static func wrap(_ body: String) -> String {
        "with timeout of 30 seconds\ntell application id \"com.apple.Music\"\n\(body)\nend tell\nend timeout"
    }
    public static let playlists = wrap("""
        set resultRows to {}
        repeat with p in (every playlist)
            if special kind of p is not folder and special kind of p is not Library and special kind of p is not Music then
                set editable to false
                try
                    if class of p is user playlist then
                        set editable to ((smart of p is false) and (special kind of p is none))
                    end if
                end try
                set end of resultRows to {persistent ID of p, name of p, editable}
            end if
        end repeat
        return resultRows
        """)
    public static let handshake = "with timeout of 120 seconds\ntell application id \"com.apple.Music\" to return version\nend timeout"

    public static func tracks(playlistID: String) throws -> String {
        let id = try identifier(playlistID)
        return wrap("set p to first playlist whose persistent ID is \(id)\n" + columns("every track of p"))
    }
    public static func search(_ query: String) -> String {
        let q = literal(query)
        return wrap(columns("every track of library playlist 1 whose name contains \(q) or artist contains \(q) or album contains \(q)"))
    }
    public static let favorites = wrap(columns("every track of library playlist 1 whose favorited is true"))
    private static func columns(_ target: String) -> String {
        // Bulk property requests preserve order and avoid one Apple event per track per field.
        "return {" + ["persistent ID", "name", "artist", "album", "duration", "favorited", "played count"]
            .map { "(\($0) of (\(target)))" }.joined(separator: ", ") + "}"
    }
    public static func reference(_ track: LibraryTrack) throws -> String {
        let playlist = try track.sourcePlaylistID.map { "(first playlist whose persistent ID is \(try identifier($0)))" } ?? "library playlist 1"
        return "(first track of \(playlist) whose persistent ID is \(try identifier(track.id)))"
    }
    public static func play(_ track: LibraryTrack) throws -> String {
        let ref = try reference(track)
        if let playlistID = track.sourcePlaylistID, let index = track.sourceIndex, index > 0 {
            // Preserve the selected occurrence, but never play a different song after an external edit.
            return wrap("""
                set p to first playlist whose persistent ID is \(try identifier(playlistID))
                if (count of tracks of p) >= \(index) then
                    if persistent ID of track \(index) of p is \(try identifier(track.id)) then
                        play track \(index) of p
                        return
                    end if
                end if
                play \(ref)
                """)
        }
        return wrap("play \(ref)")
    }
    public static func playPlaylist(id: String) throws -> String {
        wrap("play (first playlist whose persistent ID is \(try identifier(id)))")
    }
    public static func favorite(_ track: LibraryTrack, value: Bool) throws -> String {
        wrap("""
            if exists current track then
                if persistent ID of current track is \(try identifier(track.id)) then
                    set favorited of current track to \(value ? "true" : "false")
                    return
                end if
            end if
            set favorited of \(try reference(track)) to \(value ? "true" : "false")
            """)
    }
    public static func add(_ tracks: [LibraryTrack], playlistID: String) throws -> String {
        let target = "(first user playlist whose persistent ID is \(try identifier(playlistID)))"
        return wrap(try tracks.map { "duplicate \(try reference($0)) to \(target)" }.joined(separator: "\n"))
    }
    public static let snapshot = "if application id \"com.apple.Music\" is not running then error \"Music is not running\" number -600\n" + wrap("""
        set stateText to player state as text
        set positionValue to 0
        set trackRow to {}
        try
            set t to current track
            set trackRow to {persistent ID of t, name of t, artist of t, album of t, duration of t, favorited of t, played count of t}
            set positionValue to player position
        on error number -1728
            set trackRow to {}
        end try
        set playlistID to ""
        try
            set playlistID to persistent ID of current playlist
        end try
        return {stateText, positionValue, shuffle enabled, (song repeat as text), sound volume, trackRow, playlistID}
        """)
    /// Artwork is fetched separately so bulk library reads remain fast.
    public static func artwork(id: String, playlist: Bool = false, sourcePlaylistID: String? = nil) throws -> String {
        let id = try identifier(id)
        // Cloud playlist tracks need not be members of the main library.
        let source = try sourcePlaylistID.map { "(first playlist whose persistent ID is \(try identifier($0)))" }
            ?? "library playlist 1"
        let target = playlist
            ? "first playlist whose persistent ID is \(id)"
            : "first track of \(source) whose persistent ID is \(id)"
        let fallback = playlist ? """
            try
                set t to first track of (first playlist whose persistent ID is \(id))
                if (count of artworks of t) > 0 then return raw data of artwork 1 of t
            end try
            """ : """
            try
                set t to current track
                if persistent ID of t is \(id) then
                    if (count of artworks of t) > 0 then return raw data of artwork 1 of t
                end if
            end try
            """
        return wrap("""
            try
                set t to \(target)
                if (count of artworks of t) > 0 then return raw data of artwork 1 of t
            end try
            \(fallback)
            return missing value
            """)
    }

    public static func seek(_ seconds: Double) -> String {
        wrap("set player position to \(seconds.isFinite ? max(0, seconds) : 0)")
    }
    public static func volume(_ value: Double) -> String {
        wrap("set sound volume to \(Int(value.isFinite ? min(100, max(0, value)) : 0))")
    }
    public static func shuffle(_ enabled: Bool) -> String {
        wrap("set shuffle enabled to \(enabled ? "true" : "false")")
    }
    public static func repeatAll(_ enabled: Bool) -> String {
        wrap("set song repeat to \(enabled ? "all" : "off")")
    }
}
