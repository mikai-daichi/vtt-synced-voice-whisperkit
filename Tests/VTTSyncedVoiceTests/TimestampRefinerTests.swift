import Testing
@testable import VTTSyncedVoice

@Suite("TimestampRefiner")
struct TimestampRefinerTests {

    let sampleRate = 16000

    private func synth(regions: [(silent: Bool, duration: Double)]) -> [Float] {
        var samples: [Float] = []
        for (silent, duration) in regions {
            let count = Int(duration * Double(sampleRate))
            samples.append(contentsOf: [Float](repeating: silent ? 0.0 : 0.1, count: count))
        }
        return samples
    }

    // ── 基本動作 ────────────────────────────────────────────

    @Test("空エントリ列は空を返す")
    func emptyEntriesReturnsEmpty() {
        let audio = synth(regions: [(silent: false, duration: 1.0)])
        let (entries, debug) = TimestampRefiner.refine(entries: [], audio: audio)
        #expect(entries.isEmpty)
        #expect(debug.isEmpty)
    }

    @Test("出力エントリ数は入力エントリ数と同じ")
    func outputCountMatchesInput() {
        let audio = synth(regions: [
            (silent: false, duration: 0.5), (silent: true, duration: 0.5),
            (silent: false, duration: 0.5), (silent: true, duration: 0.5),
            (silent: false, duration: 0.5), (silent: true, duration: 0.5)
        ])
        let entries = [
            SubtitleEntry(startSeconds: 0.0, endSeconds: 0.5, text: "A"),
            SubtitleEntry(startSeconds: 1.0, endSeconds: 1.5, text: "B"),
            SubtitleEntry(startSeconds: 2.0, endSeconds: 2.5, text: "C")
        ]
        let (result, _) = TimestampRefiner.refine(entries: entries, audio: audio, sampleRate: sampleRate)
        #expect(result.count == 3)
    }

    @Test("debugエントリのindexとtextが入力エントリと対応する")
    func debugIndexAndTextMatch() {
        let audio = synth(regions: [(silent: false, duration: 2.0)])
        let entries = [
            SubtitleEntry(startSeconds: 0.2, endSeconds: 0.8, text: "first"),
            SubtitleEntry(startSeconds: 1.0, endSeconds: 1.6, text: "second")
        ]
        let (_, debug) = TimestampRefiner.refine(entries: entries, audio: audio, sampleRate: sampleRate)
        #expect(debug[0].index == 0)
        #expect(debug[0].text == "first")
        #expect(debug[1].index == 1)
        #expect(debug[1].text == "second")
    }

    // ── onset補正の方向性検証 ─────────────────────────────────

    @Test("CTC startが無音区間 → onsetが前方に移動してstartが変化する")
    func startShiftsForwardWhenCTCInSilence() {
        // 0〜0.5s: 無音、0.5〜2.0s: 有音
        let audio = synth(regions: [(silent: true, duration: 0.5),
                                    (silent: false, duration: 1.5)])
        let ctcStart = 0.2  // 無音区間内
        let entry = SubtitleEntry(startSeconds: ctcStart, endSeconds: 1.8, text: "test")
        let config = TimestampRefiner.Config(
            marginBefore: 0.0, marginAfter: 0.0, silenceThreshold: 0.001, minGapToNext: 0.0
        )
        let (result, _) = TimestampRefiner.refine(
            entries: [entry], audio: audio, sampleRate: sampleRate, config: config
        )
        // onsetSec ≈ 0.5 > ctcStart(0.2)
        #expect(result[0].startSeconds > ctcStart)
    }

