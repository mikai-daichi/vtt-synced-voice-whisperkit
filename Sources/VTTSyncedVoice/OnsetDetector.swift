import Foundation
import Accelerate

/// Python版 onset.py の Swift 移植。
/// vDSP.rootMeanSquare() を使い SIMD 演算で RMS を計算する。
enum OnsetDetector {

    static let searchSec: Double = 1.5      // CTC startから遡る/進む最大時間
    static let frameSec: Double = 0.005     // RMSフレームサイズ（5ms）
    static let defaultSilenceThreshold: Float = 0.001
    // 有音判定に必要な連続フレーム数（フェーズ2b）: 偶発ノイズ・息継ぎを除外する
    static let requiredConsecutiveFrames: Int = 4  // 4×5ms = 20ms

    struct Result {
        let onsetSec: Double
        let debugNote: String   // "←-XXXms" / "→+XXXms" / "→±0ms"
    }

    struct OffsetResult {
        let offsetSec: Double
        let debugNote: String
    }

    /// CTC start から無音→有音の境界（onset）を検出して返す。
    ///
    /// 2フェーズ処理（Python版 find_onset() と同一ロジック）:
    ///   フェーズ1: CTC start付近 3フレーム（15ms）の最大RMSで有音/無音を判定
    ///   フェーズ2a（有音）: 逆方向スキャンで最初の無音フレームを探す → その終端 = onset
    ///   フェーズ2b（無音）: 前方スキャンで最初の有音フレームを探す → その先頭 = onset
    ///
    /// - Parameters:
    ///   - audio: ピーク正規化済みの16kHz/モノラルPCMサンプル列
    ///   - sampleRate: サンプルレート（デフォルト16000）
    ///   - ctcStart: WhisperKit が返したワードの開始時刻（秒）
    ///   - silenceThreshold: 無音判定のRMS閾値（ピーク正規化後）
    /// CTC end から有音→無音の境界（offset）を検出して返す。detect() の対称版。
    ///
    /// フェーズ1: CTC end 付近 3フレーム（15ms）の最大RMSで有音/無音を判定
    /// フェーズ2a（有音）: 前方スキャンで最初の無音フレームを探す → その先頭 = offset
    /// フェーズ2b（無音）: 逆方向スキャンで最初の有音フレームを探す → その終端 = offset
    static func detectOffset(
        audio: [Float],
        sampleRate: Int = 16000,
        ctcEnd: Double,
        silenceThreshold: Float = defaultSilenceThreshold
    ) -> OffsetResult {
        let frameSize = max(1, Int(frameSec * Double(sampleRate)))
        let searchSamples = Int(searchSec * Double(sampleRate))
        let ctcSample = Int(ctcEnd * Double(sampleRate))

        func rms(from start: Int) -> Float {
            let end = min(start + frameSize, audio.count)
            guard start < end else { return 0.0 }
            let slice = Array(audio[start..<end])
            return vDSP.rootMeanSquare(slice)
        }

        func note(_ offsetSec: Double) -> String {
            let deltaMs = (offsetSec - ctcEnd) * 1000
            if deltaMs < -0.5 { return String(format: "←%+.0fms", deltaMs) }
            if deltaMs > 0.5  { return String(format: "→%+.0fms", deltaMs) }
            return "→±0ms"
        }

        // フェーズ1: CTC end 付近 3フレーム（15ms）の最大RMSで有音/無音を判定
        let ctcRMS = max(
            rms(from: max(0, ctcSample - frameSize * 2)),
            rms(from: max(0, ctcSample - frameSize)),
            rms(from: ctcSample)
        )
        let ctcIsSilent = ctcRMS <= silenceThreshold

        if !ctcIsSilent {
            // フェーズ2a: 有音 → 前方スキャンで最初の無音フレームを探す → その先頭 = offset
            // 無音が見つからない場合は searchEnd までの最終有音位置を offset とする。
            let searchEnd = min(audio.count, ctcSample + searchSamples)
            var pos = ctcSample
            var offsetSample = ctcSample
            while pos + frameSize <= searchEnd {
                pos += frameSize
                if rms(from: pos) <= silenceThreshold {
                    offsetSample = pos
                    break
                }
                offsetSample = pos  // 有音継続中: 無音が見つからなければ最終有音フレームの先頭が offset
            }
            let offsetSec = Double(offsetSample) / Double(sampleRate)
            return OffsetResult(offsetSec: offsetSec, debugNote: note(offsetSec))
        } else {
            // フェーズ2b: 無音 → 逆方向スキャンで最初の有音フレームを探す → その終端 = offset
            let searchStart = max(0, ctcSample - searchSamples)
            var pos = ctcSample
            var offsetSample = ctcSample
            while pos - frameSize >= searchStart {
                pos -= frameSize
                if rms(from: pos) > silenceThreshold {
                    offsetSample = pos + frameSize
                    break
                }
            }
            let offsetSec = Double(offsetSample) / Double(sampleRate)
            return OffsetResult(offsetSec: offsetSec, debugNote: note(offsetSec))
        }
    }

