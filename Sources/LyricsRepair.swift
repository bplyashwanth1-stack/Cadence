import Foundation

// MARK: - Lyrics repair

/// Some LRCLIB uploads are timed but broken: lines missing, or Telugu/Hindi run through a converter that chops
/// word endings ("Gundelon premumullula" for "Gundelona prema mullula"). LRCLIB often also has the complete,
/// correct lyrics untimed. This matches the correct lines to the broken timed ones, borrows their timestamps,
/// fits the missing lines into the gaps, and returns a fixed LRC — or nil when the timed version is fine or the
/// two don't look like the same song.
enum LyricsRepair {
    private struct Timed {
        let time: Double
        let text: String
    }

    static func repair(synced: String, plain: String) -> String? {
        let timed = LRC.parse(synced).map { Timed(time: $0.start, text: $0.words.map(\.text).joined(separator: " ")) }
        let sung = timed.filter { !$0.text.isEmpty }
        let lines = plain.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !($0.hasPrefix("[") && $0.hasSuffix("]")) }  // drop "[Chorus]" labels
        guard sung.count >= 5, lines.count >= 5 else { return nil }

        let sungKeys = sung.map { key($0.text) }
        let lineKeys = lines.map { key($0) }

        // Best monotonic pairing of timed lines to correct lines (each used at most once, order kept).
        let n = sung.count, m = lines.count
        var score = [[Double]](repeating: [Double](repeating: 0, count: m + 1), count: n + 1)
        for i in 1...n {
            for j in 1...m {
                let sim = similarity(sungKeys[i - 1], lineKeys[j - 1])
                let pair = sim >= 0.45 ? score[i - 1][j - 1] + sim : -1
                score[i][j] = max(score[i - 1][j], score[i][j - 1], pair)
            }
        }
        var pairs: [(sung: Int, line: Int)] = []
        var i = n, j = m
        while i > 0 && j > 0 {
            let sim = similarity(sungKeys[i - 1], lineKeys[j - 1])
            if sim >= 0.45 && abs(score[i][j] - (score[i - 1][j - 1] + sim)) < 1e-9 {
                pairs.append((i - 1, j - 1)); i -= 1; j -= 1
            } else if score[i - 1][j] >= score[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }
        pairs.reverse()

        // Same song, and nothing lost? The output keeps only the correct lines, so nearly every timed line must
        // be among them — otherwise a lyrics page that skips a repeated chorus would cost lines.
        guard Double(pairs.count) >= Double(n) * 0.8 else { return nil }
        // Worth repairing? Lines missing, or the matched text noticeably different (mangled or another script).
        let averageSim = pairs.map { similarity(sungKeys[$0.sung], lineKeys[$0.line]) }.reduce(0, +) / Double(pairs.count)
        let nativeScript = lines.contains { $0.unicodeScalars.contains { $0.value > 0x24F } }
        let syncedLatin = !sung.contains { $0.text.unicodeScalars.contains { $0.value > 0x24F } }
        guard Double(pairs.count) < Double(m) * 0.85 || averageSim < 0.9 || (nativeScript && syncedLatin) else {
            return nil
        }

        // Keep the script the timed version was in: Latin timed lyrics get the correct lines in Latin letters.
        func shown(_ line: String) -> String { syncedLatin ? latin(line) : line }

        // Timestamps for every correct line: matched ones borrow theirs, the rest fill the gaps between.
        let gaps = zip(sung, sung.dropFirst()).map { $1.time - $0.time }.sorted()
        let typical = gaps.isEmpty ? 4 : min(max(gaps[gaps.count / 2], 2), 6)
        var times = [Double?](repeating: nil, count: m)
        for pair in pairs { times[pair.line] = sung[pair.sung].time }
        guard let firstAnchor = times.firstIndex(where: { $0 != nil }) else { return nil }
        for k in stride(from: firstAnchor - 1, through: 0, by: -1) {
            times[k] = max(0, times[k + 1]! - typical)
        }
        var k = firstAnchor + 1
        while k < m {
            guard times[k] == nil else { k += 1; continue }
            let start = times[k - 1]!
            let next = (k..<m).first { times[$0] != nil }
            if let next {
                // Spread the missing lines evenly between the surrounding timed lines.
                let step = (times[next]! - start) / Double(next - k + 1)
                for f in k..<next { times[f] = start + step * Double(f - k + 1) }
                k = next
            } else {
                for f in k..<m { times[f] = start + typical * Double(f - k + 1) }
                k = m
            }
        }

        // Keep the timed version's instrumental breaks where they don't land inside a line.
        var out = (0..<m).map { (time: times[$0]!, text: shown(lines[$0])) }
        for gap in timed where gap.text.isEmpty {
            let before = out.last { $0.time <= gap.time }
            let after = out.first { $0.time > gap.time }
            if let before, let after, after.time - gap.time > 3, gap.time - before.time > 2 {
                out.append((gap.time, ""))
            }
        }
        out.sort { $0.time < $1.time }
        Log.write("lyrics repaired: \(pairs.count) of \(n) timed lines matched to \(m) correct lines")
        return out.map { line in
            let minutes = Int(line.time) / 60
            let seconds = line.time - Double(minutes * 60)
            return String(format: "[%02d:%05.2f] %@", minutes, seconds, line.text)
        }.joined(separator: "\n")
    }

    /// Indian scripts in English letters, keeping word endings (Telugu words end in vowels; Hindi's dropped
    /// final "a" is handled by Romanizer). Capitalised like a lyric line.
    private static func latin(_ line: String) -> String {
        let devanagari = line.unicodeScalars.contains { (0x0900...0x097F).contains($0.value) }
        let text = devanagari ? Romanizer.latin(line) : Romanizer.casual(line)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// A rough sound-alike key: Latin letters only, doubled letters collapsed, so "pichchi"/"picchi" and
    /// "premumullula"/"premamullula" come out close.
    private static func key(_ text: String) -> [Character] {
        let letters = latin(text).lowercased().filter(\.isLetter)
        var out: [Character] = []
        for c in letters where out.last != c { out.append(c) }
        return out
    }

    /// Dice similarity of letter pairs, 0...1.
    private static func similarity(_ a: [Character], _ b: [Character]) -> Double {
        guard a.count > 1, b.count > 1 else { return a == b ? 1 : 0 }
        var bigrams: [String: Int] = [:]
        for i in 0..<(a.count - 1) { bigrams[String([a[i], a[i + 1]]), default: 0] += 1 }
        var shared = 0
        for i in 0..<(b.count - 1) {
            let pair = String([b[i], b[i + 1]])
            if let count = bigrams[pair], count > 0 { shared += 1; bigrams[pair] = count - 1 }
        }
        return 2 * Double(shared) / Double(a.count + b.count - 2)
    }
}
