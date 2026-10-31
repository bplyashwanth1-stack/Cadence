import Foundation

// MARK: - Learned timing

/// Most lyric files only say when lines start, and not always exactly. While a song plays Cadence keeps the level of
/// the singing band; when it ends, this finds where each line really begins and shapes the words to when there was
/// singing, then writes it out as word-timed LRC for next time. It only moves lines it's sure about, since the band
/// also picks up instruments, and gives up on a song if too few lines are clear.
enum LearnedTiming {
    struct Result {
        let lrc: String
        let moved: Int
        let total: Int
        let shift: Double  // median, in seconds
    }

    private static let rate = 50.0  // samples per second

    /// `trace` is (song position, singing level). `offset` is what auto-sync was adding to the lyrics at the time.
    static func learn(lines: [LyricLine], trace: [(position: Double, level: Double)], offset: Double) -> Result? {
        let sung = lines.filter { !$0.words.isEmpty }
        guard sung.count >= 6, let lastEnd = sung.last?.end, !trace.isEmpty else { return nil }

        // Evenly spaced levels; -1 marks moments that weren't heard.
        let count = Int((lastEnd + 3) * rate)
        var levels = [Double](repeating: -1, count: count)
        for sample in trace {
            let i = Int(sample.position * rate)
            if i >= 0, i < count { levels[i] = sample.level }
        }
        var last = 0.0
        var gap = 0
        for i in levels.indices {
            if levels[i] >= 0 {
                last = levels[i]
                gap = 0
            } else if gap < 10 {  // a dropped sample or two isn't a hole
                levels[i] = last
                gap += 1
            }
        }
        let known = { (t: Double) -> Bool in
            let i = Int(t * rate)
            return i >= 0 && i < count && levels[i] >= 0
        }
        let smooth = levels.indices.map { i -> Double in
            let lo = max(0, i - 2), hi = min(count - 1, i + 2)
            let part = levels[lo...hi].filter { $0 >= 0 }
            return part.isEmpty ? 0 : part.reduce(0, +) / Double(part.count)
        }
        // How sharply the level rose over the last 120 ms.
        let onset = smooth.indices.map { i in i >= 6 ? max(0, smooth[i] - smooth[i - 6]) : 0 }

        // Where each line seems to begin, relative to where the file says.
        var deltas = [Double?](repeating: nil, count: sung.count)
        for (n, line) in sung.enumerated() {
            let expected = line.start - offset
            let reach = 0.6
            var from = expected - reach, to = expected + reach
            if n > 0 { from = max(from, sung[n - 1].start - offset + 0.25) }
            if n + 1 < sung.count { to = min(to, sung[n + 1].start - offset - 0.25) }
            guard to > from, known(from), known(to) else { continue }
            let a = Int(from * rate), b = min(Int(to * rate), count - 1)
            guard b > a else { continue }
            var best = 0.0, at = a
            for i in a...b {
                // Nearby rises count for more: the file is usually close.
                let d = abs(Double(i) / rate - expected)
                let score = onset[i] * (1 - 0.35 * d / reach)
                if score > best { (best, at) = (score, i) }
            }
            let mean = onset[a...b].reduce(0, +) / Double(b - a + 1)
            // Singing rises and stays up. Noise and drum hits rise too, but fall straight back.
            let before = smooth[max(0, at - 20)..<max(1, at - 4)]
            let after = smooth[min(at + 4, count - 1)..<min(at + 24, count)]
            guard !after.isEmpty else { continue }
            let held = after.reduce(0, +) / Double(after.count) - before.reduce(0, +) / Double(before.count)
            if onset[at] > 0.05, onset[at] > mean * 3, held > 0.12 { deltas[n] = Double(at) / rate - expected }
        }

        // A line far from its neighbours is more likely a drum hit than a real correction.
        var kept = deltas
        for n in deltas.indices {
            guard let delta = deltas[n] else { continue }
            let around = deltas[max(0, n - 3)...min(deltas.count - 1, n + 3)].compactMap { $0 }.sorted()
            if abs(delta - around[around.count / 2]) > 0.35 { kept[n] = nil }
        }
        let sure = kept.compactMap { $0 }
        guard sure.count >= 4, Double(sure.count) >= Double(sung.count) * 0.4 else { return nil }

        // Lines without a clear reading follow the ones around them.
        var filled = [Double](repeating: 0, count: sung.count)
        for n in sung.indices {
            if let delta = kept[n] {
                filled[n] = delta
                continue
            }
            let before = (0..<n).last { kept[$0] != nil }
            let after = ((n + 1)..<sung.count).first { kept[$0] != nil }
            switch (before, after) {
            case let (b?, a?):
                let f = Double(n - b) / Double(a - b)
                filled[n] = kept[b]! * (1 - f) + kept[a]! * f
            case let (b?, nil): filled[n] = kept[b]!
            case let (nil, a?): filled[n] = kept[a]!
            default: break
            }
        }

        var starts = sung.indices.map { sung[$0].start - offset + filled[$0] }
        for n in starts.indices.dropFirst() { starts[n] = max(starts[n], starts[n - 1] + 0.1) }

        // Write everything back out, instrumental gaps included.
        var out: [String] = []
        var index = 0
        for line in lines {
            guard !line.words.isEmpty else {
                let shift = index < filled.count ? filled[index] : filled.last ?? 0
                out.append(stamp(line.start - offset + shift, "[", "]"))
                continue
            }
            let span = max((line.words.last?.end ?? line.end) - line.start, 0.2)
            let start = starts[index]
            let limit = index + 1 < starts.count ? starts[index + 1] - 0.05 : start + span
            let end = min(start + span, limit)
            let times = wordStarts(line, span: span, start: start, end: end, smooth: smooth)
            var text = stamp(start, "[", "]")
            for (word, time) in zip(line.words, times) { text += stamp(time, "<", ">") + word.text + " " }
            out.append(text + stamp(end, "<", ">"))
            index += 1
        }
        let moves = sure.map(abs).sorted()
        return Result(lrc: out.joined(separator: "\n"), moved: sure.count, total: sung.count, shift: moves[moves.count / 2])
    }

    /// Word starts within the line: halfway between the even syllable timing and following the singing, so a held
    /// note or a breath moves the words along without one loud moment throwing them off.
    private static func wordStarts(_ line: LyricLine, span: Double, start: Double, end: Double, smooth: [Double]) -> [Double] {
        let a = max(0, Int(start * rate)), b = min(smooth.count - 1, Int(end * rate))
        guard b > a else {
            return line.words.map { start + ($0.start - line.start) / span * (end - start) }
        }
        var total = 0.0
        var running = [Double]()
        for i in a...b {
            total += 0.02 + smooth[i]
            running.append(total)
        }
        return line.words.map { word in
            let share = min(max((word.start - line.start) / span, 0), 1)
            let i = running.firstIndex { $0 >= share * total } ?? running.count - 1
            let followed = Double(i) / Double(max(running.count - 1, 1))
            return start + (share + followed) / 2 * (end - start)
        }
    }

    private static func stamp(_ time: Double, _ open: String, _ close: String) -> String {
        let t = max(time, 0)
        let minutes = Int(t) / 60
        return open + String(format: "%02d:%05.2f", minutes, t - Double(minutes * 60)) + close
    }
}