    @Test("CTC endが有音区間 → offsetが前方に延びてendが変化する")
    func endExtendsWhenCTCVoiced() {
        // 0〜1.0s: 有音、1.0〜2.0s: 無音
        let audio = synth(regions: [(silent: false, duration: 1.0),
                                    (silent: true,  duration: 1.0)])
        let ctcEnd = 0.8  // 有音区間内
        let entry = SubtitleEntry(startSeconds: 0.1, endSeconds: ctcEnd, text: "test")
        let config = TimestampRefiner.Config(
            marginBefore: 0.0, marginAfter: 0.0, silenceThreshold: 0.001, minGapToNext: 0.0
        )
        let (result, _) = TimestampRefiner.refine(
            entries: [entry], audio: audio, sampleRate: sampleRate, config: config
        )
        // offsetSec ≈ 1.0 > ctcEnd(0.8)
        #expect(result[0].endSeconds > ctcEnd)
    }

    // ── marginBefore/marginAfter の適用 ──────────────────────

    @Test("marginBefore だけonsetSecより早いstartになる")
    func marginBeforeApplied() {
        // 0〜0.3s: 無音、0.3〜2.0s: 有音
        let audio = synth(regions: [(silent: true, duration: 0.3),
                                    (silent: false, duration: 1.7)])
        let entry = SubtitleEntry(startSeconds: 0.1, endSeconds: 1.8, text: "test")
        let config = TimestampRefiner.Config(
            marginBefore: 0.033, marginAfter: 0.0, silenceThreshold: 0.001, minGapToNext: 0.0
        )
        let (result, debug) = TimestampRefiner.refine(
            entries: [entry], audio: audio, sampleRate: sampleRate, config: config
        )
        let expected = max(0.0, debug[0].onsetSec - 0.033)
        #expect(abs(result[0].startSeconds - expected) < 1e-6)
    }

    @Test("marginAfter だけoffsetSecより遅いendになる")
    func marginAfterApplied() {
        // 0〜1.0s: 有音、1.0〜2.0s: 無音
        let audio = synth(regions: [(silent: false, duration: 1.0),
                                    (silent: true,  duration: 1.0)])
        let entry = SubtitleEntry(startSeconds: 0.0, endSeconds: 0.9, text: "test")
        let config = TimestampRefiner.Config(
            marginBefore: 0.0, marginAfter: 0.2, silenceThreshold: 0.001, minGapToNext: 0.0
        )
        let (result, debug) = TimestampRefiner.refine(
            entries: [entry], audio: audio, sampleRate: sampleRate, config: config
        )
        let expected = debug[0].offsetSec + 0.2
        #expect(abs(result[0].endSeconds - expected) < 1e-6)
    }

    // ── startが0未満にならない ────────────────────────────────

    @Test("onsetSecがmarginBeforeより小さくてもstartSecondsは0以上")
    func startSecondsNeverNegative() {
        let audio = synth(regions: [(silent: false, duration: 2.0)])
        let entry = SubtitleEntry(startSeconds: 0.01, endSeconds: 1.5, text: "test")
        let config = TimestampRefiner.Config(
            marginBefore: 0.1, marginAfter: 0.0, silenceThreshold: 0.001, minGapToNext: 0.0
        )
        let (result, _) = TimestampRefiner.refine(
            entries: [entry], audio: audio, sampleRate: sampleRate, config: config
        )
        #expect(result[0].startSeconds >= 0.0)
    }

    // ── endクランプ ────────────────────────────────────────

    @Test("endSecが次エントリのstart - minGapToNextを超えない")
    func endClampedToNextEntryStart() {
        // 連続有音（endが延びてクランプが発動しやすい）
        let audio = synth(regions: [(silent: false, duration: 4.0)])
        let entries = [
            SubtitleEntry(startSeconds: 0.0, endSeconds: 1.5, text: "A"),
            SubtitleEntry(startSeconds: 1.6, endSeconds: 3.0, text: "B")
        ]
        let config = TimestampRefiner.Config(
            marginBefore: 0.0, marginAfter: 0.2, silenceThreshold: 0.001, minGapToNext: 0.1
        )
        let (result, _) = TimestampRefiner.refine(
            entries: entries, audio: audio, sampleRate: sampleRate, config: config
        )
        #expect(result[0].endSeconds <= result[1].startSeconds - config.minGapToNext + 1e-9)
    }

