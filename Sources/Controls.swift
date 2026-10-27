import AppKit
import SwiftUI

extension NowPlaying {
    /// Whether the full-screen lock-screen view is showing.
    func stageVisible(_ s: StyleValues) -> Bool {
        s.showOnLockScreen && ((active && locked) || previewing)
    }
}

final class HoverState: ObservableObject {
    static let shared = HoverState()
    @Published var hovering = false
}

private func timeString(_ seconds: Double) -> String {
    let s = max(0, Int(seconds.rounded()))
    return String(format: "%d:%02d", s / 60, s % 60)
}

/// Glass pill with artwork, song, progress and — on hover — previous / play-pause / next.
struct NowPlayingBar: View {
    @ObservedObject private var style = Style.shared
    @ObservedObject private var player = NowPlaying.shared
    @ObservedObject private var hover = HoverState.shared
    @State private var dragFraction: Double?  // set while scrubbing
    @State private var barHovered = false

    var body: some View {
        let visible = style.v.stageFooter && player.stageVisible(style.v) && player.track != nil
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            pill(position: player.position(at: context.date))
        }
        .opacity(visible ? 1 : 0)
        .animation(.easeInOut(duration: 0.6), value: visible)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pill(position: Double) -> some View {
        let duration = max(player.duration, 1)
        let fraction = min(max(position / duration, 0), 1)
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        return HStack(spacing: 16) {
            if let art = player.artwork {
                Image(nsImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
            }
            VStack(alignment: .leading, spacing: 7) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.track?.title ?? "").font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text(player.track?.artist ?? "").font(.system(size: 13, design: .rounded)).opacity(0.7)
                }
                .lineLimit(1)
                progress(fraction: fraction, position: position, duration: duration)
            }
            .frame(width: 250, alignment: .leading)
            if hover.hovering {
                controls
                    .transition(.move(edge: .trailing).combined(with: .opacity).combined(with: .scale(scale: 0.8)))
            }
        }
        .foregroundStyle(Color.white)
        .padding(.vertical, 14)
        .padding(.leading, 14)
        .padding(.trailing, 22)
        .background { glass(shape) }
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: hover.hovering)
    }

    /// Click or drag anywhere on the bar to scrub; the song jumps when the drag ends.
    private func progress(fraction: Double, position: Double, duration: Double) -> some View {
        let shown = dragFraction ?? fraction
        let shownPosition = dragFraction.map { $0 * duration } ?? position
        let active = barHovered || dragFraction != nil
        return VStack(spacing: 4) {
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.22))
                    Capsule().fill(Color.white).frame(width: width * shown)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 12, height: 12)
                        .shadow(color: .black.opacity(0.3), radius: 3)
                        .offset(x: width * shown - 6)
                        .opacity(active ? 1 : 0)
                }
                .frame(height: active ? 8 : 4)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { dragFraction = min(max($0.location.x / width, 0), 1) }
                    .onEnded { value in
                        let target = min(max(value.location.x / width, 0), 1)
                        player.seek(to: target * duration)
                        dragFraction = nil
                    })
                .onHover { barHovered = $0 }
            }
            .frame(height: 14)  // taller hit area than the visible bar
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: active)
            HStack {
                Text(timeString(shownPosition))
                Spacer()
                Text("-" + timeString(duration - shownPosition))
            }
            .font(.system(size: 10.5, weight: .medium, design: .rounded))
            .monospacedDigit()
            .opacity(0.65)
        }
    }

    private var controls: some View {
        HStack(spacing: 18) {
            button("backward.fill", size: 20) { player.control("previous track") }
            button(player.isPlaying ? "pause.fill" : "play.fill", size: 28) { player.control("playpause") }
            button("forward.fill", size: 20) { player.control("next track") }
        }
        .padding(.leading, 4)
    }

    private func button(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .bold))
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(PressableStyle())
    }

    @ViewBuilder
    private func glass(_ shape: RoundedRectangle) -> some View {
        if #available(macOS 26.0, *) {
            shape.fill(Color.black.opacity(0.12)).glassEffect(.regular, in: shape)
        } else {
            VisualEffect().clipShape(shape)
        }
    }
}

/// Shrinks a little while pressed.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.85 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Hosting view that reports hover even though Cadence is never the active app, and
/// lets the first click hit a button straight away.
final class ControlsHostingView: NSHostingView<NowPlayingBar> {
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { HoverState.shared.hovering = true }
    override func mouseExited(with event: NSEvent) { HoverState.shared.hovering = false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Small clickable window for the now-playing bar, layered above the full-screen lyrics.
final class ControlsWindow: NSPanel {
    init(screen: NSScreen) {
        let size = NSSize(width: 640, height: 120)
        let frame = NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.minY + 34,
                           width: size.width, height: size.height)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        canBecomeVisibleWithoutLogin = true
        ignoresMouseEvents = true  // enabled only while the bar is showing
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let hosting = ControlsHostingView(rootView: NowPlayingBar())
        hosting.sizingOptions = []
        contentView = hosting
        orderFrontRegardless()
        LockScreen.attach(self)
    }

    override var canBecomeKey: Bool { false }
}
