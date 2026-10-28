import AppKit
import SwiftUI

// MARK: - Word icons

/// SF Symbols shown beside matching words in the word stack.
enum WordIcons {
    private static let groups: [(String, [String])] = [
        ("heart.fill", ["love", "loved", "loving", "lover", "heart", "need", "needed", "want", "adore"]),
        ("heart.slash.fill", ["broken", "heartbreak", "heartbroken", "hate"]),
        ("person.fill", ["you", "your", "you're", "yours", "u", "him", "her", "she", "he", "somebody", "someone"]),
        ("person.2.fill", ["we", "us", "together", "friends", "everybody", "everyone"]),
        ("eye.fill", ["see", "seen", "saw", "look", "looking", "eyes", "eye", "watch", "watching"]),
        ("car.fill", ["car", "cars", "drive", "driving", "ride", "riding"]),
        ("clock.fill", ["time", "minute", "minutes", "clock", "hour", "hours", "tonight", "today", "tomorrow"]),
        ("hourglass", ["wait", "waiting", "waited", "forever", "patience"]),
        ("figure.run", ["run", "running", "ran", "push", "go", "going", "gone", "chase", "away"]),
        ("wind", ["blow", "blew", "wind", "breathe", "breath", "air"]),
        ("dice.fill", ["chance", "chances", "luck", "lucky", "gamble", "risk"]),
        ("bubble.left.fill", ["tell", "telling", "told", "talk", "talking", "say", "said", "saying", "words", "call", "calling"]),
        ("phone.fill", ["phone", "ring", "ringing", "text"]),
        ("number", ["number", "numbers", "one", "two", "three"]),
        ("signature", ["name", "names", "sign"]),
        ("basketball.fill", ["ball", "ballin", "balling", "game", "play", "playing"]),
        ("moon.fill", ["night", "nights", "moon", "midnight", "dark", "darkness"]),
        ("sun.max.fill", ["sun", "day", "days", "shine", "shining", "sunshine", "morning", "summer"]),
        ("star.fill", ["star", "stars", "famous", "shine", "dream"]),
        ("moon.zzz.fill", ["sleep", "sleeping", "dreams", "dreaming", "bed"]),
        ("flame.fill", ["fire", "burn", "burning", "hot", "flame", "lit", "heat"]),
        ("drop.fill", ["cry", "crying", "cried", "tears", "tear", "rain", "raining"]),
        ("snowflake", ["cold", "ice", "freeze", "frozen", "winter", "snow"]),
        ("dollarsign.circle.fill", ["money", "cash", "rich", "pay", "paid", "dollar", "dollars", "bank"]),
        ("house.fill", ["home", "house", "room"]),
        ("globe.americas.fill", ["world", "earth", "everywhere", "planet"]),
        ("music.note", ["music", "song", "songs", "sing", "singing", "melody", "radio", "beat"]),
        ("figure.dance", ["dance", "dancing", "dancer", "move", "moving"]),
        ("airplane", ["fly", "flying", "flew", "plane", "high", "higher"]),
        ("cloud.fill", ["sky", "cloud", "clouds", "heaven", "above"]),
        ("lightbulb.fill", ["light", "lights", "idea", "bright"]),
        ("sparkles", ["magic", "god", "pray", "praying", "angel", "miracle", "beautiful", "stunning"]),
        ("crown.fill", ["king", "queen", "crown", "royal", "boss"]),
        ("key.fill", ["key", "keys", "open", "unlock"]),
        ("lock.fill", ["lock", "locked", "safe", "secret", "secrets"]),
        ("building.2.fill", ["city", "town", "streets", "street", "downtown"]),
        ("road.lanes", ["road", "highway", "way", "miles", "mile"]),
        ("party.popper.fill", ["party", "celebrate", "club", "crazy", "wild"]),
        ("gift.fill", ["gift", "present", "give", "gave"]),
        ("water.waves", ["water", "ocean", "sea", "wave", "waves", "river", "drown", "drowning"]),
        ("brain.head.profile", ["mind", "think", "thinking", "thought", "head", "remember", "forget"]),
        ("hand.raised.fill", ["hand", "hands", "hold", "holding", "touch", "stop"]),
        ("hand.point.up.left.fill", ["swish", "point", "this", "that"]),
        ("bolt.fill", ["power", "electric", "shock", "lightning", "fast"]),
        ("mouth.fill", ["kiss", "kissing", "lips", "mouth"]),
        ("camera.fill", ["picture", "pictures", "photo", "camera"]),
        ("airpods", ["listen", "listening", "hear", "heard"]),
        ("door.left.hand.open", ["door", "leave", "leaving", "left", "goodbye", "bye"]),
        ("arrow.up.circle.fill", ["up", "rise", "rising", "top"]),
        ("arrow.down.circle.fill", ["down", "fall", "falling", "fell", "low"]),
        ("exclamationmark.circle.fill", ["never", "no", "don't", "can't", "won't"]),
        ("checkmark.circle.fill", ["yes", "yeah", "right", "okay", "ok", "true"]),
        ("questionmark.circle.fill", ["why", "what", "how", "who", "where", "when"]),
    ]

