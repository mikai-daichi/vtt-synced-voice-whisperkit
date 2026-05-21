import Testing
@testable import VTTSyncedVoice

@Suite("SubtitleEntry")
struct SubtitleEntryTests {

    @Test("初期化でプロパティが正しく設定される")
    func initialization() {
        let entry = SubtitleEntry(startSeconds: 1.0, endSeconds: 3.5, text: "こんにちは")
        #expect(entry.startSeconds == 1.0)
        #expect(entry.endSeconds == 3.5)
        #expect(entry.text == "こんにちは")
    }

    @Test("Equatableが値で等価判定される")
    func equatable() {
        let a = SubtitleEntry(startSeconds: 1.0, endSeconds: 2.0, text: "ABC")
        let b = SubtitleEntry(startSeconds: 1.0, endSeconds: 2.0, text: "ABC")
        let c = SubtitleEntry(startSeconds: 1.0, endSeconds: 2.0, text: "XYZ")
        #expect(a == b)
        #expect(a != c)
    }

    @Test("startSeconds == endSeconds でも生成可能")
    func zeroLengthEntry() {
        let entry = SubtitleEntry(startSeconds: 5.0, endSeconds: 5.0, text: "")
        #expect(entry.startSeconds == entry.endSeconds)
        #expect(entry.text.isEmpty)
    }

    @Test("大きな時刻値でも精度が保たれる")
    func largeTimestamp() {
        let entry = SubtitleEntry(startSeconds: 3599.999, endSeconds: 3600.001, text: "end")
        #expect(entry.startSeconds == 3599.999)
        #expect(entry.endSeconds == 3600.001)
    }
}
