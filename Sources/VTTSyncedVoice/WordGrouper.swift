import Foundation
import WhisperKit

enum WordGrouper {

    static let sentenceEndCharacters: Set<Character> = ["。", "？", "！", ".", "?", "!"]
    static let maxCharsPerEntry = 40

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
                let accumulatedText = currentWords.map(\.word).joined()
                let endsWithSentence = sentenceEndCharacters.contains(word.word.last ?? " ")
                let gapExceeds = gap >= gapThreshold
                let tooLong = accumulatedText.count >= maxCharsPerEntry

                shouldBreak = endsWithSentence || gapExceeds || tooLong
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
        let text = words.map(\.word).joined()
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return SubtitleEntry(
            startTime: Double(first.start),
            endTime: Double(last.end),
            text: text
        )
    }
}