    private static let map: [String: String] = {
        var map: [String: String] = [:]
        for (symbol, words) in groups {
            for word in words where map[word] == nil { map[word] = symbol }
        }
        return map
    }()

    private static var cache: [String: String?] = [:]

    static func symbol(for word: String) -> String? {
        if let hit = cache[word] { return hit }
        let symbol = lookup(word)
        cache[word] = symbol
        return symbol
    }

    private static func lookup(_ word: String) -> String? {
        let key = word.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.symbols).subtracting(["'"]))
            .trimmingCharacters(in: CharacterSet(charactersIn: "'"))
        return map[key]
    }
}

// MARK: - Word stack (one word at a time, Verci-style)

/// Stable pseudo-random value in 0..<1 per word, so a word keeps its size and position while on screen.
func noise(_ index: Int, _ salt: Int) -> Double {
    var x = UInt64(truncatingIfNeeded: index &* 2_654_435_761 &+ salt &* 40_503 &+ 0x9E37)
    x ^= x >> 13
    x = x &* 0x5BD1_E995
    x ^= x >> 15
    return Double(x % 10_000) / 10_000
}

private func clamp01(_ x: Double) -> Double { min(max(x, 0), 1) }

private func easeOutBack(_ x: Double) -> Double {
    let c1 = 1.70158, c3 = c1 + 1
    return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
}

struct StackWord: View {
    let word: Word
    let index: Int
    let current: Int
    let time: Double
    @ObservedObject private var style = Style.shared
    @ObservedObject private var player = NowPlaying.shared

    var body: some View {
        let s = style.v
        let sizes = [0.42, 0.6, 0.8, 1.0]
        let size = s.stageFontSize * sizes[Int(noise(index, 1) * Double(sizes.count))]
        let string = s.display(word.text)
        let symbol = s.stageIcons ? WordIcons.symbol(for: word.text) : nil
        let iconFirst = noise(index, 4) < 0.5

        HStack(spacing: size * 0.18) {
            if let symbol, iconFirst { icon(symbol, size) }
            label(string, size, s)
            if let symbol, !iconFirst { icon(symbol, size) }
        }
        .shadow(color: .black.opacity(0.35), radius: size * 0.08, y: size * 0.02)
        .rotationEffect(.degrees((noise(index, 3) - 0.5) * 5))
        .offset(x: (noise(index, 2) - 0.5) * size * 1.1)
        .opacity(index > current ? 0.22 : 1)
        .blur(radius: index > current ? size * 0.03 : 0)
    }

