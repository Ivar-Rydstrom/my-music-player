import SwiftUI
import AppKit
#if SWIFT_PACKAGE
import PlayerCore
#endif

/// The window "frame" colours, like an Arc Space: the accent blends into the companion colour across
/// the whole window. The mix is gentle so every preset stays calm, light or dark.
extension PlayerTheme {
    /// A frame tone from a theme colour's hue. Saturation is lifted for muted accents and capped for
    /// loud ones, and brightness is fixed per mode, so every preset gets the same calm depth.
    private func frameTone(_ color: ThemeColor, lift: Double) -> ThemeColor {
        let ns = NSColor(color.color).usingColorSpace(.sRGB) ?? .gray
        let saturation = ns.saturationComponent
        let tone = isDark
            ? Color(hue: ns.hueComponent, saturation: min(0.42, 0.10 + saturation * 0.55) * (saturation < 0.06 ? 0.3 : 1), brightness: 0.27 + lift)
            : Color(hue: ns.hueComponent, saturation: min(0.26, 0.09 + saturation * 0.5) * (saturation < 0.06 ? 0.3 : 1), brightness: 0.87 + lift)
        return ThemeColor(color: tone).mixed(with: base, amount: 0.18)
    }
    /// Top-left of the frame: the accent's hue.
    var frameLead: ThemeColor { frameTone(highlight, lift: 0) }
    /// Bottom-right of the frame: the companion's hue.
    var frameTrail: ThemeColor { frameTone(glow, lift: isDark ? -0.03 : 0.02) }
    var frameMid: ThemeColor { frameLead.mixed(with: frameTrail, amount: 0.5) }
    var frameGradient: LinearGradient {
        // Mostly top-to-bottom, so the sidebar itself shows the accent melting into the companion.
        LinearGradient(stops: [.init(color: frameLead.color, location: 0.05),
                               .init(color: frameLead.mixed(with: frameTrail, amount: 0.5).color, location: 0.5),
                               .init(color: frameTrail.color, location: 0.95)],
                       startPoint: UnitPoint(x: 0, y: 0), endPoint: UnitPoint(x: 0.3, y: 1))
    }
    var frameInk: Color { frameMid.readableInk.mixed(with: frameMid, amount: 0.08).color }
    var frameMuted: Color {
        frameMid.readableInk.mixed(with: frameMid, amount: 0.42).readable(on: [frameLead, frameTrail], minimum: 3.2).color
    }
    var frameIsDark: Bool { frameMid.readableInk == .white }
    /// Arc's selected tab: a white pill on light frames, a lighter translucent fill on dark ones.
    var sidebarSelection: Color { frameIsDark ? Color.white.opacity(0.13) : Color.white.opacity(0.78) }
    var sidebarHover: Color { frameIsDark ? Color.white.opacity(0.06) : Color.white.opacity(0.30) }
    /// The translucent address-bar field under the traffic lights.
    var addressFill: Color { frameIsDark ? Color.white.opacity(0.08) : Color.white.opacity(0.38) }
    /// The palette's highlighted row: the theme accent, settled to a mid tone so white text reads on it.
    var paletteHighlight: Color {
        let ns = NSColor(highlight.color).usingColorSpace(.sRGB) ?? .gray
        let saturation = min(0.55, ns.saturationComponent * 0.75 + 0.12)
        return Color(hue: ns.hueComponent, saturation: saturation, brightness: 0.46).opacity(0.85)
    }
    /// Song-row selection: tinted, never system grey.
    var rowSelection: Color { accent.opacity(isDark ? 0.20 : 0.15) }
    var rowHover: Color { text.opacity(isDark ? 0.05 : 0.04) }
}

/// Arc-style traffic lights, drawn by the app so they can live in the sidebar, hide on collapse, and
/// reappear inside the hover-peek panel. Hovering the group shows the familiar glyphs.
struct TrafficLights: View {
    @Environment(\.controlActiveState) private var active
    @State private var hovering = false
    #if DEBUG
    /// Screenshots capture a background window; `--lights=on` draws the lights as if it were key.
    private let forceColor = ProcessInfo.processInfo.arguments.contains("--lights=on")
    #else
    private let forceColor = false
    #endif
    var window: NSWindow?

    var body: some View {
        HStack(spacing: 8) {
            light(Color(red: 1.0, green: 0.37, blue: 0.34), glyph: "xmark", label: "Close") { window?.performClose(nil) }
            light(Color(red: 1.0, green: 0.74, blue: 0.18), glyph: "minus", label: "Minimize") { window?.performMiniaturize(nil) }
            light(Color(red: 0.16, green: 0.79, blue: 0.25), glyph: "arrow.up.left.and.arrow.down.right", label: "Full screen") { window?.toggleFullScreen(nil) }
        }
        .onHover { hovering = $0 }
    }

    private func light(_ color: Color, glyph: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(active == .inactive && !hovering && !forceColor ? Color.gray.opacity(0.35) : color)
                .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
                .overlay {
                    if hovering {
                        Image(systemName: glyph).font(.system(size: 6.5, weight: .black)).foregroundStyle(.black.opacity(0.55))
                    }
                }
                .frame(width: 12, height: 12)
        }
        .buttonStyle(.plain).accessibilityLabel(label)
    }
}

/// Empty frame areas drag the window, as the hidden title bar no longer does it everywhere.
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 { window?.performZoom(nil) } else { window?.performDrag(with: event) }
        }
    }
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Small square icon button for the sidebar chrome (toggle, back/forward, bottom bar).
struct ChromeButton: View {
    @Environment(\.playerTheme) private var theme
    @Environment(\.isEnabled) private var enabled
    var symbol: String
    var help: String
    var size: CGFloat = 14
    var action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size, weight: .medium))
                .foregroundStyle(enabled ? (hovering ? theme.frameInk : theme.frameMuted) : theme.frameMuted.opacity(0.45))
                .frame(width: 28, height: 28)
                .background(hovering && enabled ? theme.sidebarHover : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(help).accessibilityLabel(help)
        .onHover { hovering = $0 }
    }
}

struct KeyCap: View {
    @Environment(\.playerTheme) private var theme
    var label: String
    init(_ label: String) { self.label = label }
    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(theme.muted)
            .padding(.horizontal, 5).frame(minWidth: 20, minHeight: 18)
            .background(theme.text.opacity(0.06), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(theme.text.opacity(0.1)))
    }
}
