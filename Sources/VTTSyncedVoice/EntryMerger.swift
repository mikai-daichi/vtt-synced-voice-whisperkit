import Foundation

public enum EntryMerger {

    static let sentenceEndCharacters: Set<Character> = ["。", "！", "？", "!", "?"]

    /// WordGrouper の出力を句点単位でマージして返す。
    ///
    /// 句点（。！？!?）で終わるエントリをフラッシュ点として、
    /// それまでのバッファを1エントリに結合する。
    /// 句点が付かないまま末尾に達した場合も1エントリにまとめる。
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

    private static func flush(_ buffer: [SubtitleEntry]) -> SubtitleEntry {
        SubtitleEntry(
            startSeconds: buffer.first!.startSeconds,
            endSeconds: buffer.last!.endSeconds,
            text: buffer.map(\.text).joined()
        )
    }
}
