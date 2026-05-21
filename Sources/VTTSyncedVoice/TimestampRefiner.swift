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
        /// クランプ後に保証するエントリの最小表示時間（秒）。ゼロ長エントリを防ぐ。
        public var minDuration: Double = 0.1
        public init(
            marginBefore: Double = 0.033,
            marginAfter: Double = 0.2,
            silenceThreshold: Float = 0.001,
            minGapToNext: Double = 0.1,
            minDuration: Double = 0.1
        ) {
            self.marginBefore = marginBefore
            self.marginAfter = marginAfter
            self.silenceThreshold = silenceThreshold
            self.minGapToNext = minGapToNext
            self.minDuration = minDuration
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
        // 直前エントリの offsetSec（marginAfter 加算前）を記録する。
        // detect() の searchFrom に渡すことで前発話の残響をスキップしつつ
        // marginAfter による過大な押し出しを防ぐ。
        var prevOffsetSec: Double? = nil

        for (i, entry) in entries.enumerated() {
            // start 補正: 前エントリの offsetSec（margin前）を searchFrom に渡して残響をスキップ
            let onsetResult = OnsetDetector.detect(
                audio: audio,
                sampleRate: sampleRate,
                ctcStart: entry.startSeconds,
                searchFrom: prevOffsetSec,
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
            prevOffsetSec = offsetResult.offsetSec

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

        // パス1: end クランプ — 次エントリの start - minGapToNext を超えないようにする。
        // refined[i+1].startSeconds はここでは未クランプの値。パス2で startSeconds が変わっても
        // end クランプの基準は「onset 補正後の start」であるべきなので、パス1を先に行う。
        // minDuration を下限として保証し、ゼロ長エントリになることを防ぐ。
        // ゼロ長起源エントリ（元の ctcStart == ctcEnd）の end が次エントリの start より後になる場合、
        // end を優先して次エントリの start を後ろへ逃がす。
        for i in 0..<refined.count - 1 {
            let clampedEnd = refined[i + 1].startSeconds - config.minGapToNext
            if refined[i].endSeconds > clampedEnd {
                let minEnd = refined[i].startSeconds + config.minDuration
                let resolvedEnd = max(minEnd, clampedEnd)
                refined[i] = SubtitleEntry(
                    startSeconds: refined[i].startSeconds,
                    endSeconds: resolvedEnd,
                    text: refined[i].text
                )
                // ゼロ長起源エントリで end が次の start を侵食する場合、次の start を後ろへ逃がす
                let isZeroDurationOrigin = entries[i].startSeconds == entries[i].endSeconds
                if isZeroDurationOrigin && resolvedEnd + config.minGapToNext > refined[i + 1].startSeconds {
                    refined[i + 1] = SubtitleEntry(
                        startSeconds: resolvedEnd + config.minGapToNext,
                        endSeconds: refined[i + 1].endSeconds,
                        text: refined[i + 1].text
                    )
                }
            }
        }

        // パス2: start クランプ — marginBefore で前エントリの end と重なった場合に最小インターバルを確保。
        // パス1で更新済みの refined[i-1].endSeconds を参照するため、パス1の後に行う。
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
