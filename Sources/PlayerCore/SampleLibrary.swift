import Foundation

public enum SampleLibrary {
    public static let tracks: [LibraryTrack] = [
        LibraryTrack(id: "demo-1", title: "A Walk", artist: "Tycho", album: "Dive", duration: 316),
        LibraryTrack(id: "demo-2", title: "Kerala", artist: "Bonobo", album: "Migration", duration: 237),
        LibraryTrack(id: "demo-3", title: "Open Eye Signal", artist: "Jon Hopkins", album: "Immunity", duration: 473),
        LibraryTrack(id: "demo-4", title: "Two Thousand and Seventeen", artist: "Four Tet", album: "New Energy", duration: 252),
        LibraryTrack(id: "demo-5", title: "Retrograde", artist: "James Blake", album: "Overgrown", duration: 223),
        LibraryTrack(id: "demo-6", title: "Intro", artist: "The xx", album: "xx", duration: 127),
        LibraryTrack(id: "demo-7", title: "Tadow", artist: "Masego & FKJ", album: "Tadow", duration: 302),
        LibraryTrack(id: "demo-8", title: "Weightless", artist: "Marconi Union", album: "Weightless", duration: 489),
        LibraryTrack(id: "demo-9", title: "Friday Morning", artist: "Khruangbin", album: "Con Todo El Mundo", duration: 414),
        LibraryTrack(id: "demo-10", title: "Nude", artist: "Radiohead", album: "In Rainbows", duration: 255),
        LibraryTrack(id: "demo-11", title: "Pink + White", artist: "Frank Ocean", album: "Blonde", duration: 184),
        LibraryTrack(id: "demo-12", title: "Nights", artist: "Frank Ocean", album: "Blonde", duration: 307)
    ]
    public static let playlists = [
        MusicPlaylist(id: "demo-focus", name: "In the flow", subtitle: "Room to think. A little momentum.", tracks: tracks),
        MusicPlaylist(id: "demo-evening", name: "After hours", subtitle: "For when the day slows down.", tracks: Array(tracks.suffix(7))),
        MusicPlaylist(id: "demo-drive", name: "The long way home", subtitle: "No particular hurry.", tracks: Array(tracks.reversed())),
        MusicPlaylist(id: "demo-repeat", name: "On repeat", subtitle: "Always worth another listen.", tracks: Array(tracks.prefix(5)))
    ]
}
