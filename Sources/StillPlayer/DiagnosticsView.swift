import SwiftUI
import MusicKit

struct DiagnosticsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var observations = ""
    @State private var setup = MusicAccountSetup.inspect()
    @State private var authorization = MusicAccountSetup.authorization
    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Account & integration").font(.title2.weight(.semibold))
                    Text("Connect your existing library and subscription.").foregroundStyle(Palette.muted)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label(model.usesMusicApp ? "Connected to Music.app" : "Use Music.app for playback", systemImage: "music.note")
                        .foregroundStyle(Palette.accent)
                    Text("No developer membership required. Still reads your playlists and controls Music while it runs in the background. Allow control of Music when macOS asks.")
                        .font(.callout).foregroundStyle(Palette.muted)
                    Text(model.connectionStatus).font(.caption).foregroundStyle(Palette.muted)
                    HStack {
                        Button(model.isConnecting ? "Connecting…" : model.usesMusicApp ? "Reconnect to Music" : "Connect Music.app") {
                            Task { await model.connect() }
                        }.buttonStyle(.borderedProminent).disabled(model.isConnecting)
                        if model.isConnecting { ProgressView().controlSize(.small) }
                        if model.isLive { Button("Use sample library") { model.useSamples() }.disabled(model.isConnecting) }
                        Button("Open Music") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Music.app")) }
                    }
                    Button("Automation settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                    }.font(.caption)
                    Text("Connect only reads data. Favoriting and playlist additions happen when you choose them. Switching to samples or quitting Still leaves Music's playback running.")
                        .font(.caption).foregroundStyle(Palette.muted)
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
            }
            DisclosureGroup("Independent MusicKit player · optional") {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label(model.isLive ? "Connected to Apple Music" : "Using sample data", systemImage: model.isLive ? "checkmark.circle" : "music.note.list")
                        .foregroundStyle(Palette.accent)
                    Text("Connecting reads your library. Favorites and playlist changes only happen when you choose those actions.")
                        .font(.callout).foregroundStyle(Palette.muted)
                    if let issue = setup.issue {
                        Text(issue).font(.callout).foregroundStyle(.orange)
                        HStack {
                            Link("Developer enrollment", destination: URL(string: "https://developer.apple.com/programs/enroll/")!)
                            Link("App IDs & services", destination: URL(string: "https://developer.apple.com/account/resources/identifiers/list")!)
                        }.font(.caption)
                    }
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                        GridRow { Text("Bundle ID"); Text(setup.bundleID.isEmpty ? "Not an app bundle" : setup.bundleID).textSelection(.enabled) }
                        GridRow { Text("Signing team"); Text(setup.teamID ?? "Not configured").textSelection(.enabled) }
                        GridRow { Text("Music permission"); Text(authorization) }
                        GridRow { Text("Connection"); Text(model.connectionStatus) }
                        if let storefront = model.accountStorefront {
                            GridRow { Text("Storefront"); Text(storefront.uppercased()) }
                            GridRow { Text("Catalog playback"); Text(model.canStream ? "Available" : "Unavailable") }
                            GridRow { Text("Sync Library"); Text(model.cloudLibraryEnabled ? "Enabled" : "Disabled") }
                        }
                    }.font(.caption).foregroundStyle(Palette.muted)
                    HStack {
                        Button("Connect using MusicKit") { Task { await model.connectMusicKit() } }
                            .buttonStyle(.borderedProminent).disabled(model.isConnecting || setup.issue != nil)
                        Button("Recheck setup") {
                            setup = MusicAccountSetup.inspect()
                            authorization = MusicAccountSetup.authorization
                        }.disabled(model.isConnecting)
                        if model.isConnecting { ProgressView().controlSize(.small) }
                        if model.isLive { Button("Use sample library") { model.useSamples() }.disabled(model.isConnecting) }
                    }
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
            }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Account experiment").font(.headline)
                Text("1. Open a playlist and test play, pause, seek, skip, and volume.\n2. Favorite a song and add one to a test playlist using the track menu.\n3. Check the changes on your iPhone and refresh this app.\n4. Complete a song and check listening history and play counts.\n5. Test sleep, network interruption, and output-device changes.")
                    .font(.callout).lineSpacing(4).foregroundStyle(Palette.muted)
                Text("Music.app handles account sync and audio output. Its Up Next queue and catalog search stay in Music. Cross-device sync still needs testing with your account.")
                    .font(.caption).foregroundStyle(Palette.muted)
            }
            HStack {
                Text("Session log").font(.headline)
                Spacer()
                Button("Record play-count snapshot") {
                    guard model.isLive else { model.record("Play counts are unavailable in sample mode."); return }
                    if model.usesMusicApp {
                        if let current = model.playback.current {
                            model.record("\(current.title): Music play count \(current.playCount.map(String.init) ?? "unavailable").")
                        } else { model.record("Play a song first to capture its play count.") }
                        return
                    }
                    Task {
                        do {
                            var request = MusicLibraryRequest<Song>()
                            if let current = model.playback.current {
                                request.filter(matching: \.id, equalTo: MusicItemID(current.id))
                                let song = try await request.response().items.first
                                model.record("\(current.title): library play count \(song?.playCount.map(String.init) ?? "unavailable"). Check history in Music too.")
                            } else { model.record("Play a library song first to capture its play count.") }
                        } catch { model.record("Play-count lookup failed: \(error.localizedDescription)") }
                    }
                }
                Button("Copy log") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.log.reversed().joined(separator: "\n") + "\n\nObservations:\n" + observations, forType: .string)
                }
            }
            ScrollView {
                Text(model.log.isEmpty ? "No account operations yet." : model.log.joined(separator: "\n"))
                    .font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }.frame(height: 100).background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
            TextField("Notes about sync or playback…", text: $observations).textFieldStyle(.roundedBorder)
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
        }.padding(28)
        }.frame(width: 730, height: 730).background(Palette.background)
            .onChange(of: model.isConnecting) { _, _ in authorization = MusicAccountSetup.authorization }
    }
}
