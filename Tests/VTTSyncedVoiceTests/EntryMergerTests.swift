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

    @Test("句点なしのエントリが連続（閾値超） → 全部まとめて1エントリ")
    func noPunctuationMergesAll() {
        // 閾値（7文字）を超えるテキストは読点が挿入されない
        let entries = [
            entry("前半の部分テキスト", start: 0.0, end: 1.0),
            entry("後半の部分テキスト", start: 1.1, end: 2.0),
            entry("末尾の部分テキスト", start: 2.1, end: 3.0)
        ]
        let result = EntryMerger.merge(entries: entries)
        #expect(result.count == 1)
        #expect(result[0].text == "前半の部分テキスト後半の部分テキスト末尾の部分テキスト")
        #expect(result[0].startSeconds == 0.0)
        #expect(result[0].endSeconds == 3.0)
    }

    @Test("7文字以下の短文エントリ → 次のエントリと読点で接続される")
    func shortEntryGetsComma() {
        // "1つ目" は7文字以下なので次のエントリと読点で結合される
        let entries = [
            entry("1つ目", start: 0.0, end: 0.5),
            entry("VTTタイムスタンプ位置でクリップをカットします", start: 0.6, end: 2.0)
        ]
        let result = EntryMerger.merge(entries: entries)
        #expect(result.count == 1)
        #expect(result[0].text == "1つ目、VTTタイムスタンプ位置でクリップをカットします")
    }

    @Test("短文の後が読点始まりなら読点を重複挿入しない")
    func shortEntryNoDoubleComma() {
        let entries = [
            entry("2つ目、", start: 0.0, end: 0.5),
            entry("クリップを削除します", start: 0.6, end: 2.0)
        ]
        let result = EntryMerger.merge(entries: entries)
        #expect(result.count == 1)
        #expect(result[0].text == "2つ目、クリップを削除します")
    }

    @Test("複数の文が混在 → 文単位で正しく分割される")
    func multipleSentences() {
        let entries = [
            entry("最初の文の前半部分", start: 0.0, end: 1.0),
            entry("後半です。", start: 1.1, end: 2.0),
            entry("次の文の前半部分", start: 2.1, end: 3.0),
            entry("後半ですね。", start: 3.1, end: 4.0)
        ]
        let result = EntryMerger.merge(entries: entries)
        #expect(result.count == 2)
        #expect(result[0].text == "最初の文の前半部分後半です。")
        #expect(result[0].startSeconds == 0.0)
        #expect(result[0].endSeconds == 2.0)
        #expect(result[1].text == "次の文の前半部分後半ですね。")
        #expect(result[1].startSeconds == 2.1)
        #expect(result[1].endSeconds == 4.0)
    }

    @Test("「！」で文末と判定される")
    func exclamationMark() {
        let entries = [
            entry("すごいです", start: 0.0, end: 0.5),
            entry("！", start: 0.6, end: 1.0)
        ]
        let result = EntryMerger.merge(entries: entries)
        #expect(result.count == 1)
        #expect(result[0].text == "すごいです、！")  // "！" は1文字で短文 → 読点挿入
    }

    @Test("「？」で文末と判定される（8文字超）")
    func questionMarkFullWidth() {
        let entries = [
            entry("どうですか？", start: 0.0, end: 0.5),
        ]
        let result = EntryMerger.merge(entries: entries)
        #expect(result.count == 1)
        #expect(result[0].text == "どうですか？")
    }

    @Test("半角「!」「?」でも文末と判定される")
    func halfWidthPunctuation() {
        let excl = [entry("Yes!", start: 0.0, end: 0.5), entry("No way", start: 0.6, end: 1.0)]
        let r1 = EntryMerger.merge(entries: excl)
        #expect(r1.count == 2)   // "Yes!" でフラッシュ、"No way" は句点なし → 末尾フラッシュ
        #expect(r1[0].text == "Yes!")
        #expect(r1[1].text == "No way")

        let ques = [entry("Really?", start: 0.0, end: 0.5), entry("Yes indeed", start: 0.6, end: 1.0)]
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

    @Test("8文字超エントリのマージ後textが各エントリのtext結合と一致する")
    func mergedTextEqualsJoined() {
        // 短文閾値（7文字）を超えるテキストなら読点が挿入されない
        let entries = [
            entry("パート一つ目です", start: 0.0, end: 1.0),
            entry("パート二つ目です", start: 1.1, end: 2.0),
            entry("パート三つ目です。", start: 2.1, end: 3.0)
        ]
        let result = EntryMerger.merge(entries: entries)
        let expected = entries.map(\.text).joined()
        #expect(result[0].text == expected)
    }
}

