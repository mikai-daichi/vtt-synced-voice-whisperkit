import Foundation

public enum TextReplacer {

    public struct Rule: Sendable {
        public let from: String
        public let to: String
        public init(from: String, to: String) {
            self.from = from
            self.to = to
        }
    }

    /// CSV ファイルから置換ルールを読み込む。
    /// フォーマット: `置換前,置換後` を1行1ルール。
    /// BOM付きUTF-8、空行、`#` 始まりのコメント行はスキップする。
    /// カンマが2つ以上ある行は最初のカンマで分割し、残り全体を置換後文字列とする。
    public static func loadCSV(url: URL) throws -> [Rule] {
        let raw = try String(contentsOf: url, encoding: .utf8)
        let content = raw.hasPrefix("\u{FEFF}") ? String(raw.dropFirst()) : raw

        var rules: [Rule] = []
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            guard let commaIdx = trimmed.firstIndex(of: ",") else { continue }
            let from = String(trimmed[trimmed.startIndex..<commaIdx])
            let to = String(trimmed[trimmed.index(after: commaIdx)...])
            guard !from.isEmpty else { continue }
            rules.append(Rule(from: from, to: to))
        }
        return rules
    }

    /// ルールを順番に適用して新しい SubtitleEntry[] を返す。
    /// 前のルールの出力が次のルールの入力になる（連鎖置換）。
    public static func apply(rules: [Rule], to entries: [SubtitleEntry]) -> [SubtitleEntry] {
        guard !rules.isEmpty else { return entries }
        return entries.map { entry in
            var text = entry.text
            for rule in rules {
                text = text.replacingOccurrences(of: rule.from, with: rule.to)
            }
            return SubtitleEntry(startSeconds: entry.startSeconds, endSeconds: entry.endSeconds, text: text)
        }
    }
}
