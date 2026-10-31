import Foundation

// MARK: - Beat clock

/// Counts beats so the background lights can be carried along by the music. With the music audible these are the
/// real kick drum; otherwise sung words stand in, with a steady pulse through instrumentals.
final class BeatClock {
    static let shared = BeatClock()

    struct Beat {
        let index: Int
        let age: Double
    }

    private var hits: [(index: Int, date: Date)] = []
    private var count = 0
    private var lastDate = Date.distantPast
    private var lastAudioBeat = Date.distantPast
    private var lastWordPulse = 0.0

    /// Like SceneDirector, this only acts once per date, so every layer drawing the same frame agrees.
    func update(date: Date, time: Double) {
        guard date > lastDate else { return }
        lastDate = date
        let player = NowPlaying.shared
        if Style.shared.v.audioReactive, let audio = AudioPulse.shared.snapshot() {
            if audio.lastBeat > lastAudioBeat {
                lastAudioBeat = audio.lastBeat
                hit(audio.lastBeat)
            }
            return
        }
        let pulse = player.wordPulse(at: time)
        let since = date.timeIntervalSince(hits.last?.date ?? .distantPast)
        if (pulse > lastWordPulse + 0.2 && since > 0.18) || (player.isPlaying && since > 0.75) { hit(date) }
        lastWordPulse = pulse
    }

    private func hit(_ date: Date) {
        count += 1
        hits.append((count, date))
        if hits.count > 4 { hits.removeFirst() }
    }

    /// The latest beats, oldest first.
    func recent(at date: Date) -> [Beat] {
        hits.map { Beat(index: $0.index, age: max(0, date.timeIntervalSince($0.date))) }
    }

    /// Distance travelled at one unit per beat, each step gliding to a stop.
    func travel(at date: Date) -> Double {
        recent(at: date).reduce(Double(count)) { total, beat in
            total - pow(1 - min(beat.age / 0.4, 1), 3)
        }
    }
}
