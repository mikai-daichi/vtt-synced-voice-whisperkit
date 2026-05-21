import Foundation
import WhisperKit

enum WordGrouper {

    static let sentenceEndCharacters: Set<Character> = ["。", "？", "！", ".", "?", "!"]

    static func group(
        words: [WordTiming],
        gapThreshold: Double = 0.5
    ) -> [SubtitleEntry] {
        guard !words.isEmpty else { return [] }

        var entries: [SubtitleEntry] = []
        var currentWords: [WordTiming] = []

        for (i, word) in words.enumerated() {
            currentWords.append(word)

            let shouldBreak: Bool
            if i == words.count - 1 {
                shouldBreak = true
            } else {
                let next = words[i + 1]
                let gap = Double(next.start - word.end)
                let endsWithSentence = sentenceEndCharacters.contains(word.word.last ?? " ")
                let gapExceeds = gap >= gapThreshold

                shouldBreak = endsWithSentence || gapExceeds
            }

            if shouldBreak, let entry = makeEntry(from: currentWords) {
                entries.append(entry)
                currentWords = []
            }
        }

        return entries
    }

    private static func makeEntry(from words: [WordTiming]) -> SubtitleEntry? {
        guard let first = words.first, let last = words.last else { return nil }
        let text = words.map(\.word).joined().trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return SubtitleEntry(
            startSeconds: Double(first.start),
            endSeconds: Double(last.end),
            text: text
        )
    }
}
