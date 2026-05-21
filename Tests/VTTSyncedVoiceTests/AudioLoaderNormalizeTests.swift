import Testing
@testable import VTTSyncedVoice

@Suite("AudioLoader.normalize")
struct AudioLoaderNormalizeTests {

    @Test("最大値が1.0に正規化される")
    func peakBecomesOne() {
        let samples: [Float] = [0.0, 0.5, -1.0, 0.25]
        let result = AudioLoader.normalize(samples)
        let peak = result.map { abs($0) }.max()!
        #expect(abs(peak - 1.0) < 1e-6)
    }

    @Test("負のピークを持つ場合も正しく正規化される")
    func negativePeak() {
        let samples: [Float] = [0.2, -0.8, 0.4]
        let result = AudioLoader.normalize(samples)
        #expect(abs(result[0] - 0.25) < 1e-6)
        #expect(abs(result[1] - (-1.0)) < 1e-6)
        #expect(abs(result[2] - 0.5) < 1e-6)
    }

    @Test("全ゼロ配列はそのまま返される（ゼロ除算防止）")
    func allZeroSamplesUnchanged() {
        let samples: [Float] = [0.0, 0.0, 0.0]
        let result = AudioLoader.normalize(samples)
        #expect(result == [0.0, 0.0, 0.0])
    }

    @Test("単一要素配列が1.0に正規化される")
    func singleElementBecomesOne() {
        let samples: [Float] = [0.3]
        let result = AudioLoader.normalize(samples)
        #expect(abs(result[0] - 1.0) < 1e-6)
    }

    @Test("既に正規化済みの配列は変わらない")
    func alreadyNormalizedUnchanged() {
        let samples: [Float] = [0.5, -1.0, 0.25, -0.75]
        let result = AudioLoader.normalize(samples)
        for (a, b) in zip(samples, result) {
            #expect(abs(a - b) < 1e-6)
        }
    }

    @Test("空配列は空配列を返す")
    func emptyArrayReturnsEmpty() {
        let result = AudioLoader.normalize([])
        #expect(result.isEmpty)
    }
}
