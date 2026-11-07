import Foundation
import NaturalLanguage
import SwiftUI
#if canImport(Translation)
import Translation
#endif

// MARK: - Translated lyrics

/// A translation of each lyric line into your Mac's language, made on this Mac with Apple's translation (macOS
/// 15 or later) when a song's lyrics are in another language. Worked out once per song.
final class LyricTranslator: ObservableObject {
    static let shared = LyricTranslator()

    @Published private(set) var lines: [Int: String] = [:]
    @Published private(set) var trackID: String?
    /// The language pair for the song waiting to be translated; the host view starts a session for it.
    @Published var request: (source: Locale.Language, target: Locale.Language)?

    /// The translation of line `index` of the playing song, if there is one.
    func line(_ index: Int) -> String? {
        trackID == NowPlaying.shared.track?.id ? lines[index] : nil
    }

    /// Called as lyrics arrive: asks for a translation if the song's language isn't yours.
    func prepare() {
        let player = NowPlaying.shared
        guard Style.shared.v.translate, let id = player.track?.id, id != trackID, !player.lyrics.isEmpty else { return }
        trackID = id
        lines = [:]
        let text = player.lyrics.map { $0.words.map(\.text).joined(separator: " ") }.joined(separator: "\n")
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let code = recognizer.dominantLanguage?.rawValue else { return }
        let source = Locale.Language(identifier: code)
        let target = Locale.current.language
        guard source.languageCode != target.languageCode else { return }
        request = (source, target)
    }

    func store(_ translated: [Int: String], for id: String) {
        guard id == trackID else { return }
        lines = translated
    }
}

/// Invisible view that runs the translation session; it has to live in a window to work.
struct TranslationHost: View {
    @ObservedObject private var translator = LyricTranslator.shared
    @ObservedObject private var player = NowPlaying.shared
    @ObservedObject private var style = Style.shared

    var body: some View {
        let lyricsKey = "\(player.track?.id ?? "")-\(player.lyrics.count)-\(style.v.translate)"
        Group {
            #if canImport(Translation)
            if #available(macOS 15.0, *) {
                SessionRunner()
            }
            #endif
        }
        .frame(width: 0, height: 0)
        .onAppear { translator.prepare() }
        .onChange(of: lyricsKey) { _, _ in translator.prepare() }
    }
}

#if canImport(Translation)
@available(macOS 15.0, *)
private struct SessionRunner: View {
    @ObservedObject private var translator = LyricTranslator.shared
    @ObservedObject private var player = NowPlaying.shared

    var body: some View {
        let configuration = translator.request.map {
            TranslationSession.Configuration(source: $0.source, target: $0.target)
        }
        Color.clear
            .translationTask(configuration) { session in
                guard let id = translator.trackID else { return }
                let lyrics = player.lyrics
                let requests = lyrics.enumerated().compactMap { i, line -> TranslationSession.Request? in
                    let text = line.words.map(\.text).joined(separator: " ")
                    return text.isEmpty ? nil : TranslationSession.Request(sourceText: text, clientIdentifier: "\(i)")
                }
                guard let responses = try? await session.translations(from: requests) else {
                    Log.write("lyric translation unavailable")
                    return
                }
                var translated: [Int: String] = [:]
                for response in responses {
                    if let i = response.clientIdentifier.flatMap(Int.init), response.targetText != response.sourceText {
                        translated[i] = response.targetText
                    }
                }
                await MainActor.run { translator.store(translated, for: id) }
            }
    }
}
#endif

/// The current line's translation, small and quiet under the lyrics.
struct TranslationLine: View {
    let time: Double
    @ObservedObject private var translator = LyricTranslator.shared
    @ObservedObject private var player = NowPlaying.shared
    @ObservedObject private var style = Style.shared

    var body: some View {
        let index = player.lyrics.lastIndex { $0.start <= time }
        if style.v.translate, let index, let text = translator.line(index) {
            Text(text)
                .font(.system(size: max(15, style.v.stageFontSize * 0.16), weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.7))
                .shadow(color: .black.opacity(0.5), radius: 6)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 40)
                .id(index)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: index)
        }
    }
}
