import Testing
import WhisperKit
@testable import VTTSyncedVoice

private func word(_ w: String, start: Float, end: Float) -> WordTiming {
    WordTiming(word: w, tokens: [], start: start, end: end, probability: 1.0)
}

@Suite("WordGrouper")
struct WordGrouperTests {

    @Test("空配列は空配列を返す")
    func emptyWordsReturnsEmpty() {
        let result = WordGrouper.group(words: [])
        #expect(result.isEmpty)
    }

    @Test("単語1つでエントリが1つ作られる")
    func singleWordSingleEntry() {
        let words = [word("hello", start: 1.0, end: 1.5)]
        let result = WordGrouper.group(words: words)
        #expect(result.count == 1)
        #expect(result[0].text == "hello")
        #expect(result[0].startSeconds == 1.0)
        #expect(result[0].endSeconds == 1.5)
    }

    @Test("gapThreshold以上の間隔で分割される（デフォルト0.5秒）")
    func splitOnGap() {
        let words = [
            word("前", start: 0.0, end: 0.5),
            word("後", start: 1.1, end: 1.5)  // gap = 0.6 ≥ 0.5
        ]
        let result = WordGrouper.group(words: words)
        #expect(result.count == 2)
        #expect(result[0].text == "前")
        #expect(result[1].text == "後")
    }

    @Test("gapThresholdより小さい間隔では分割されない")
    func noSplitOnSmallGap() {
        let words = [
            word("前", start: 0.0, end: 0.5),
            word("後", start: 0.8, end: 1.0)  // gap = 0.3 < 0.5
        ]
        let result = WordGrouper.group(words: words)
        #expect(result.count == 1)
        #expect(result[0].text == "前後")
    }

    @Test("カスタムgapThresholdが機能する")
    func customGapThreshold() {
        let words = [
            word("A", start: 0.0, end: 0.5),
            word("B", start: 0.9, end: 1.0)   // gap = 0.4
        ]
        let split = WordGrouper.group(words: words, gapThreshold: 0.3)
        #expect(split.count == 2)

        let merged = WordGrouper.group(words: words, gapThreshold: 0.5)
        #expect(merged.count == 1)
    }

    @Test("日本語句点（。）で分割される")
    func splitOnJapanesePeriod() {
        let words = [
            word("終わり。", start: 0.0, end: 1.0),
            word("次", start: 1.1, end: 1.5)
        ]
        let result = WordGrouper.group(words: words, gapThreshold: 2.0)
        #expect(result.count == 2)
        #expect(result[0].text == "終わり。")
    }

    @Test("感嘆符・疑問符で分割される（! ? ！ ？）")
    func splitOnExclamation() {
        for punctuation in ["!", "?", "！", "？"] {
            let words = [
                word("yes\(punctuation)", start: 0.0, end: 0.5),
                word("no", start: 0.6, end: 1.0)
            ]
            let result = WordGrouper.group(words: words, gapThreshold: 2.0)
            #expect(result.count == 2, "分割されるはず（句読点=\(punctuation)）")
        }
    }

    @Test("文字数がいくら長くても文字数では分割されない")
    func longTextNotSplit() {
        let longText = String(repeating: "あ", count: 100)
        let words = [
            word(longText, start: 0.0, end: 1.0),
            word("次", start: 1.05, end: 1.5)
        ]
        let result = WordGrouper.group(words: words, gapThreshold: 2.0)
        #expect(result.count == 1)
    }

    @Test("エントリのstartは最初の単語のstart、endは最後の単語のend")
    func entryTimestampFromFirstAndLastWord() {
        let words = [
            word("A", start: 1.0, end: 1.2),
            word("B", start: 1.3, end: 1.6),
            word("C", start: 1.7, end: 2.0)
        ]
        let result = WordGrouper.group(words: words)
        #expect(result.count == 1)
        #expect(result[0].startSeconds == 1.0)
        #expect(result[0].endSeconds == 2.0)
    }

    @Test("スペースのみの単語はエントリが作られない")
    func whitespaceOnlyWordSkipped() {
        let words = [word("   ", start: 0.0, end: 0.5)]
        let result = WordGrouper.group(words: words)
        #expect(result.isEmpty)
    }
}
