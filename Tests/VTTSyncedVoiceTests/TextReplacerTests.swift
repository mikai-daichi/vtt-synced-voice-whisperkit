import Testing
import Foundation
@testable import VTTSyncedVoice

@Suite("TextReplacer")
struct TextReplacerTests {

    // ── apply() ────────────────────────────────────────────────

    @Test("空ルールは変更なし")
    func emptyRulesReturnsUnchanged() {
        let entries = [SubtitleEntry(startSeconds: 0, endSeconds: 1, text: "ファイナルカットプロ")]
        let result = TextReplacer.apply(rules: [], to: entries)
        #expect(result[0].text == "ファイナルカットプロ")
    }

    @Test("基本置換が複数エントリに適用される")
    func basicReplacementAcrossEntries() {
        let rules = [TextReplacer.Rule(from: "ファイナルカットプロ", to: "Final Cut Pro")]
        let entries = [
            SubtitleEntry(startSeconds: 0, endSeconds: 1, text: "ファイナルカットプロを使います"),
            SubtitleEntry(startSeconds: 1, endSeconds: 2, text: "ファイナルカットプロは便利"),
        ]
        let result = TextReplacer.apply(rules: rules, to: entries)
        #expect(result[0].text == "Final Cut Proを使います")
        #expect(result[1].text == "Final Cut Proは便利")
    }

    @Test("複数ルールが全て適用される")
    func multipleRulesAllApplied() {
        let rules = [
            TextReplacer.Rule(from: "ファイナルカットプロ", to: "Final Cut Pro"),
            TextReplacer.Rule(from: "ウィスパーキット", to: "WhisperKit"),
        ]
        let entries = [SubtitleEntry(startSeconds: 0, endSeconds: 1, text: "ファイナルカットプロとウィスパーキット")]
        let result = TextReplacer.apply(rules: rules, to: entries)
        #expect(result[0].text == "Final Cut ProとWhisperKit")
    }

    @Test("連鎖置換: 前のルールの出力が次のルールの入力になる")
    func chainReplacement() {
        let rules = [
            TextReplacer.Rule(from: "A", to: "B"),
            TextReplacer.Rule(from: "B", to: "C"),
        ]
        let entries = [SubtitleEntry(startSeconds: 0, endSeconds: 1, text: "A")]
        let result = TextReplacer.apply(rules: rules, to: entries)
        #expect(result[0].text == "C")
    }

    @Test("タイムスタンプは変更されない")
    func timestampsPreserved() {
        let rules = [TextReplacer.Rule(from: "旧", to: "新")]
        let entries = [SubtitleEntry(startSeconds: 1.5, endSeconds: 3.2, text: "旧テキスト")]
        let result = TextReplacer.apply(rules: rules, to: entries)
        #expect(result[0].startSeconds == 1.5)
        #expect(result[0].endSeconds == 3.2)
    }

    @Test("マッチしないルールはテキストを変更しない")
    func noMatchLeavesTextUnchanged() {
        let rules = [TextReplacer.Rule(from: "存在しない語", to: "X")]
        let entries = [SubtitleEntry(startSeconds: 0, endSeconds: 1, text: "変わらないテキスト")]
        let result = TextReplacer.apply(rules: rules, to: entries)
        #expect(result[0].text == "変わらないテキスト")
    }

    // ── loadCSV() ──────────────────────────────────────────────

    private func writeTempCSV(_ content: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".csv")
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test("基本的なCSVを読み込める")
    func loadBasicCSV() throws {
        let url = try writeTempCSV("ファイナルカットプロ,Final Cut Pro\nウィスパーキット,WhisperKit\n")
        let rules = try TextReplacer.loadCSV(url: url)
        #expect(rules.count == 2)
        #expect(rules[0].from == "ファイナルカットプロ")
        #expect(rules[0].to == "Final Cut Pro")
        #expect(rules[1].from == "ウィスパーキット")
        #expect(rules[1].to == "WhisperKit")
    }

    @Test("空行とコメント行をスキップする")
    func skipsEmptyAndCommentLines() throws {
        let csv = """
        # これはコメント
        ファイナルカットプロ,Final Cut Pro

        # 別のコメント
        A,B
        """
        let url = try writeTempCSV(csv)
        let rules = try TextReplacer.loadCSV(url: url)
        #expect(rules.count == 2)
        #expect(rules[0].from == "ファイナルカットプロ")
        #expect(rules[1].from == "A")
    }

    @Test("BOM付きUTF-8ファイルを読める")
    func loadBOMFile() throws {
        let bom = "\u{FEFF}"
        let url = try writeTempCSV(bom + "A,B\n")
        let rules = try TextReplacer.loadCSV(url: url)
        #expect(rules.count == 1)
        #expect(rules[0].from == "A")
        #expect(rules[0].to == "B")
    }

    @Test("カンマを含む置換後文字列: 最初のカンマで分割する")
    func toContainsComma() throws {
        let url = try writeTempCSV("区切り,b,c\n")
        let rules = try TextReplacer.loadCSV(url: url)
        #expect(rules.count == 1)
        #expect(rules[0].from == "区切り")
        #expect(rules[0].to == "b,c")
    }

    @Test("カンマがない行はスキップされる")
    func lineWithoutCommaSkipped() throws {
        let url = try writeTempCSV("カンマなし\nA,B\n")
        let rules = try TextReplacer.loadCSV(url: url)
        #expect(rules.count == 1)
        #expect(rules[0].from == "A")
    }

    @Test("存在しないファイルはエラーを投げる")
    func missingFileThrows() {
        let url = URL(fileURLWithPath: "/tmp/nonexistent_\(UUID().uuidString).csv")
        #expect(throws: (any Error).self) {
            _ = try TextReplacer.loadCSV(url: url)
        }
    }
}
