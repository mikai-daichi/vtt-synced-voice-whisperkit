# vtt-synced-voice-whisperkit

[日本語版 README はこちら](README.ja.md)

A Swift package that generates timestamped WebVTT subtitles from audio files using [WhisperKit](https://github.com/argmaxinc/WhisperKit). Runs entirely on-device on Apple Silicon — no cloud API, no data leaves your machine.

## Features

- Word-level timestamps via WhisperKit (Whisper large-v3)
- Waveform-based onset/offset correction for ±33ms (1 frame @ 30fps) accuracy
- Hallucination filtering — removes phantom words generated beyond actual audio duration
- Sentence-unit merging for Japanese (`--merge-sentences`) — merges phrase-split entries into natural sentence units using Japanese sentence-ending patterns (です/ます/etc.)
- Outputs WebVTT string or `[SubtitleEntry]` array
- Swift 6 concurrency (`Sendable`, actor-safe)
- CLI tool included

## Requirements

- macOS 14+
- Apple Silicon (M1/M2/M3/M4) recommended
- Xcode 16+ (required to bundle CoreML models; `swift build` alone is not sufficient)

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mikai-daichi/vtt-synced-voice-whisperkit.git", from: "0.1.0")
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "VTTSyncedVoice", package: "vtt-synced-voice-whisperkit")
        ]
    )
]
```

## Usage

### As a Swift library

```swift
import VTTSyncedVoice

// Generate WebVTT string
let analyzer = try await VTTSyncedVoice()
let vtt = try await analyzer.generateVTT(audioURL: audioURL) { progress in
    switch progress {
    case .loadingModels:   print("Loading models...")
    case .transcribing:    print("Transcribing...")
    case .grouping:        print("Grouping phrases...")
    case .refining:        print("Refining timestamps...")
    case .completed(let n): print("Done: \(n) entries")
    default: break
    }
}
print(vtt)

// Or get SubtitleEntry array directly
let entries = try await analyzer.analyze(audioURL: audioURL)
```

**Custom configuration:**

```swift
var config = VTTSyncedVoice.Configuration()
config.language = "ja"                     // language code (default: "ja")
config.model = "large-v3-v20240930_626MB"  // WhisperKit model name (default: large-v3-v20240930_626MB)
config.phraseGapThreshold = 0.5            // silence gap to split phrases (default: 0.5s)
config.marginBefore = 0.033               // shift subtitle start earlier from onset (default: 0.033s)
config.marginAfter  = 0.2                 // extend subtitle end after offset (default: 0.2s)
config.silenceThreshold = 0.001           // RMS threshold for silence detection (default: 0.001)
config.mergeSentences = false              // merge entries into sentence units — Japanese only (default: false)
config.punctuationHint = false             // hint WhisperKit to output punctuation — Japanese only (default: false)
config.replacementRules = try TextReplacer.loadCSV(url: URL(fileURLWithPath: "replace.csv"))  // text replacement rules (default: [])

let analyzer = try await VTTSyncedVoice(configuration: config)
```

### CLI

Clone the repository and run from its root:

```bash
git clone https://github.com/mikai-daichi/vtt-synced-voice-whisperkit.git
cd vtt-synced-voice-whisperkit
swift run -c release vtt-synced-voice AudioFiles/audio.m4a --language ja --output VttFiles/subtitles.vtt
```

The Whisper model is downloaded automatically on first run (~626 MB for large-v3).

**All options:**

```
USAGE: vtt-synced-voice <audio-file> [OPTIONS]

ARGUMENTS:
  <audio-file>            Input audio file path

OPTIONS:
  -l, --language <code>   Language code (default: ja)
  -o, --output <path>     Output VTT file path (default: stdout)
  --gap-threshold <sec>   Phrase gap threshold in seconds (default: 0.5)
  --model <name>          WhisperKit model name (default: large-v3-v20240930_626MB)
  --margin-before <sec>   Shift subtitle start earlier from onset (default: 0.033)
  --margin-after <sec>    Extend subtitle end after offset (default: 0.2)
  --replace-list <path>   Path to CSV file with replacement rules (from,to per line)
  --merge-sentences       Merge entries into sentence units (Japanese only)
  --punctuation-hint      Hint WhisperKit to output punctuation (Japanese only)
  --dump-words            Dump raw word timings from WhisperKit to stderr
  --verbose               Show onset/offset correction details per entry
  --dump-rms-at <sec>     Dump RMS values ±0.5s around specified time
  -h, --help              Show help
```

**Verbose output example:**

```
[idx] S: CTC→onset→final (note)  |  E: CTC→offset→final (note)  text
[ 0] S:  3.449→ 3.416→ 3.383 (←-33ms)  E: 6.120→ 6.120→ 6.153 (→±0ms)  「皆さんテロップ作業で」
```

## Supported Audio Formats

`.m4a`, `.wav`, `.mp3`, `.aac`, `.flac`, `.mp4`

## Models

| Model | Size | Notes |
|---|---|---|
| `large-v3-v20240930_626MB` | ~626 MB | Best accuracy, recommended for Japanese |
| `small` | ~244 MB | Balanced |
| `base` | ~74 MB | Fast, lightweight |

The model is downloaded from Hugging Face on first run (~626 MB for large-v3).

## Notes

- **Use `swift run` or Xcode, not `swift build`**: The CLI works with `swift run` because WhisperKit downloads its models at runtime. A bare `swift build` binary may fail to locate models depending on the working directory.
- **First run**: The Whisper model (~626 MB) is downloaded from Hugging Face automatically. Subsequent runs use the cached model.
- **Xcode Command Line Tools**: Make sure Xcode → Settings → Locations → Command Line Tools points to the correct Xcode version. A misconfigured setting causes `MLX error: Failed to load the default metallib`.
- **Replacement list CSV format**: One rule per line, `from,to`. Blank lines and lines starting with `#` are treated as comments. If the replacement value itself contains a comma, only the first comma is used as the delimiter (`a,b,c` replaces `a` with `b,c`). BOM-prefixed UTF-8 is also supported.
- **Repeated speech**: WhisperKit (like all Whisper-based models) may skip or collapse repeated phrases. This is a known limitation of the Whisper architecture.

## License

MIT License

Copyright (c) 2026 mikai-daichi

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
