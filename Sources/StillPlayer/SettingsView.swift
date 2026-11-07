import SwiftUI
#if SWIFT_PACKAGE
import PlayerCore
#endif

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: ThemeStore
    @ObservedObject var updater: AppUpdater
    @Environment(\.playerTheme) private var theme
    /// Remembered, so the palette's "Settings: Connection" (etc.) can open straight to a section.
    @AppStorage("settings.tab") private var tab = ProcessInfo.processInfo.arguments.contains("--connect-music") ? "connection" : "appearance"
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings").font(.system(size: 23, weight: .semibold, design: .rounded))
                Spacer()
                Picker("Settings section", selection: $tab) {
                    Text("Appearance").tag("appearance")
                    Text("Connection").tag("connection")
                    Text("Keyboard").tag("keyboard")
                    Text("Updates").tag("updates")
                }.pickerStyle(.segmented).labelsHidden().frame(width: 440)
            }.padding(26)
            Divider()
            if tab == "appearance" {
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("A little more you.").font(.system(size: 28, weight: .semibold, design: .rounded))
                            Text("Pick a palette, or make one that feels like home.").foregroundStyle(theme.muted)
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                            ForEach(ThemePreset.all) { preset in
                                Button { store.preferences.preset = preset.id } label: {
                                    VStack(alignment: .leading, spacing: 10) {
                                        miniature(preset.theme).frame(height: 68)
                                        HStack {
                                            Text(preset.name).font(.system(size: 12, weight: .medium))
                                            Spacer()
                                            if store.preferences.preset == preset.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.accent) }
                                        }
                                    }.padding(10).background(theme.surface, in: RoundedRectangle(cornerRadius: 13))
                                        .overlay(RoundedRectangle(cornerRadius: 13).stroke(store.preferences.preset == preset.id ? theme.accent : theme.muted.opacity(0.15), lineWidth: 1))
                                }.buttonStyle(.plain).accessibilityLabel("\(preset.name) theme")
                            }
                        }
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Your own mix").font(.headline)
                                Text("Start with a color. Fine-tune every detail.").font(.callout).foregroundStyle(theme.muted)
                            }
                            Spacer()
                            if store.preferences.preset != "custom" {
                                Button("Create a theme") { store.customize() }.buttonStyle(.borderedProminent).foregroundStyle(theme.buttonInk)
                            } else {
                                Label("Custom", systemImage: "slider.horizontal.3").font(.callout).foregroundStyle(theme.accent)
                            }
                        }
                        if store.preferences.preset == "custom" { customEditor }
                        HStack {
                            Image(systemName: "checkmark.circle").foregroundStyle(theme.accent)
                            Text("Changes save automatically on this Mac.").font(.caption).foregroundStyle(theme.muted)
                            Spacer()
                            Button("Reset appearance") { store.preferences = ThemePreferences() }.font(.caption).buttonStyle(.plain)
                        }
                    }.padding(28)
                }
            } else if tab == "keyboard" {
                KeyboardSettingsView()
            } else if tab == "updates" {
                UpdateSettingsView(updater: updater)
            } else {
                DiagnosticsView(model: model)
            }
        }.frame(width: 740, height: 780).background(theme.background)
    }

    private func miniature(_ colors: PlayerTheme) -> some View {
        HStack(spacing: 7) {
            VStack(alignment: .leading, spacing: 5) {
                Circle().fill(colors.accent).frame(width: 9, height: 9)
                Capsule().fill(colors.accent.opacity(0.3)).frame(width: 26, height: 4)
                Capsule().fill(colors.muted.opacity(0.3)).frame(width: 22, height: 4)
                Spacer(minLength: 0)
            }.padding(8).frame(width: 46).background(colors.surface)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 5).fill(colors.highlight.color.gradient).frame(width: 26, height: 26)
                Capsule().fill(colors.text.opacity(0.5)).frame(height: 4)
                Capsule().fill(colors.muted.opacity(0.25)).frame(height: 4)
            }.padding(.trailing, 10)
        }.background(colors.background.overlay(colors.wash)).clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private var customEditor: some View {
        VStack(alignment: .leading, spacing: 18) {
            Toggle("Automatic palette", isOn: Binding(get: { store.preferences.automatic }, set: { store.setAutomatic($0) }))
                .toggleStyle(.switch).accessibilityLabel("Automatic palette")
            if store.preferences.automatic {
                HStack(alignment: .top, spacing: 22) {
                    ColorField(hue: $store.preferences.hue, saturation: $store.preferences.saturation)
                        .frame(height: 145)
                    VStack(alignment: .leading, spacing: 17) {
                        Text("Drag to find your color").font(.callout.weight(.medium))
                        Picker("Appearance", selection: $store.preferences.light) {
                            Text("Dark").tag(false)
                            Text("Light").tag(true)
                        }.pickerStyle(.segmented)
                        HStack { Text("Color depth"); Spacer(); Text("\(Int(store.preferences.intensity * 100))%").monospacedDigit() }
                            .font(.caption).foregroundStyle(theme.muted)
                        Slider(value: $store.preferences.intensity, in: 0...1).accessibilityLabel("Color depth")
                    }.frame(width: 235)
                }
                Text("Background, accent, and a companion color follow your selection. Text contrast adjusts automatically.")
                    .font(.caption).foregroundStyle(theme.muted)
            } else {
                Text("Choose exact colors with the picker or a six-digit hex value.").font(.callout).foregroundStyle(theme.muted)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    HexColorField(title: "Background", hex: $store.preferences.background)
                    HexColorField(title: "Surface", hex: $store.preferences.surface)
                    HexColorField(title: "Accent", hex: $store.preferences.accent)
                    HexColorField(title: "Companion", hex: $store.preferences.companion)
                }
                Text("Accent controls adjust for readability. Keep background and surface colors similarly light or dark for readable text.")
                    .font(.caption).foregroundStyle(theme.muted)
            }
        }.padding(20).background(theme.surface, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct ColorField: View {
    @Binding var hue: Double
    @Binding var saturation: Double
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(stops: (0...12).map { .init(color: Color(hue: Double($0) / 12, saturation: 1, brightness: 1), location: Double($0) / 12) }, startPoint: .leading, endPoint: .trailing)
                LinearGradient(colors: [.white.opacity(0.95), .clear], startPoint: .top, endPoint: .bottom)
                Circle().fill(Color(hue: hue, saturation: saturation, brightness: 1))
                    .frame(width: 22, height: 22).overlay(Circle().stroke(.white, lineWidth: 3))
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    .position(x: 12 + hue * (proxy.size.width - 24), y: 12 + saturation * (proxy.size.height - 24))
            }.clipShape(RoundedRectangle(cornerRadius: 13)).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    hue = min(1, max(0, (value.location.x - 12) / (proxy.size.width - 24)))
                    saturation = min(1, max(0, (value.location.y - 12) / (proxy.size.height - 24)))
                })
        }.accessibilityElement(children: .ignore).accessibilityLabel("Theme color")
            .accessibilityValue("Hue \(Int(hue * 360)) degrees, saturation \(Int(saturation * 100)) percent")
            .accessibilityAdjustableAction { direction in
                switch direction { case .increment: hue = min(1, hue + 0.025); case .decrement: hue = max(0, hue - 0.025); @unknown default: break }
            }
    }
}

private struct HexColorField: View {
    var title: String
    @Binding var hex: String
    @State private var draft = ""
    private var valid: Bool { ThemeColor(hex: draft) != nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                ColorPicker(title, selection: Binding(get: { (ThemeColor(hex: hex) ?? .black).color }, set: { hex = ThemeColor(color: $0).hex }), supportsOpacity: false)
                TextField("#RRGGBB", text: $draft).font(.system(.caption, design: .monospaced)).textFieldStyle(.roundedBorder).frame(width: 90)
                    .accessibilityLabel("\(title) hex color")
            }
            if !valid { Text("Enter six hex digits.").font(.caption2).foregroundStyle(.orange) }
        }
        .onAppear { draft = hex }
        .onChange(of: hex) { _, value in if draft != value { draft = value } }
        .onChange(of: draft) { _, value in if let color = ThemeColor(hex: value) { hex = color.hex } }
    }
}