@Suite("EntryMerger.applyBoundaries")
struct ApplyBoundariesTests {

    private func entry(_ text: String, start: Double = 0.0, end: Double = 1.0) -> SubtitleEntry {
        SubtitleEntry(startSeconds: start, endSeconds: end, text: text)
    }

    @Test("空配列は空を返す")
    func emptyReturnsEmpty() {
        #expect(EntryMerger.applyBoundaries(entries: [], endIndices: []).isEmpty)
    }

    @Test("末尾インデックスのみ → 全エントリが1つにまとまる（8文字超）")
    func allInOneGroup() {
        // 短文閾値を超えるテキストで読点挿入なしを確認
        let entries = [
            entry("テキスト部分その一", start: 0.0, end: 1.0),
            entry("テキスト部分その二", start: 1.1, end: 2.0),
            entry("テキスト部分その三", start: 2.1, end: 3.0)
        ]
        let result = EntryMerger.applyBoundaries(entries: entries, endIndices: [2])
        #expect(result.count == 1)
        #expect(result[0].text == "テキスト部分その一テキスト部分その二テキスト部分その三")
        #expect(result[0].startSeconds == 0.0)
        #expect(result[0].endSeconds == 3.0)
    }

    @Test("各インデックスで分割 → エントリ数が正しい（8文字超）")
    func splitAtEachIndex() {
        let entries = [
            entry("テキスト部分その一", start: 0.0, end: 1.0),
            entry("テキスト部分その二", start: 1.1, end: 2.0),
            entry("テキスト部分その三", start: 2.1, end: 3.0),
            entry("テキスト部分その四", start: 3.1, end: 4.0)
        ]
        let result = EntryMerger.applyBoundaries(entries: entries, endIndices: [1, 3])
        #expect(result.count == 2)
        #expect(result[0].text == "テキスト部分その一テキスト部分その二")
        #expect(result[0].startSeconds == 0.0)
        #expect(result[0].endSeconds == 2.0)
        #expect(result[1].text == "テキスト部分その三テキスト部分その四")
        #expect(result[1].startSeconds == 2.1)
        #expect(result[1].endSeconds == 4.0)
    }

    @Test("全インデックスで分割 → 元のエントリ数と同じ")
    func splitEveryEntry() {
        let entries = [
            entry("テキスト部分その一", start: 0.0, end: 1.0),
            entry("テキスト部分その二", start: 1.1, end: 2.0)
        ]
        let result = EntryMerger.applyBoundaries(entries: entries, endIndices: [0, 1])
        #expect(result.count == 2)
        #expect(result[0].text == "テキスト部分その一")
        #expect(result[1].text == "テキスト部分その二")
    }

    @Test("endIndices に範囲外インデックスが含まれても安全")
    func outOfRangeIndicesIgnored() {
        let entries = [
            entry("テキスト部分その一", start: 0.0, end: 1.0),
            entry("テキスト部分その二", start: 1.1, end: 2.0)
        ]
        let result = EntryMerger.applyBoundaries(entries: entries, endIndices: [1, 99])
        #expect(result.count == 1)
        #expect(result[0].text == "テキスト部分その一テキスト部分その二")
    }
}
