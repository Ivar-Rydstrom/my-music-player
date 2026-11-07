import SwiftUI
#if SWIFT_PACKAGE
import PlayerCore
#endif

/// Update alerts and install progress for the main window.
struct UpdatePrompt: ViewModifier {
    @ObservedObject var updater: AppUpdater

    func body(content: Content) -> some View {
        content
            .alert(title, isPresented: Binding(get: { updater.prompt != nil }, set: { if !$0 { updater.prompt = nil } }), presenting: updater.prompt) { prompt in
                switch prompt {
                case .available(let release):
                    Button("Install and Relaunch") { Task { await updater.install(release) } }
                    Button("Skip This Version") { updater.skip(release) }
                    Button("Later", role: .cancel) {}
                case .upToDate:
                    Button("OK", role: .cancel) {}
                case .problem:
                    if let page = updater.releasesPage { Button("Open GitHub Releases") { NSWorkspace.shared.open(page) } }
                    Button("OK", role: .cancel) {}
                }
            } message: { prompt in
                switch prompt {
                case .available(let release):
                    Text("You have \(updater.currentVersion?.description ?? "an older version"). Hummery will quit, update, and reopen.\(excerpt(release.notes))")
                case .upToDate:
                    Text("Hummery \(updater.currentVersion?.description ?? "") is the newest version.")
                case .problem(_, let detail):
                    Text(detail)
                }
            }
            .overlay(alignment: .bottom) {
                if case .installing(_, let step) = updater.phase {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(step).font(.callout)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 96)
                }
            }
    }

    private var title: String {
        switch updater.prompt {
        case .available(let release): return "Hummery \(release.version) is available"
        case .upToDate: return "You're up to date"
        case .problem(let title, _): return title
        case nil: return ""
        }
    }

    private func excerpt(_ notes: String) -> String {
        guard !notes.isEmpty else { return "" }
        return "\n\n" + (notes.count > 600 ? String(notes.prefix(600)) + "…" : notes)
    }
}

struct UpdateSettingsView: View {
    @Environment(\.playerTheme) private var theme
    @ObservedObject var updater: AppUpdater

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Updates").font(.title2.weight(.semibold))
                    Text("New versions come from this project's GitHub releases.").foregroundStyle(theme.muted)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .firstTextBaseline) {
                            Label("Hummery \(updater.currentVersion?.description ?? "development build")", systemImage: "shippingbox")
                                .foregroundStyle(theme.accent)
                            Spacer()
                            if let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
                                Text("Build \(build)").font(.caption).foregroundStyle(theme.muted)
                            }
                        }
                        Text(status).font(.callout).foregroundStyle(statusIsProblem ? .orange : theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            if case .available(let release) = updater.phase {
                                Button("Install \(release.version) and Relaunch") { Task { await updater.install(release) } }
                                    .buttonStyle(.borderedProminent).foregroundStyle(theme.buttonInk)
                            } else {
                                Button("Check Now") { Task { await updater.check(userInitiated: true) } }
                                    .buttonStyle(.borderedProminent).foregroundStyle(theme.buttonInk).disabled(updater.isBusy)
                            }
                            if updater.isBusy { ProgressView().controlSize(.small) }
                            Spacer()
                            if let page = updater.releasesPage { Link("Release notes", destination: page).font(.callout) }
                        }
                        Toggle("Check for updates automatically", isOn: $updater.automaticallyChecks).toggleStyle(.switch)
                        Text("Hummery checks about once a day while it's open. Installing replaces the app where it is and keeps your settings and Music permission.")
                            .font(.caption).foregroundStyle(theme.muted)
                    }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(28)
        }
    }

    private var statusIsProblem: Bool {
        if case .failed = updater.phase { return true }
        return false
    }

    private var status: String {
        switch updater.phase {
        case .checking: return "Checking GitHub…"
        case .installing(_, let step): return step
        case .available(let release): return "Version \(release.version) is ready to install."
        case .failed(let message): return message
        case .upToDate, .idle:
            guard let last = updater.lastCheck else { return "Not checked yet." }
            let when = "Last checked \(last.formatted(.relative(presentation: .named)))."
            return updater.phase == .upToDate ? "Up to date. " + when : when
        }
    }
}
