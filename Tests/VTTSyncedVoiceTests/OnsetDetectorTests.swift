import Testing
@testable import VTTSyncedVoice

@Suite("OnsetDetector")
struct OnsetDetectorTests {

    let sampleRate = 16000
    let silenceThreshold: Float = 0.001

    // `regions` は (silent: Bool, duration: 秒) のタプル列
    // 無音: 0.0、有音: 0.1（閾値0.001を大きく上回る）
    private func synth(regions: [(silent: Bool, duration: Double)]) -> [Float] {
        var samples: [Float] = []
        for (silent, duration) in regions {
            let count = Int(duration * Double(sampleRate))
            samples.append(contentsOf: [Float](repeating: silent ? 0.0 : 0.1, count: count))
        }
        return samples
    }

    // ────────────────────────────────────────────────────────
    // detect() のテスト
    // ────────────────────────────────────────────────────────

    @Test("フェーズ2b: CTC startが無音 → 前方スキャンでonsetを検出")
    func detectPhase2b_silentAtCTC() {
        // 0〜0.5s: 無音、0.5〜1.5s: 有音
        let audio = synth(regions: [(silent: true, duration: 0.5),
                                    (silent: false, duration: 1.0)])
        let ctcStart = 0.1
        let result = OnsetDetector.detect(
            audio: audio,
            sampleRate: sampleRate,
            ctcStart: ctcStart,
            silenceThreshold: silenceThreshold
        )
        #expect(result.onsetSec >= 0.4)
        #expect(result.onsetSec <= 0.6)
    }

    @Test("フェーズ2a: CTC startが有音 → 逆方向スキャンでonsetを検出")
    func detectPhase2a_voicedAtCTC() {
        // 0〜0.5s: 無音、0.5〜1.5s: 有音
        let audio = synth(regions: [(silent: true, duration: 0.5),
                                    (silent: false, duration: 1.0)])
        let ctcStart = 0.8
        let result = OnsetDetector.detect(
            audio: audio,
            sampleRate: sampleRate,
            ctcStart: ctcStart,
            silenceThreshold: silenceThreshold
        )
        #expect(result.onsetSec >= 0.4)
        #expect(result.onsetSec <= 0.6)
    }

    @Test("CTC startが音声の先頭付近（境界値）")
    func detectAtAudioStart() {
        let audio = synth(regions: [(silent: false, duration: 1.0)])
        let result = OnsetDetector.detect(
            audio: audio,
            sampleRate: sampleRate,
            ctcStart: 0.01,
            silenceThreshold: silenceThreshold
        )
        #expect(result.onsetSec >= 0.0)
        #expect(result.onsetSec <= 0.05)
    }

    @Test("searchFromが指定された場合、その位置から前方スキャンを開始する")
    func detectWithSearchFrom() {
        // 0〜0.3s: 有音(残響)、0.3〜0.6s: 無音、0.6〜1.5s: 有音(本発話)
        let audio = synth(regions: [(silent: false, duration: 0.3),
                                    (silent: true,  duration: 0.3),
                                    (silent: false, duration: 0.9)])
        let ctcStart = 0.5  // 無音区間
        let result = OnsetDetector.detect(
            audio: audio,
            sampleRate: sampleRate,
            ctcStart: ctcStart,
            searchFrom: 0.35,
            silenceThreshold: silenceThreshold
        )
        // searchFromより後の有音区間（0.6秒付近）が検出される
        #expect(result.onsetSec >= 0.55)
        #expect(result.onsetSec <= 0.75)
    }

    @Test("全無音でもonsetSecがクラッシュせずに返る")
    func detectAllSilence() {
        let audio = synth(regions: [(silent: true, duration: 2.0)])
        let result = OnsetDetector.detect(
            audio: audio,
            sampleRate: sampleRate,
            ctcStart: 0.5,
            silenceThreshold: silenceThreshold
        )
        #expect(result.onsetSec >= 0.0)
    }

    @Test("フェーズ2bのdebugNoteが前方シフトを表す（→+ または →±0ms）")
    func detectDebugNoteForwardShift() {
        // 0〜0.5s: 無音、0.5〜1.5s: 有音 → onset(0.5秒) > ctcStart(0.1秒)
        let audio = synth(regions: [(silent: true, duration: 0.5),
                                    (silent: false, duration: 1.0)])
        let result = OnsetDetector.detect(
            audio: audio,
            sampleRate: sampleRate,
            ctcStart: 0.1,
            silenceThreshold: silenceThreshold
        )
        #expect(result.debugNote.hasPrefix("→+") || result.debugNote == "→±0ms")
    }

