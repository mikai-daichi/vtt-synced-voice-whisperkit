import Foundation

public final class VTTSyncedVoice: Sendable {

    public struct Configuration: Sendable {
        public var language: String = "ja"
        public var phraseGapThreshold: Double = 0.5
        public var model: String = "large-v3-v20240930_626MB"
        /// onset検出後、開始時刻を早める余白（秒）。増やすほど早くなる。
        public var marginBefore: Double = 0.033
        /// offset検出後、終了時刻を延ばす余白（秒）。増やすほどセリフ間の間隔が広がる。
        public var marginAfter: Double = 0.2
        /// 無音判定のRMS閾値（ピーク正規化後）
        public var silenceThreshold: Float = 0.001
        /// true にすると WordGrouper の出力を句点単位でマージしてから TimestampRefiner に渡す
        public var mergeSentences: Bool = false
        public init() {}
    }

    public enum Progress: Sendable {
        case loadingModels
        case downloadingModel(name: String, progress: Double)
        case transcribing
        case grouping
        case refining
        case completed(entryCount: Int)
    }

    private let configuration: Configuration
    private let pipeline: SpeechPipeline

    public init(configuration: Configuration = Configuration()) async throws {
        self.configuration = configuration
        self.pipeline = try await SpeechPipeline.load(
            model: configuration.model,
            language: configuration.language
        )
    }

    public func analyze(
        audioURL: URL,
        onProgress: (@Sendable (Progress) -> Void)? = nil
    ) async throws -> [SubtitleEntry] {
        // WhisperKit でワードタイムスタンプを取得
        let words = try await pipeline.process(audioURL: audioURL, onProgress: onProgress)

        // ワードをフレーズ単位にグループ化
        onProgress?(.grouping)
        let grouped = WordGrouper.group(words: words, gapThreshold: configuration.phraseGapThreshold)
        let phrased = configuration.mergeSentences ? EntryMerger.merge(entries: grouped) : grouped

        // 波形レベルの onset 補正
        onProgress?(.refining)
        let audio = try AudioLoader.loadNormalized(url: audioURL)
        let refinerConfig = TimestampRefiner.Config(
            marginBefore: configuration.marginBefore,
            marginAfter: configuration.marginAfter,
            silenceThreshold: configuration.silenceThreshold
        )
        let (entries, _) = TimestampRefiner.refine(
            entries: phrased,
            audio: audio,
            config: refinerConfig
        )

        onProgress?(.completed(entryCount: entries.count))
        return entries
    }

    /// onset補正のデバッグ情報付きで解析する（verbose出力用）
    public func analyzeVerbose(
        audioURL: URL,
        onProgress: (@Sendable (Progress) -> Void)? = nil
    ) async throws -> (entries: [SubtitleEntry], debug: [TimestampRefiner.DebugEntry]) {
        let words = try await pipeline.process(audioURL: audioURL, onProgress: onProgress)

        onProgress?(.grouping)
        let grouped = WordGrouper.group(words: words, gapThreshold: configuration.phraseGapThreshold)
        let phrased = configuration.mergeSentences ? EntryMerger.merge(entries: grouped) : grouped

        onProgress?(.refining)
        let audio = try AudioLoader.loadNormalized(url: audioURL)
        let refinerConfig = TimestampRefiner.Config(
            marginBefore: configuration.marginBefore,
            marginAfter: configuration.marginAfter,
            silenceThreshold: configuration.silenceThreshold
        )
        let (entries, debug) = TimestampRefiner.refine(
            entries: phrased,
            audio: audio,
            config: refinerConfig
        )

        onProgress?(.completed(entryCount: entries.count))
        return (entries, debug)
    }

    public struct WordInfo: Sendable {
        public let word: String
        public let start: Float
        public let end: Float
    }

    public func words(
        audioURL: URL
    ) async throws -> [WordInfo] {
        let timings = try await pipeline.process(audioURL: audioURL)
        return timings.map { WordInfo(word: $0.word, start: $0.start, end: $0.end) }
    }

    public func generateVTT(
        audioURL: URL,
        onProgress: (@Sendable (Progress) -> Void)? = nil
    ) async throws -> String {
        let entries = try await analyze(audioURL: audioURL, onProgress: onProgress)
        return VTTWriter.write(entries: entries)
    }
}
