import Foundation

public enum EntryMerger {

    static let sentenceEndCharacters: Set<Character> = ["。", "！", "？", "!", "?"]

    /// 7文字以下のエントリは単独表示が不自然なため次のエントリに接続する。
    static let shortEntryThreshold = 7

    /// 末尾がこれらの助詞・接続形なら確実に次に続く（文末でない）。
    static let continuingSuffixes: [String] = [
        // 接続形（ます・です＋接続助詞）
        "ますし", "ですし", "たし",
        "ますが", "ですが", "たが",
        "ますけど", "ですけど", "たけど",
        "まして", "でして",
        // 接続助詞
        "して", "ので", "から", "けど", "が", "ながら", "たり",
        // 助詞止め（文が途中で切れている）
        "を", "に", "で", "と", "へ", "より",
    ]

    /// コードベースの文末判定。確実に続くパターンなら false、それ以外は true（疑わしければ文末）。
    static func isSentenceEnd(_ text: String) -> Bool {
        guard !text.isEmpty else { return true }

        // 読点止め → 確実に続く
        if text.last == "、" { return false }

        // 短文 → 確実に続く
        if text.count <= shortEntryThreshold { return false }

        // 接続形・助詞止め → 確実に続く
        for suffix in continuingSuffixes {
            if text.hasSuffix(suffix) { return false }
        }

        // それ以外は文末（疑わしければ切る）
        return true
    }

    /// コードベースの文境界判定でマージする（--merge-sentences で使用）。
    public static func mergeWithAI(entries: [SubtitleEntry]) async -> [SubtitleEntry] {
        mergeByPattern(entries: entries)
    }

    /// コードのパターンマッチで文末判定してマージする。
    public static func mergeByPattern(entries: [SubtitleEntry]) -> [SubtitleEntry] {
        guard !entries.isEmpty else { return [] }

        var result: [SubtitleEntry] = []
        var buffer: [SubtitleEntry] = []

        for entry in entries {
            buffer.append(entry)
            if isSentenceEnd(entry.text) {
                result.append(flush(buffer))
                buffer = []
            }
        }
        if !buffer.isEmpty {
            result.append(flush(buffer))
        }
        return result
    }

    /// WordGrouper の出力を句点単位でマージして返す（句点ベースのフォールバック）。
    public static func merge(entries: [SubtitleEntry]) -> [SubtitleEntry] {
        guard !entries.isEmpty else { return [] }

        var result: [SubtitleEntry] = []
        var buffer: [SubtitleEntry] = []

        for entry in entries {
            buffer.append(entry)
            if let last = entry.text.last, sentenceEndCharacters.contains(last) {
                result.append(flush(buffer))
                buffer = []
            }
        }
        if !buffer.isEmpty {
            result.append(flush(buffer))
        }
        return result
    }

    /// 指定インデックスでエントリをフラッシュする（AI境界検出の結果適用、将来用）。
    static func applyBoundaries(entries: [SubtitleEntry], endIndices: [Int]) -> [SubtitleEntry] {
        guard !entries.isEmpty else { return [] }

        let endSet = Set(endIndices)
        var result: [SubtitleEntry] = []
        var buffer: [SubtitleEntry] = []

        for (i, entry) in entries.enumerated() {
            buffer.append(entry)
            if endSet.contains(i) {
                result.append(flush(buffer))
                buffer = []
            }
        }
        if !buffer.isEmpty {
            result.append(flush(buffer))
        }
        return result
    }

    /// バッファを1エントリに結合する。
    /// 短文エントリ（7文字以下）の後には読点「、」を挿入して次のテキストと自然につなぐ。
    private static func flush(_ buffer: [SubtitleEntry]) -> SubtitleEntry {
        var text = ""
        for (i, entry) in buffer.enumerated() {
            text += entry.text
            let isLast = i == buffer.count - 1
            let isShort = entry.text.count <= shortEntryThreshold
            let nextStartsWithComma = !isLast && buffer[i + 1].text.first == "、"
            if !isLast && isShort && !text.hasSuffix("、") && !nextStartsWithComma {
                text += "、"
            }
        }
        return SubtitleEntry(
            startSeconds: buffer.first!.startSeconds,
            endSeconds: buffer.last!.endSeconds,
            text: text
        )
    }
}