    @Test("フェーズ2aのdebugNoteが後方シフトを表す（←）")
    func detectDebugNoteBackwardShift() {
        // 0〜0.3s: 無音、0.3〜1.5s: 有音 → onset(0.3秒) < ctcStart(0.8秒)
        let audio = synth(regions: [(silent: true, duration: 0.3),
                                    (silent: false, duration: 1.2)])
        let result = OnsetDetector.detect(
            audio: audio,
            sampleRate: sampleRate,
            ctcStart: 0.8,
            silenceThreshold: silenceThreshold
        )
        #expect(result.debugNote.hasPrefix("←"))
    }

    @Test("瞬間的なノイズ（2フレーム=10ms）は有音として検出されない")
    func detectShortNoisePulseIgnored() {
        // 0〜0.5s: 無音、0.5〜0.51s: 短ノイズ(2フレーム)、0.51〜0.6s: 無音、0.6〜1.5s: 有音
        var audio = synth(regions: [(silent: true, duration: 0.5)])
        let noiseCount = Int(0.010 * Double(sampleRate))  // 10ms = 2フレーム
        audio.append(contentsOf: [Float](repeating: 0.1, count: noiseCount))
        audio.append(contentsOf: synth(regions: [(silent: true, duration: 0.09),
                                                 (silent: false, duration: 0.9)]))
        let result = OnsetDetector.detect(
            audio: audio,
            sampleRate: sampleRate,
            ctcStart: 0.4,
            silenceThreshold: silenceThreshold
        )
        // 短いノイズはスキップされ、0.6秒付近のonsetが検出される
        #expect(result.onsetSec >= 0.55)
    }

    // ────────────────────────────────────────────────────────
    // detectOffset() のテスト
    // ────────────────────────────────────────────────────────

    @Test("フェーズ2a: CTC endが有音 → 前方スキャンでoffsetを検出")
    func detectOffsetPhase2a_voicedAtCTC() {
        // 0〜0.8s: 有音、0.8〜1.5s: 無音
        let audio = synth(regions: [(silent: false, duration: 0.8),
                                    (silent: true,  duration: 0.7)])
        let result = OnsetDetector.detectOffset(
            audio: audio,
            sampleRate: sampleRate,
            ctcEnd: 0.6,
            silenceThreshold: silenceThreshold
        )
        #expect(result.offsetSec >= 0.75)
        #expect(result.offsetSec <= 0.85)
    }

    @Test("フェーズ2b: CTC endが無音 → 逆方向スキャンでoffsetを検出")
    func detectOffsetPhase2b_silentAtCTC() {
        // 0〜0.8s: 有音、0.8〜1.5s: 無音
        let audio = synth(regions: [(silent: false, duration: 0.8),
                                    (silent: true,  duration: 0.7)])
        let result = OnsetDetector.detectOffset(
            audio: audio,
            sampleRate: sampleRate,
            ctcEnd: 1.0,
            silenceThreshold: silenceThreshold
        )
        #expect(result.offsetSec >= 0.78)
        #expect(result.offsetSec <= 0.85)
    }

    @Test("全有音でもoffsetSecがクラッシュせずに返る")
    func detectOffsetAllVoiced() {
        let audio = synth(regions: [(silent: false, duration: 2.0)])
        let result = OnsetDetector.detectOffset(
            audio: audio,
            sampleRate: sampleRate,
            ctcEnd: 1.0,
            silenceThreshold: silenceThreshold
        )
        #expect(result.offsetSec >= 0.0)
    }

    @Test("CTC endが音声末尾を超えていてもクラッシュしない")
    func detectOffsetBeyondAudioEnd() {
        let audio = synth(regions: [(silent: false, duration: 0.5)])
        let result = OnsetDetector.detectOffset(
            audio: audio,
            sampleRate: sampleRate,
            ctcEnd: 2.0,
            silenceThreshold: silenceThreshold
        )
        #expect(result.offsetSec >= 0.0)
    }

    @Test("フェーズ2a: searchEnd まで有音が続く場合、offsetSecが searchEnd を超えない")
    func detectOffsetPhase2a_noSilenceFound() {
        // searchSec(1.5秒)の範囲内で全て有音 → searchEnd = ctcEnd + 1.5s 付近で打ち切られる
        let audio = synth(regions: [(silent: false, duration: 3.0)])
        let ctcEnd = 0.5
        let result = OnsetDetector.detectOffset(
            audio: audio,
            sampleRate: sampleRate,
            ctcEnd: ctcEnd,
            silenceThreshold: silenceThreshold
        )
        // searchEnd = min(audio.count, ctcSample + searchSamples) ≈ 2.0秒
        let expectedMax = ctcEnd + OnsetDetector.searchSec
        #expect(result.offsetSec <= expectedMax + OnsetDetector.frameSec)
        #expect(result.offsetSec >= ctcEnd)
    }
}
