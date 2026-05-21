import Foundation
import AVFoundation
import WhisperKit

final class SpeechPipeline: Sendable {

    nonisolated(unsafe) private let whisperKit: WhisperKit
    private let language: String

    private init(whisperKit: WhisperKit, language: String) {
        self.whisperKit = whisperKit
        self.language = language
    }

    static func load(
        model: String,
        language: String,
        onProgress: (@Sendable (VTTSyncedVoice.Progress) -> Void)? = nil
    ) async throws -> SpeechPipeline {
        onProgress?(.loadingModels)
        let config = WhisperKitConfig(model: model)
        let whisperKit = try await WhisperKit(config)
        return SpeechPipeline(whisperKit: whisperKit, language: language)
    }

    func process(
        audioURL: URL,
        punctuationHint: Bool = false,
        onProgress: (@Sendable (VTTSyncedVoice.Progress) -> Void)? = nil
    ) async throws -> [WordTiming] {
        onProgress?(.transcribing)

        var options = DecodingOptions()
        options.wordTimestamps = true
        options.language = language

        // 句読点付与を促すヒント: 直前セグメントが句点で終わったように見せる
        if punctuationHint, let tokenizer = whisperKit.tokenizer {
            let ids = tokenizer.encode(text: "。")
            if !ids.isEmpty {
                options.promptTokens = ids
            }
        }

        let results = try await whisperKit.transcribe(
            audioPath: audioURL.path,
            decodeOptions: options
        )

        // 音声ファイルの実際の長さを取得してゴースト（幻聴）ワードを除外する
        let audioFile = try AVAudioFile(forReading: audioURL)
        let audioDuration = Double(audioFile.length) / audioFile.processingFormat.sampleRate

        var words = results.flatMap { $0.allWords }.filter { $0.start <= Float(audioDuration) }

        // 最後のワードの end が audioDuration を超えている場合（幻聴に引き伸ばされた）
        // audioDuration でクランプして再検証対象にする
        if var last = words.last, Double(last.end) > audioDuration {
            last.end = Float(audioDuration)
            words[words.count - 1] = last
        }

        return words
    }
}
