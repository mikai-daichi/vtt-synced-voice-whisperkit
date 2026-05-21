import Testing
@testable import VTTSyncedVoice

@Suite("VTTWriter")
struct VTTWriterTests {

    @Test("空配列でも WEBVTT ヘッダが出力される")
    func emptyEntriesHeader() {
        let output = VTTWriter.write(entries: [])
        let lines = output.components(separatedBy: "\n")
        #expect(lines[0] == "WEBVTT")
        #expect(lines[1] == "")
    }

    @Test("0.0秒は 00:00:00.000 にフォーマットされる")
    func formatZeroSeconds() {
        let entry = SubtitleEntry(startSeconds: 0.0, endSeconds: 0.0, text: "A")
        let output = VTTWriter.write(entries: [entry])
        #expect(output.contains("00:00:00.000 --> 00:00:00.000"))
    }

    @Test("1時間23分45.678秒が正しくフォーマットされる")
    func formatHourMinuteSecondMs() {
        let t = 1.0 * 3600 + 23.0 * 60 + 45.678
        let entry = SubtitleEntry(startSeconds: t, endSeconds: t + 1.0, text: "B")
        let output = VTTWriter.write(entries: [entry])
        #expect(output.contains("01:23:45.678"))
    }

    @Test("59分59.999秒のエッジケース")
    func formatNearHour() {
        let t = 59.0 * 60 + 59.999
        let entry = SubtitleEntry(startSeconds: t, endSeconds: t + 0.5, text: "C")
        let output = VTTWriter.write(entries: [entry])
        #expect(output.contains("00:59:59.999"))
    }

    @Test("ミリ秒が3桁ゼロ埋めされる（0.005秒 → .005）")
    func millisecondPadding() {
        let entry = SubtitleEntry(startSeconds: 0.005, endSeconds: 0.010, text: "D")
        let output = VTTWriter.write(entries: [entry])
        #expect(output.contains("00:00:00.005 --> 00:00:00.010"))
    }

    @Test("1エントリのVTT構造が正しい（タイムスタンプ行＋テキスト行＋空行）")
    func singleEntryStructure() {
        let entry = SubtitleEntry(startSeconds: 1.0, endSeconds: 2.0, text: "hello")
        let output = VTTWriter.write(entries: [entry])
        let lines = output.components(separatedBy: "\n")
        #expect(lines.count >= 5)
        #expect(lines[0] == "WEBVTT")
        #expect(lines[1] == "")
        #expect(lines[2] == "00:00:01.000 --> 00:00:02.000")
        #expect(lines[3] == "hello")
        #expect(lines[4] == "")
    }

    @Test("複数エントリが順番に出力される")
    func multipleEntries() {
        let entries = [
            SubtitleEntry(startSeconds: 0.0, endSeconds: 1.0, text: "first"),
            SubtitleEntry(startSeconds: 1.5, endSeconds: 2.5, text: "second")
        ]
        let output = VTTWriter.write(entries: entries)
        let firstRange = output.range(of: "first")
        let secondRange = output.range(of: "second")
        #expect(firstRange != nil)
        #expect(secondRange != nil)
        #expect(firstRange!.lowerBound < secondRange!.lowerBound)
    }

    @Test("日本語テキストがそのまま出力される")
    func japaneseText() {
        let entry = SubtitleEntry(startSeconds: 0.5, endSeconds: 1.5, text: "こんにちは世界")
        let output = VTTWriter.write(entries: [entry])
        #expect(output.contains("こんにちは世界"))
    }
}
