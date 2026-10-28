import AppKit
import SwiftUI

// MARK: - Scene director (Auto background)

/// Decides when Auto cuts to the next scene. With the music audible it cuts like an editor: hard on a drop
/// (a big hit after a quiet stretch), on the first beat of each new four-line section, and every few beats in
/// the chorus. Without audio it falls back to cutting when a new section starts.
final class SceneDirector {
    static let shared = SceneDirector()

    private(set) var scene = 0
    private var cutAt = Date.distantPast
    private var bigCut = false
    private var lastDate = Date.distantPast
    private var trackID: String?
    private var section = 0
    private var sectionChangedAt = Date.distantPast
    private var lastBeatSeen = Date.distantPast
    private var levels: [Float] = []  // ~3 s of loudness at 30 fps

    /// Advances the director to `date`. Both stage layers call this with the same 30 fps date, and it only acts
    /// once per date, so they always agree on the scene.
    func update(date: Date, section newSection: Int, chorus: Bool) {
        guard date > lastDate else { return }
        lastDate = date
        let track = NowPlaying.shared.track?.id
        if track != trackID {
            trackID = track
            scene = 0
            cutAt = .distantPast
            levels = []
            section = newSection
        }
        if newSection != section {
            section = newSection
            sectionChangedAt = date
        }
        let since = date.timeIntervalSince(cutAt)
        let sectionDue = sectionChangedAt > cutAt

        guard Style.shared.v.audioReactive, let audio = AudioPulse.shared.snapshot() else {
            if sectionDue { cut(date, big: false) }
            return
        }
        levels.append(audio.level)
        if levels.count > 90 { levels.removeFirst(levels.count - 90) }

        let beat = audio.lastBeat > lastBeatSeen
        if beat { lastBeatSeen = audio.lastBeat }
        // A section change with no beat to land on (quiet bridge) still cuts after a moment.
        if sectionDue && date.timeIntervalSince(sectionChangedAt) > 1.2 && since > 2 {
            cut(date, big: false)
            return
        }
        guard beat, since > 1.5 else { return }
        let before = levels.prefix(max(levels.count - 15, 0))
        let quietBefore = before.count > 30 && before.reduce(0, +) / Float(before.count) < 0.4
        if quietBefore && audio.level > 0.7 {
            cut(date, big: true)  // the drop
        } else if sectionDue || (since > (chorus ? 3.5 : 10) && audio.bass > 0.7) {
            cut(date, big: false)
        }
    }

    private func cut(_ date: Date, big: Bool) {
        scene += 1
        cutAt = date
        bigCut = big
    }

    /// 1 right at a cut, decaying — drives the white flash and the zoom punch. A drop hits harder and longer.
    func flash(at date: Date) -> Double {
        let since = date.timeIntervalSince(cutAt)
        guard since >= 0 else { return 0 }
        return bigCut ? 1.4 * exp(-since * 2.5) : exp(-since * 4)
    }
}

// MARK: - Title card

/// When a new song starts, its title slams in big with the artist under it, like a music video's opening, then
/// gets out of the way before the first line is sung.
struct TitleCard: View {
    let date: Date
    let time: Double
    @ObservedObject private var style = Style.shared
    @ObservedObject private var player = NowPlaying.shared

    /// How long the card stays: through the intro up to just before the first line, between 3 and 8 seconds.
    /// Joining a song midway gets a short 3 s card.
    static func duration(_ player: NowPlaying) -> Double {
        guard player.trackStart.position < 3 else { return 3 }
        let firstLine = player.lyrics.first { !$0.words.isEmpty }?.start ?? 8
        return min(max(firstLine - player.trackStart.position - 0.6, 3), 8)
    }

    static func showing(_ player: NowPlaying, at date: Date) -> Bool {
        let age = date.timeIntervalSince(player.trackStart.date)
        return Style.shared.v.titleCard && player.track != nil && age >= 0 && age < duration(player)
    }

    var body: some View {
        if let track = player.track, Self.showing(player, at: date) {
            let s = style.v
            let age = date.timeIntervalSince(player.trackStart.date)
            let exit = min(max((age - (Self.duration(player) - 0.5)) / 0.5, 0), 1)
            let slam = min(age / 0.28, 1)
            let settle = min(max((age - 0.28) / 1.2, 0), 1)
            let accent = s.colorMode == "custom" ? Color(hex: s.customHex) : Color(nsColor: player.palette[0])
            let size = s.stageFontSize * 0.62

            VStack(spacing: size * 0.18) {
                if let art = player.artwork {
                    Image(nsImage: art)
                        .resizable()
                        .aspectRatio(1, contentMode: .fill)
                        .frame(width: size * 1.3, height: size * 1.3)
                        .clipShape(RoundedRectangle(cornerRadius: size * 0.12, style: .continuous))
                        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
                        .scaleEffect(0.6 + 0.4 * easeOut(min(age / 0.4, 1)))
                        .opacity(min(age / 0.2, 1))
                }
                HStack(spacing: 12) {
                    Rectangle().fill(accent).frame(width: 40 * settle, height: 2)
                    Text("NOW PLAYING")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .tracking(4)
                        .foregroundStyle(Color.white.opacity(0.75))
                    Rectangle().fill(accent).frame(width: 40 * settle, height: 2)
                }
                .opacity(settle)
                Text(track.title)
                    .font(s.font(size: size))
                    .textCase(.uppercase)
                    .tracking(2 + 6 * settle)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.4)
                    .foregroundStyle(Color.white)
                    .shadow(color: accent.opacity(0.9), radius: size * 0.25)
                    .scaleEffect(1 + 1.2 * pow(1 - slam, 2))
                    .blur(radius: (1 - slam) * 10)
                    .opacity(slam)
                Text(track.artist)
                    .font(.system(size: size * 0.32, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .offset(y: (1 - settle) * 20)
                    .opacity(settle)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scaleEffect(1 + 0.15 * exit)
            .blur(radius: exit * 16)
            .opacity(1 - exit)
        }
    }

    private func easeOut(_ x: Double) -> Double {
        let c1 = 1.70158, c3 = c1 + 1
        return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
    }
}
