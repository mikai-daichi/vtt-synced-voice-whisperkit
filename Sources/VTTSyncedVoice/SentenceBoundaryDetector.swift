import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26, *)
@Generable
struct SentenceBoundaries {
    /// チャンク内で文末と判定されたローカルインデックス
    var endIndices: [Int]
}

@available(macOS 26, *)
public enum SentenceBoundaryDetector {

    static let chunkSize = 20
    static let overlap = 2

    /// 末尾が読点「、」で終わる断片、または7文字以下の短文はコード側で非文末と確定する。
    private static func isDefinitelyContinuing(_ text: String) -> Bool {
        text.last == "、" || text.count <= EntryMerger.shortEntryThreshold
    }

    /// entries の中で文末となるインデックスを返す（0-based）。
    public static func detectBoundaries(in entries: [SubtitleEntry]) async throws -> [Int] {
        guard entries.count > 1 else { return entries.isEmpty ? [] : [entries.count - 1] }

        var boundaries = Set<Int>()
        let total = entries.count
        var chunkStart = 0

        while chunkStart < total {
            let chunkEnd = min(chunkStart + chunkSize, total)
            let chunk = Array(entries[chunkStart..<chunkEnd])

            let indicesInChunk = try await detectInChunk(chunk)
            for localIdx in indicesInChunk {
                guard localIdx < chunk.count else { continue }
                boundaries.insert(chunkStart + localIdx)
            }

            if chunkEnd == total { break }
            chunkStart = chunkEnd - overlap
        }

        boundaries.insert(total - 1)
        return boundaries.sorted()
    }

    private static func detectInChunk(_ chunk: [SubtitleEntry]) async throws -> [Int] {
        // 読点止めはコード側で非文末確定。AI には渡さず、元インデックスへの対応表だけ保持する。
        // aiIndex → chunkIndex のマッピング
        var aiToChunk: [Int: Int] = [:]
        var aiFragments: [(aiIdx: Int, text: String)] = []

        for (chunkIdx, entry) in chunk.enumerated() {
            if !isDefinitelyContinuing(entry.text) {
                let aiIdx = aiFragments.count
                aiToChunk[aiIdx] = chunkIdx
                aiFragments.append((aiIdx, entry.text))
            }
        }

        // AI に渡す断片が0個（全部読点止め）の場合は末尾だけ返す
        guard !aiFragments.isEmpty else { return [chunk.count - 1] }

        let lastAiIndex = aiFragments.count - 1
        let fragmentList = aiFragments
            .map { "[\($0.aiIdx)] \($0.text)" }
            .joined(separator: "\n")

        let systemPrompt = """
            あなたは日本語音声認識テキストの文境界アナリストです。
            句読点のない音声認識断片のリストを受け取り、各断片が「文末か否か」を判定して、文末となる断片の番号を返します。
            各断片はその断片のテキストだけで独立して判定します。前後の断片の内容は判定に影響させないでください。
            テキストの内容は変更しません。番号だけを返します。
            """

        let userPrompt = """
            以下は音声認識で得られた \(aiFragments.count) 個の断片のリストです。
            [0] から [\(lastAiIndex)] まで全ての断片を1つずつ独立して評価し、「文末」と判定した番号を全て endIndices に返してください。
            最後の断片 [\(lastAiIndex)] は必ず含めること。

            \(fragmentList)

            【文末と判定する条件】（いずれかに当てはまれば文末）
            - 丁寧体語尾：〜です、〜ます、〜でした、〜ました、〜ません、〜ませんでした
            - 普通体語尾：〜だ、〜だった、〜た（常に文末）、〜ない、〜ぬ
            - 疑問形：〜ですか、〜ますか、〜でしょうか、〜かな、〜だろうか
            - 依頼・命令：〜てください、〜なさい
            - 発語・フィラー：「あ」「あー」「えっと」「えー」「うーん」などが単独または連続
            - 体言止め：名詞や形容詞で完結（例：「今日は雨」「1つ目」）
            - 末尾が句点：。！？

            【重要】各断片を前後と無関係に独立して判定すること。
            「ます」「です」「た」で終わる断片は、次の断片が何であっても必ず文末とすること。
            """

        let session = LanguageModelSession(instructions: systemPrompt)
        let response = try await session.respond(
            to: userPrompt,
            generating: SentenceBoundaries.self
        )

        // AI の返した aiIndex を chunkIndex に変換して返す
        return response.content.endIndices.compactMap { aiToChunk[$0] }
    }
}
#endif
