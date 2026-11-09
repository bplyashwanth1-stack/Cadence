import AppKit
import SwiftUI

// MARK: - Fisheye layout

/// A column of words rolling under a glass lens, the word being sung closest to the glass.
/// `icons` is Fisheye Visual: the same lens with SF Symbols beside the words.
struct FisheyeView: View {
    let time: Double
    let date: Date
    let icons: Bool
    @Environment(\.isClip) private var clip

    var body: some View {
        // Clips are drawn off screen, where the AppKit lens can't render, so they get the words without the glass.
        Group {
            if clip {
                FisheyeWords(time: time, icons: icons)
            } else {
                LensHost(content: AnyView(FisheyeWords(time: time, icons: icons)))
            }
        }
            .shadow(color: .black.opacity(0.45), radius: 10, y: 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Runs SwiftUI content through a Core Image bump distortion on its layer. Core Animation applies it on the GPU, and
/// unlike a SwiftUI shader it needs no compiled .metallib, so the app still builds with only the command line tools.
private struct LensHost: NSViewRepresentable {
    let content: AnyView

    func makeNSView(context: Context) -> LensView { LensView(rootView: content) }
    func updateNSView(_ view: LensView, context: Context) { view.hosting.rootView = content }
}

private final class LensView: NSView {
    let hosting: NSHostingView<AnyView>
    private static let strength = 0.5

    init(rootView: AnyView) {
        hosting = NSHostingView(rootView: rootView)
        super.init(frame: .zero)
        wantsLayer = true
        layerUsesCoreImageFilters = true
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        hosting.frame = bounds
        guard let filter = CIFilter(name: "CIBumpDistortion") else { return }
        filter.setValue(CIVector(x: bounds.midX, y: bounds.midY), forKey: kCIInputCenterKey)
        filter.setValue(bounds.height * 0.75, forKey: kCIInputRadiusKey)
        filter.setValue(Self.strength, forKey: kCIInputScaleKey)
        contentFilters = [filter]
    }
}

private struct FisheyeWords: View {
    let time: Double
    let icons: Bool
    @ObservedObject private var style = Style.shared
    @ObservedObject private var player = NowPlaying.shared

    var body: some View {
        let s = style.v
        let words = player.words
        let index = words.lastIndex { $0.start <= time } ?? -1
        Canvas { context, size in
            guard index >= 0 else { return }
            draw(words, index, s, context, size)
        }
    }

    private func draw(_ words: [Word], _ index: Int, _ s: StyleValues, _ context: GraphicsContext, _ size: CGSize) {
        let fontSize = s.stageFontSize * 0.6
        let row = fontSize * 1.2
        // The column rolls up to each new word, rather than jumping.
        let roll = 1 - min(max((time - words[index].start) / 0.24, 0), 1)
        let scroll = Double(index) - roll * roll * roll
        let color = s.glowColor(player.palette, onStage: true)
        // Clear the glass during a long instrumental gap.
        let untilNext = index + 1 < words.count ? words[index + 1].start - time : .infinity
        let quiet = untilNext > 1.5 ? min(max((time - words[index].end - 3) / 0.6, 0), 1) : 0
        let reach = Int(size.height / 2 / row) + 2

        for i in max(0, index - reach)...min(words.count - 1, index + reach) {
            let y = (Double(i) - scroll) * row
            let fade = max(0, 1 - abs(y) / (size.height * 0.5))
            let emphasis = i == index ? 1 : i < index ? 0.5 : 0.24
            let opacity = emphasis * (0.25 + 0.75 * fade) * (1 - quiet)
            guard opacity > 0 else { continue }

            var line = Text(s.display(words[i].text)).font(s.font(size: fontSize)).tracking(s.tracking)
            if icons, let symbol = WordIcons.symbol(for: words[i].text) {
                let icon = Text(Image(systemName: symbol)).font(.system(size: fontSize * 0.62, weight: .bold))
                line = noise(i, 4) < 0.5 ? icon + Text("  ") + line : line + Text("  ") + icon
            }
            var text = context.resolve(line)
            text.shading = .color(color)
            let measured = text.measure(in: CGSize(width: 100_000, height: 100_000))

            var layer = context
            layer.opacity = opacity
            layer.translateBy(x: size.width / 2, y: size.height / 2 + y)
            let fit = min(1, size.width * 0.86 / max(measured.width, 1))
            layer.scaleBy(x: fit, y: fit)
            layer.draw(text, at: .zero, anchor: .center)
        }
    }
}
