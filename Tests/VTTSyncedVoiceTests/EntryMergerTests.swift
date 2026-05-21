import Testing
@testable import VTTSyncedVoice

@Suite("EntryMerger")
struct EntryMergerTests {

    private func entry(_ text: String, start: Double = 0.0, end: Double = 1.0) -> SubtitleEntry {
        SubtitleEntry(startSeconds: start, endSeconds: end, text: text)
    }

    @Test("空配列は空を返す")
    func emptyReturnsEmpty() {
        #expect(EntryMerger.merge(entries: []).isEmpty)
    }

    @Test("句点で終わるエントリが1つ → そのまま1エントリを返す")
    func singleSentenceEntry() {
        let entries = [entry("こんにちは。", start: 0.0, end: 1.0)]
        let result = EntryMerger.merge(entries: entries)
        #expect(result.count == 1)
        #expect(result[0].text == "こんにちは。")
    }

    @Test("句点で2エントリに分かれた文章 → 1エントリにマージされる（問題ケース）")
    func splitSentenceMerged() {
        let entries = [
            entry("ファイナルカットプロエクステ", start: 1.0, end: 3.0),
            entry("ンションとしても使用できます。", start: 3.1, end: 5.0)
        ]
        let result = EntryMerger.merge(entries: entries)
        #expect(result.count == 1)
        #expect(result[0].text == "ファイナルカットプロエクステンションとしても使用できます。")
        #expect(result[0].startSeconds == 1.0)
        #expect(result[0].endSeconds == 5.0)
    }

    @Test("句点なしのエントリが連続 → 全部まとめて1エントリ")
    func noPunctuationMergesAll() {
        let entries = [
            entry("A", start: 0.0, end: 1.0),
            entry("B", start: 1.1, end: 2.0),
            entry("C", start: 2.1, end: 3.0)
        ]
        let result = EntryMerger.merge(entries: entries)
        #expect(result.count == 1)
        #expect(result[0].text == "ABC")
        #expect(result[0].startSeconds == 0.0)
        #expect(result[0].endSeconds == 3.0)
    }

    @Test("複数の文が混在 → 文単位で正しく分割される")
    func multipleSentences() {
        let entries = [
            entry("最初の文の前半", start: 0.0, end: 1.0),
            entry("後半です。", start: 1.1, end: 2.0),
            entry("次の文の前半", start: 2.1, end: 3.0),
            entry("後半ですね。", start: 3.1, end: 4.0)
        ]
        let result = EntryMerger.merge(entries: entries)
        #expect(result.count == 2)
        #expect(result[0].text == "最初の文の前半後半です。")
        #expect(result[0].startSeconds == 0.0)
        #expect(result[0].endSeconds == 2.0)
        #expect(result[1].text == "次の文の前半後半ですね。")
        #expect(result[1].startSeconds == 2.1)
        #expect(result[1].endSeconds == 4.0)
    }

    @Test("「！」で文末と判定される")
    func exclamationMark() {
        let entries = [
            entry("すごい", start: 0.0, end: 0.5),
            entry("です！", start: 0.6, end: 1.0)
        ]
        let result = EntryMerger.merge(entries: entries)
        #expect(result.count == 1)
        #expect(result[0].text == "すごいです！")
    }

    @Test("「？」で文末と判定される")
    func questionMarkFullWidth() {
        let entries = [
            entry("どうです", start: 0.0, end: 0.5),
            entry("か？", start: 0.6, end: 1.0)
        ]
        let result = EntryMerger.merge(entries: entries)
        #expect(result.count == 1)
        #expect(result[0].text == "どうですか？")
    }

    @Test("半角「!」「?」でも文末と判定される")
    func halfWidthPunctuation() {
        let excl = [entry("Yes!", start: 0.0, end: 0.5), entry("No", start: 0.6, end: 1.0)]
        let r1 = EntryMerger.merge(entries: excl)
        #expect(r1.count == 2)   // "Yes!" でフラッシュ、"No" は句点なし → 末尾フラッシュ
        #expect(r1[0].text == "Yes!")
        #expect(r1[1].text == "No")

        let ques = [entry("Really?", start: 0.0, end: 0.5), entry("Yes", start: 0.6, end: 1.0)]
        let r2 = EntryMerger.merge(entries: ques)
        #expect(r2.count == 2)
        #expect(r2[0].text == "Really?")
    }

    @Test("句点で終わる単独エントリのタイムスタンプが保持される")
    func timestampPreserved() {
        let entries = [entry("テスト。", start: 1.5, end: 3.7)]
        let result = EntryMerger.merge(entries: entries)
        #expect(result[0].startSeconds == 1.5)
        #expect(result[0].endSeconds == 3.7)
    }

    @Test("マージ後のtextが各エントリのtext結合と一致する")
    func mergedTextEqualsJoined() {
        let entries = [
            entry("パート1", start: 0.0, end: 1.0),
            entry("パート2", start: 1.1, end: 2.0),
            entry("パート3。", start: 2.1, end: 3.0)
        ]
        let result = EntryMerger.merge(entries: entries)
        let expected = entries.map(\.text).joined()
        #expect(result[0].text == expected)
    }
}