    /// - Parameters:
    ///   - searchFrom: 前方スキャンの開始点（秒）。前エントリの endSeconds を渡すことで
    ///                 前発話の残響・息継ぎをスキップできる。nil の場合は ctcStart から開始。
    static func detect(
        audio: [Float],
        sampleRate: Int = 16000,
        ctcStart: Double,
        searchFrom: Double? = nil,
        silenceThreshold: Float = defaultSilenceThreshold
    ) -> Result {
        let frameSize = max(1, Int(frameSec * Double(sampleRate)))
        let searchSamples = Int(searchSec * Double(sampleRate))
        let ctcSample = Int(ctcStart * Double(sampleRate))

        func rms(from start: Int) -> Float {
            let end = min(start + frameSize, audio.count)
            guard start < end else { return 0.0 }
            let slice = Array(audio[start..<end])
            return vDSP.rootMeanSquare(slice)
        }

        func note(_ onsetSec: Double) -> String {
            let deltaMs = (onsetSec - ctcStart) * 1000
            if deltaMs < -0.5 { return String(format: "←%+.0fms", deltaMs) }
            if deltaMs > 0.5  { return String(format: "→%+.0fms", deltaMs) }
            return "→±0ms"
        }

        // フェーズ1: CTC start付近 3フレーム（15ms）の最大RMSで有音/無音を判定
        let ctcRMS = max(
            rms(from: ctcSample),
            rms(from: ctcSample + frameSize),
            rms(from: ctcSample + frameSize * 2)
        )
        let ctcIsSilent = ctcRMS <= silenceThreshold

        if !ctcIsSilent {
            // フェーズ2a: 有音 → 逆方向スキャンで最初の無音フレームを探す
            let searchStart = max(0, ctcSample - searchSamples)
            var pos = ctcSample
            var onsetSample = ctcSample
            while pos - frameSize >= searchStart {
                pos -= frameSize
                if rms(from: pos) <= silenceThreshold {
                    onsetSample = pos + frameSize
                    break
                }
            }
            let onsetSec = Double(onsetSample) / Double(sampleRate)
            return Result(onsetSec: onsetSec, debugNote: note(onsetSec))
        } else {
            // フェーズ2b: 無音 → 「無音区間を確認してから有音」の2段階で onset を探す
            // 手順:
            //   ステップ1: CTC start（または searchFrom）から前方スキャンして無音フレームを確認
            //   ステップ2: その無音の後に連続有音（Nフレーム）が始まる点を onset とする
            // これにより CTC より前にある息継ぎ・残響をスキップできる
            let scanStartSample: Int
            if let sf = searchFrom, sf > ctcStart {
                scanStartSample = Int(sf * Double(sampleRate))
            } else {
                scanStartSample = ctcSample
            }
            let searchEnd = min(audio.count, ctcSample + searchSamples)
            var pos = scanStartSample
            var onsetSample = ctcSample
            var foundSilence = false

            while pos + frameSize <= searchEnd {
                let currentRMS = rms(from: pos)
                if !foundSilence {
                    // ステップ1: 無音フレームを探す
                    if currentRMS <= silenceThreshold {
                        foundSilence = true
                    }
                } else {
                    // ステップ2: 無音確認済み → 連続有音の開始を探す
                    if currentRMS > silenceThreshold {
                        var consecutive = 1
                        var checkPos = pos + frameSize
                        while consecutive < requiredConsecutiveFrames && checkPos + frameSize <= searchEnd {
                            if rms(from: checkPos) > silenceThreshold {
                                consecutive += 1
                                checkPos += frameSize
                            } else {
                                break
                            }
                        }
                        if consecutive >= requiredConsecutiveFrames {
                            onsetSample = pos
                            break
                        } else {
                            // 連続フレーム不足 → 無音フラグをリセットして続行
                            foundSilence = false
                        }
                    }
                }
                pos += frameSize
            }
            let onsetSec = Double(onsetSample) / Double(sampleRate)
            return Result(onsetSec: onsetSec, debugNote: note(onsetSec))
        }
    }
}
