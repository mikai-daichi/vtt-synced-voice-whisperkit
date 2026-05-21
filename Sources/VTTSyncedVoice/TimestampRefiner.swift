import Foundation
import Accelerate

/// Python版 transcriber.py の apply_onset_to_cues() に対応する処理。
/// SubtitleEntry[] の startSeconds を音声波形の onset で補正する。
public enum TimestampRefiner {

    public struct Config {
        /// onset検出後、開始時刻を早める余白（秒）。増やすほど早くなる。
        public var marginBefore: Double = 0.033
        /// offset検出後、終了時刻を延ばす余白（秒）。増やすほどセリフ間の間隔が広がる。
        public var marginAfter: Double = 0.2
        /// 無音判定のRMS閾値（ピーク正規化後）
        public var silenceThreshold: Float = 0.001
        /// 次エントリとの間に確保する最小無音時間（秒）
        public var minGapToNext: Double = 0.1
        public init(
            marginBefore: Double = 0.033,
            marginAfter: Double = 0.2,
            silenceThreshold: Float = 0.001,
            minGapToNext: Double = 0.1
        ) {
            self.marginBefore = marginBefore
            self.marginAfter = marginAfter
            self.silenceThreshold = silenceThreshold
            self.minGapToNext = minGapToNext
        }
    }

    public struct DebugEntry: Sendable {
        public let index: Int
        public let text: String
        public let ctcStart: Double
        public let onsetSec: Double
        public let finalStart: Double
        public let noteStart: String
        public let ctcEnd: Double
        public let offsetSec: Double
        public let finalEnd: Double
        public let noteEnd: String
    }

    /// onset補正を適用して新しい SubtitleEntry[] を返す。
    ///
    /// - Parameters:
    ///   - entries: WordGrouper が生成した補正前のエントリ列
    ///   - audio: ピーク正規化済みの16kHz/モノラルPCMサンプル列
    ///   - sampleRate: サンプルレート（デフォルト16000）
    ///   - config: 補正パラメータ
    /// - Returns: (補正済みエントリ列, デバッグ情報列)
    public static func refine(
        entries: [SubtitleEntry],
        audio: [Float],
        sampleRate: Int = 16000,
        config: Config = Config()
    ) -> (entries: [SubtitleEntry], debug: [DebugEntry]) {
        guard !entries.isEmpty else { return ([], []) }

        var refined: [SubtitleEntry] = []
        var debugLog: [DebugEntry] = []

        for (i, entry) in entries.enumerated() {
            // start 補正: 前エントリの endSeconds を searchFrom に渡して残響をスキップ
            let prevEnd: Double? = i > 0 ? entries[i - 1].endSeconds : nil
            let onsetResult = OnsetDetector.detect(
                audio: audio,
                sampleRate: sampleRate,
                ctcStart: entry.startSeconds,
                searchFrom: prevEnd,
                silenceThreshold: config.silenceThreshold
            )
            let newStart = max(0.0, onsetResult.onsetSec - config.marginBefore)

            // end 補正: CTC end から有音→無音の境界（offset）を検出
            let offsetResult = OnsetDetector.detectOffset(
                audio: audio,
                sampleRate: sampleRate,
                ctcEnd: entry.endSeconds,
                silenceThreshold: config.silenceThreshold
            )
            let newEnd = offsetResult.offsetSec + config.marginAfter

            refined.append(SubtitleEntry(
                startSeconds: newStart,
                endSeconds: newEnd,
                text: entry.text
            ))

            debugLog.append(DebugEntry(
                index: i,
                text: entry.text,
                ctcStart: entry.startSeconds,
                onsetSec: onsetResult.onsetSec,
                finalStart: newStart,
                noteStart: onsetResult.debugNote,
                ctcEnd: entry.endSeconds,
                offsetSec: offsetResult.offsetSec,
                finalEnd: newEnd,
                noteEnd: offsetResult.debugNote
            ))
        }

        // end クランプ: 次エントリの start - minGapToNext を超えないようにする
        for i in 0..<refined.count - 1 {
            let clampedEnd = refined[i + 1].startSeconds - config.minGapToNext
            if refined[i].endSeconds > clampedEnd {
                refined[i] = SubtitleEntry(
                    startSeconds: refined[i].startSeconds,
                    endSeconds: max(refined[i].startSeconds, clampedEnd),
                    text: refined[i].text
                )
            }
        }

        // start クランプ: paddingBefore で前エントリの end と重なった場合に最小インターバルを確保
        for i in 1..<refined.count {
            let clampedStart = refined[i - 1].endSeconds + config.minGapToNext
            if refined[i].startSeconds < clampedStart {
                refined[i] = SubtitleEntry(
                    startSeconds: clampedStart,
                    endSeconds: refined[i].endSeconds,
                    text: refined[i].text
                )
            }
        }

        // 最後のエントリの endSeconds が無音領域にある場合、有音まで遡って修正する。
        // 幻聴によって CTC end が後ろに伸ばされた場合に detectOffset の searchSec 制限を超えることがある。
        if let lastIdx = refined.indices.last {
            let lastEnd = refined[lastIdx].endSeconds
            let frameSize = max(1, Int(OnsetDetector.frameSec * Double(sampleRate)))
            let endSample = min(Int(lastEnd * Double(sampleRate)), audio.count - frameSize)

            func rms(from start: Int) -> Float {
                let e = min(start + frameSize, audio.count)
                guard start < e else { return 0.0 }
                let slice = Array(audio[start..<e])
                return vDSP.rootMeanSquare(slice)
            }

            if rms(from: endSample) <= config.silenceThreshold {
                // 有音フレームが見つかるまで無制限に遡る
                var pos = endSample
                var foundSample = endSample
                while pos - frameSize >= 0 {
                    pos -= frameSize
                    if rms(from: pos) > config.silenceThreshold {
                        foundSample = pos + frameSize
                        break
                    }
                }
                let correctedEnd = Double(foundSample) / Double(sampleRate) + config.marginAfter
                if correctedEnd < lastEnd {
                    refined[lastIdx] = SubtitleEntry(
                        startSeconds: refined[lastIdx].startSeconds,
                        endSeconds: correctedEnd,
                        text: refined[lastIdx].text
                    )
                    // debugLog の最終エントリも更新
                    let d = debugLog[lastIdx]
                    debugLog[lastIdx] = DebugEntry(
                        index: d.index, text: d.text,
                        ctcStart: d.ctcStart, onsetSec: d.onsetSec, finalStart: d.finalStart, noteStart: d.noteStart,
                        ctcEnd: d.ctcEnd, offsetSec: Double(foundSample) / Double(sampleRate),
                        finalEnd: correctedEnd, noteEnd: "←last-silence-scan"
                    )
                }
            }
        }

        return (refined, debugLog)
    }
}
