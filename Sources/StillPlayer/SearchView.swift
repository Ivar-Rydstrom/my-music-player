import SwiftUI
#if SWIFT_PACKAGE
import PlayerCore
#endif

struct SearchView: View {
    @Environment(\.playerTheme) private var theme
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var catalog = false
    @State private var selection = Set<String>()
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(theme.accent)
                TextField("Find a song, artist, or album", text: $query).textFieldStyle(.plain).font(.title3).focused($focused)
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(.horizontal, 24).padding(.top, 24)
            HStack {
                if model.usesMusicApp {
                    Label("Your library", systemImage: "music.note.list").font(.callout)
                } else {
                Picker("Search in", selection: $catalog) {
                    Text("Your library").tag(false)
                    Text("Catalog").tag(true)
                }.pickerStyle(.segmented).frame(width: 250)
                }
                Spacer()
                if model.searching { ProgressView().controlSize(.small) }
                Text(model.usesMusicApp ? "Library songs" : model.isLive ? "Up to 25 song results" : "Sample songs in both scopes")
                    .font(.caption).foregroundStyle(theme.muted)
            }.padding(.horizontal, 24)
            if query.isEmpty {
                ContentUnavailableView("Find your next song", systemImage: "magnifyingglass",
                    description: Text(model.usesMusicApp ? "Search your library, then double-click to play." : "Search, then double-click to play or right-click to queue and save."))
            } else if !model.searching && model.searchResults.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                TrackTable(model: model, tracks: model.searchResults, selection: $selection)
            }
            Text("Closing search keeps your playlist and selection in place.")
                .font(.caption).foregroundStyle(theme.muted).padding(.horizontal, 24).padding(.bottom, 20)
        }.frame(width: 810, height: 530).background(theme.background)
            .task { focused = true }
            .task(id: "\(model.isLive)-\(model.usesMusicApp)-\(catalog)-\(query)") { selection = []; await model.search(query, catalog: model.usesMusicApp ? false : catalog) }
    }
}