    private func icon(_ symbol: String, _ size: Double) -> some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .bold))
            .foregroundStyle(boxColor)
            .opacity(index <= current ? 1 : 0)
    }

    @ViewBuilder
    private func label(_ string: String, _ size: Double, _ s: StyleValues) -> some View {
        let text = Text(string).font(s.font(size: size)).tracking(s.tracking)
            .lineLimit(1).minimumScaleFactor(0.3)
        if index == current && s.stackStyle == "effect" {
            WordView(word: word, index: index, time: time, active: true, size: size, connects: false,
                     line: index < player.wordLines.count ? player.wordLines[index] : 0)
                .padding(size * 0.1)
        } else if index == current {
            // Highlighter box sweeps across the word as it's sung, then the word pops slightly.
            let progress = word.progress(at: time)
            let appear = clamp01((time - word.start) / 0.3)
            let edge = clamp01(progress * 1.08)
            let soft = clamp01(progress * 1.08 - 0.08)
            let mask = LinearGradient(stops: [.init(color: .white, location: soft), .init(color: .clear, location: edge)],
                                      startPoint: .leading, endPoint: .trailing)
            text.foregroundStyle(mutedColor)
                .padding(.horizontal, size * 0.1)
                .padding(.vertical, size * 0.1)
                .overlay {
                    ZStack {
                        Rectangle().fill(boxColor)
                        text.foregroundStyle(boxTextColor)
                    }
                    .mask(mask)
                }
                .scaleEffect(0.82 + 0.18 * easeOutBack(appear))
                .shadow(color: boxColor.opacity(s.glow * 0.8), radius: size * 0.25 * s.glow)
        } else {
            text.foregroundStyle(mutedColor)
                .padding(.horizontal, size * 0.1)
                .padding(.vertical, size * 0.1)
        }
    }

    private var boxColor: Color {
        switch style.v.colorMode {
        case "white": return .white
        case "custom": return Color(hex: style.v.customHex)
        default:
            // Vivid, slightly deep version of the main album colour so white text pops on it.
            let c = player.palette[0].usingColorSpace(.deviceRGB) ?? player.palette[0]
            return Color(nsColor: NSColor(hue: c.hueComponent, saturation: max(c.saturationComponent, 0.75),
                                          brightness: 0.82, alpha: 1))
        }
    }

    private var boxTextColor: Color {
        style.v.colorMode == "white" ? .black : .white
    }

    /// Already-sung words: the album's second colour, slightly darkened.
    private var mutedColor: Color {
        switch style.v.colorMode {
        case "white": return Color.white.opacity(0.55)
        case "custom":
            let c = NSColor(Color(hex: style.v.customHex))
            return Color(nsColor: c.blended(withFraction: 0.35, of: .black) ?? c)
        default:
            // Light tint of the album's second colour, readable on the dark backdrop.
            let c = player.palette[player.palette.count > 1 ? 1 : 0]
            return Color(nsColor: c.blended(withFraction: 0.35, of: .white) ?? c)
        }
    }
}

struct WordStackView: View {
    let time: Double
    let date: Date
    @ObservedObject private var style = Style.shared
    @ObservedObject private var player = NowPlaying.shared

    var body: some View {
        let s = style.v
        let words = player.words
        let index = words.lastIndex { $0.start <= time } ?? -1
        let from = max(0, index - 2)
        let to = min(words.count, index + 2)
        let t = date.timeIntervalSinceReferenceDate

        ZStack {
            if isInstrumental(words, index) {
                Image(systemName: "music.note")
                    .font(.system(size: s.stageFontSize * 0.6, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .scaleEffect(1 + 0.06 * sin(t * 3))
                    .transition(.opacity)
            } else {
                VStack(spacing: s.stageFontSize * 0.02) {
                    ForEach(from..<max(from, to), id: \.self) { i in
                        StackWord(word: words[i], index: i, current: index, time: time)
                            .transition(.asymmetric(
                                insertion: .modifier(active: Zoom(scale: 0.7, blur: 12, opacity: 0), identity: .identity)
                                    .combined(with: .offset(y: s.stageFontSize * 0.5)),
                                removal: .modifier(active: Zoom(scale: 0.85, blur: 16, opacity: 0), identity: .identity)
                                    .combined(with: .offset(y: -s.stageFontSize * 0.4))))
                    }
                }
                .frame(minWidth: s.lyricsBacking == "none" ? 0 : s.stageFontSize * 4)
                .modifier(LyricsBacking(kind: s.lyricsBacking, size: s.stageFontSize * 0.6))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Flatten the words (with their shadows and glow) into one GPU-rendered layer per frame.
        .drawingGroup()
        // The whole wall drifts slowly in 3D.
        .rotation3DEffect(.degrees(s.stageDrift ? sin(t * 0.35) * 9 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
        .rotation3DEffect(.degrees(s.stageDrift ? cos(t * 0.27) * 6 : 0), axis: (x: 1, y: 0, z: 0), perspective: 0.45)
        .animation(.spring(response: 0.42, dampingFraction: 1 - s.bounce * 0.5), value: index)
    }

    /// Long gap between sung words: show a pulsing note instead of a stale word.
    private func isInstrumental(_ words: [Word], _ index: Int) -> Bool {
        guard index >= 0 else { return false }
        let sinceEnd = time - words[index].end
        let untilNext = index + 1 < words.count ? words[index + 1].start - time : .infinity
        return sinceEnd > 3 && untilNext > 1.5
    }
}