    // ── startクランプ ──────────────────────────────────────

    @Test("startSecが前エントリのend + minGapToNextより前にならない")
    func startClampedToPrevEntryEnd() {
        // 密接した2エントリ
        let audio = synth(regions: [(silent: false, duration: 4.0)])
        let entries = [
            SubtitleEntry(startSeconds: 0.0, endSeconds: 1.5, text: "A"),
            SubtitleEntry(startSeconds: 1.55, endSeconds: 3.0, text: "B")
        ]
        let config = TimestampRefiner.Config(
            marginBefore: 0.1, marginAfter: 0.2, silenceThreshold: 0.001, minGapToNext: 0.1
        )
        let (result, _) = TimestampRefiner.refine(
            entries: entries, audio: audio, sampleRate: sampleRate, config: config
        )
        #expect(result[1].startSeconds >= result[0].endSeconds + config.minGapToNext - 1e-9)
    }

    // ── 最後のエントリの無音末尾補正 ─────────────────────────

    @Test("最後のエントリのendが無音領域にある場合、有音まで遡って修正される")
    func lastEntryEndCorrectedFromSilence() {
        // 0〜0.8s: 有音、0.8〜2.0s: 無音
        let audio = synth(regions: [(silent: false, duration: 0.8),
                                    (silent: true,  duration: 1.2)])
        let entry = SubtitleEntry(startSeconds: 0.0, endSeconds: 1.5, text: "last")
        let config = TimestampRefiner.Config(
            marginBefore: 0.0, marginAfter: 0.0, silenceThreshold: 0.001, minGapToNext: 0.0
        )
        let (result, _) = TimestampRefiner.refine(
            entries: [entry], audio: audio, sampleRate: sampleRate, config: config
        )
        // 無音領域(1.5秒)より小さい値に修正される
        #expect(result[0].endSeconds < 1.5)
        #expect(result[0].endSeconds >= 0.0)
    }

    @Test("最後のエントリのendが有音領域にある場合は末尾補正が発動しない")
    func lastEntryEndNotModifiedWhenVoiced() {
        // 全体が有音
        let audio = synth(regions: [(silent: false, duration: 2.0)])
        let entry = SubtitleEntry(startSeconds: 0.0, endSeconds: 1.0, text: "last")
        let config = TimestampRefiner.Config(
            marginBefore: 0.0, marginAfter: 0.0, silenceThreshold: 0.001, minGapToNext: 0.0
        )
        let (_, debug) = TimestampRefiner.refine(
            entries: [entry], audio: audio, sampleRate: sampleRate, config: config
        )
        // 有音区間なので末尾補正は発動しない
        #expect(debug[0].noteEnd != "←last-silence-scan")
    }

    // ── Config デフォルト値の検証 ─────────────────────────────

    @Test("Configのデフォルト値が仕様通り")
    func configDefaultValues() {
        let config = TimestampRefiner.Config()
        #expect(config.marginBefore == 0.033)
        #expect(config.marginAfter == 0.2)
        #expect(config.silenceThreshold == 0.001)
        #expect(config.minGapToNext == 0.1)
    }

    @Test("DebugEntryにCTCの元の値が保存されている")
    func debugEntryPreservesOriginalCTC() {
        let audio = synth(regions: [(silent: false, duration: 2.0)])
        let entry = SubtitleEntry(startSeconds: 0.3, endSeconds: 1.2, text: "check")
        let config = TimestampRefiner.Config(
            marginBefore: 0.0, marginAfter: 0.0, silenceThreshold: 0.001, minGapToNext: 0.0
        )
        let (_, debug) = TimestampRefiner.refine(
            entries: [entry], audio: audio, sampleRate: sampleRate, config: config
        )
        #expect(debug[0].ctcStart == 0.3)
        #expect(debug[0].ctcEnd == 1.2)
    }
}
