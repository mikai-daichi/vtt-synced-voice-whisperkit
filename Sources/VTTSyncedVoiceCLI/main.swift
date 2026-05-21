import Foundation
import Accelerate
import ArgumentParser
import VTTSyncedVoice

struct VTTSyncedVoiceCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "vtt-synced-voice",
        abstract: "Generate timestamped VTT subtitles from audio files using WhisperKit"
    )

    @Argument(help: "Input audio file path")
    var audioFile: String

    @Option(name: .shortAndLong, help: "Language code (e.g. ja, en)")
    var language: String = "ja"

    @Option(name: .shortAndLong, help: "Output VTT file path (default: stdout)")
    var output: String?

    @Option(name: .long, help: "Phrase gap threshold in seconds")
    var gapThreshold: Double = 0.5

    @Option(name: .long, help: "WhisperKit model name")
    var model: String = "large-v3-v20240930_626MB"

    @Flag(name: .long, help: "Dump raw word timings from WhisperKit before grouping")
    var dumpWords: Bool = false

    @Flag(name: .long, help: "Show onset correction details for each entry")
    var verbose: Bool = false

    @Flag(name: .long, help: "Merge phrase entries into sentence units (split on 。！？!?)")
    var mergeSentences: Bool = false

    @Flag(name: .long, help: "Pass punctuation hint tokens to WhisperKit to encourage punctuation output (limited effect)")
    var punctuationHint: Bool = false

    @Option(name: .long, help: "Dump RMS values around a specific time (seconds) for waveform investigation")
    var dumpRmsAt: Double?

    @Option(name: .long, help: "Seconds to shift subtitle start earlier (default: 0.033)")
    var marginBefore: Double = 0.033

    @Option(name: .long, help: "Seconds to extend subtitle end later (default: 0.2)")
    var marginAfter: Double = 0.2

    mutating func run() throws {
        var config = VTTSyncedVoice.Configuration()
        config.language = language
        config.phraseGapThreshold = gapThreshold
        config.model = model
        config.marginBefore = marginBefore
        config.marginAfter = marginAfter
        config.mergeSentences = mergeSentences
        config.punctuationHint = punctuationHint

        let audioURL = URL(fileURLWithPath: audioFile)
        let outputPath = output
        let capturedConfig = config
        let shouldDumpWords = dumpWords
        let isVerbose = verbose
        let dumpRmsAtTime = dumpRmsAt

        try runAsync {
            // --dump-rms-at: Whisperモデル不要、波形だけ読んで終了
            if let targetSec = dumpRmsAtTime {
                let audio = try AudioLoader.loadNormalized(url: audioURL)
                let sampleRate = 16000
                let frameSize = max(1, Int(0.005 * Double(sampleRate)))  // 5ms
                let windowSec = 0.5  // 前後0.5秒を表示
                let startSample = max(0, Int((targetSec - windowSec) * Double(sampleRate)))
                let endSample   = min(audio.count, Int((targetSec + windowSec) * Double(sampleRate)))
                fputs(String(format: "RMS dump: %.3fs ± %.1fs  (threshold=0.001)\n", targetSec, windowSec), stderr)
                fputs("    time      RMS        判定\n", stderr)
                var pos = startSample
                while pos + frameSize <= endSample {
                    let slice = Array(audio[pos..<pos + frameSize])
                    var rmsVal: Float = 0
                    vDSP_rmsqv(slice, 1, &rmsVal, vDSP_Length(slice.count))
                    let t = Double(pos) / Double(sampleRate)
                    let marker = pos == Int(targetSec * Double(sampleRate)) ? " ← CTC" : ""
                    fputs(String(format: "  %7.3f   %.6f   %@%@\n",
                        t, rmsVal, rmsVal > 0.001 ? "有音" : "無音", marker), stderr)
                    pos += frameSize
                }
                return
            }

            let analyzer = try await VTTSyncedVoice(configuration: capturedConfig)

            if shouldDumpWords {
                let words = try await analyzer.words(audioURL: audioURL)
                for w in words {
                    fputs(String(format: "%7.3f --> %7.3f  %@\n", w.start, w.end, w.word), stderr)
                }
                return
            }

            if isVerbose {
                let (entries, debug) = try await analyzer.analyzeVerbose(audioURL: audioURL) { progress in
                    switch progress {
                    case .loadingModels: fputs("Loading models...\n", stderr)
                    case .downloadingModel(let name, let p): fputs("Downloading \(name): \(Int(p * 100))%\n", stderr)
                    case .transcribing: fputs("Transcribing...\n", stderr)
                    case .grouping: fputs("Grouping phrases...\n", stderr)
                    case .refining: fputs("Refining timestamps (onset)...\n", stderr)
                    case .completed(let count): fputs("Done: \(count) entries\n", stderr)
                    }
                }
                fputs("\n--- onset/offset補正結果 ---\n", stderr)
                fputs("  [idx] start: CTC→onset→final (note)  |  end: CTC→offset→final (note)  text\n", stderr)
                for d in debug {
                    fputs(String(format: "  [%2d] S:%7.3f→%7.3f→%7.3f (%@)  E:%7.3f→%7.3f→%7.3f (%@)  「%@」\n",
                        d.index,
                        d.ctcStart, d.onsetSec, d.finalStart, d.noteStart,
                        d.ctcEnd, d.offsetSec, d.finalEnd, d.noteEnd,
                        String(d.text.prefix(15))), stderr)
                }
                let vtt = VTTWriter.write(entries: entries)
                if let path = outputPath {
                    try vtt.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
                } else {
                    print(vtt)
                }
                return
            }

            let vtt = try await analyzer.generateVTT(audioURL: audioURL) { progress in
                switch progress {
                case .loadingModels:
                    fputs("Loading models...\n", stderr)
                case .downloadingModel(let name, let p):
                    fputs("Downloading \(name): \(Int(p * 100))%\n", stderr)
                case .transcribing:
                    fputs("Transcribing...\n", stderr)
                case .grouping:
                    fputs("Grouping phrases...\n", stderr)
                case .refining:
                    fputs("Refining timestamps (onset)...\n", stderr)
                case .completed(let count):
                    fputs("Done: \(count) entries\n", stderr)
                }
            }
            if let path = outputPath {
                try vtt.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
            } else {
                print(vtt)
            }
        }
    }
}

func runAsync(_ body: @Sendable @escaping () async throws -> Void) throws {
    let sema = DispatchSemaphore(value: 0)
    let box = ErrorBox()
    Task.detached {
        do {
            try await body()
        } catch {
            box.error = error
        }
        sema.signal()
    }
    sema.wait()
    if let error = box.error { throw error }
}

final class ErrorBox: @unchecked Sendable {
    var error: Error?
}

VTTSyncedVoiceCLI.main()
