# CLAUDE.md - vtt-synced-voice-whisperkit 開発ガイド

## プロジェクト概要

vtt-synced-voice-whisperkit は、音声ファイルから高精度なタイムスタンプ付きVTTを生成する
Swift Package。WhisperKit を使い、Apple Silicon 上でローカル実行する。
クラウドAPI不要、データがデバイスの外に出ない。

- **入力:** 音声ファイル（.m4a, .wav, .mp3, .aac, .flac, .mp4）
- **出力:** VTT文字列 または SubtitleEntry 配列
- **対象環境:** macOS 14 以降、Apple Silicon（M1/M2/M3/M4）推奨
- **ライセンス:** MIT
- **配布:** GitHub（Swift Package Manager）
- **Python版との関係:** Python版 vtt-synced-voice（WhisperX使用）のSwiftネイティブ移植

### 主な利用者

1. **AutoTrim（FCP用カット編集自動化アプリ）** — SPM依存としてこのパッケージを読み込み、音声ファイルから直接カット編集を実行する
2. **CLIユーザー** — ターミナルから音声ファイルを指定してVTTを生成する
3. **他のSwiftアプリ開発者** — SPM依存として組み込み、音声→字幕機能を追加する

---

## 開発経緯

### speech-swift（Qwen3-ForcedAligner）での試みと中止

前プロジェクト `vtt-synced-voice-swift` では `speech-swift`（`https://github.com/soniqo/speech-swift`）を依存として採用し、
`Qwen3-ForcedAligner + Qwen3-ASR + SileroVAD` によるパイプラインを実装した。
Phase 1（コア実装）・Phase 2（VAD統合）を完了し、日本語音声で動作確認まで行ったが、
**Python版（WhisperX）との精度比較で実用水準に達しないことが判明し、2026-05-21に凍結**した。

### speech-swift の問題点（実測データ）

テスト音声（日本語、約60秒）での比較：

| エントリ | Python版（正解） | Swift/speech-swift版 | 問題 |
|---|---|---|---|
| 1 | `03.449s` 皆さんテロップ作業で消耗していませんか | `03.520s` 皆 / `05.440s` さん | フレーズ分断 |
| 2 | `07.335s` ファイナルカットプロで… | `09.199s` ファイナルカットプロで… | 開始2秒ズレ |
| 3 | `22.636s` 10分の動画… | `25.312s` 10分の動画… | 開始3秒ズレ |
| 4 | `29.636s` 時間がかかるだけではなく集中力が… | `32.399s` …収集 / `35.520s` 力が… | 分断＋誤字 |

根本原因：`Qwen3-ForcedAligner` がワード間に実際には存在しない大きなギャップを割り当てる。
VAD補正やWordGrouperのチューニングでは解決できない精度の問題だった。

### WhisperKit を選んだ理由

| 項目 | WhisperKit | Qwen3-ForcedAligner（旧） |
|---|---|---|
| タイムスタンプ精度 | Whisperベース（実績あり） | 実用水準に達しなかった |
| ワード単位タイムスタンプ | ✅ `WordTiming` 型 | ✅ `AlignedWord` 型（精度不足） |
| VAD | ✅ 内蔵（エネルギーベース） | ✅ SileroVAD（別モデル） |
| 日本語対応 | ✅ 完全対応 | ✅ 完全対応 |
| 開発・メンテ | Argmax社、継続中 | soniqo、不明 |
| 実績 | 広く使われている | 未知数 |

---

## アーキテクチャ

### パイプライン

```
音声ファイル
    ↓
AudioLoader（AVFoundation）
    → PCMサンプル抽出（16kHz、モノラル）
    ↓
WhisperKit
    → VAD内蔵（エネルギーベース、自動チャンク分割）
    → ASR（文字起こし）
    → ワード単位タイムスタンプ（wordTimestamps: true）
    ↓
WordGrouper
    → WordTiming[] → フレーズ単位グループ化
    → 句読点・ギャップ・最大文字数で区切り
    ↓
出力: [SubtitleEntry] または VTT文字列
```

### speech-swift版との比較

| 処理 | speech-swift版 | WhisperKit版 |
|---|---|---|
| ASR | Qwen3-ASR | Whisper（内蔵） |
| アライナー | Qwen3-ForcedAligner | Whisperトークンタイムスタンプ |
| VAD | SileroVAD（別モデル） | エネルギーベース（内蔵） |
| タイムスタンプ補正 | TimestampRefiner.swift | 未定（精度確認後に判断） |

---

## WhisperKit API

### インストール

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "0.9.0"),
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0")
],
targets: [
    .target(
        name: "VTTSyncedVoice",
        dependencies: [
            .product(name: "WhisperKit", package: "argmax-oss-swift")
        ]
    ),
]
```

### 基本的な使い方

```swift
import WhisperKit

let whisperKit = try await WhisperKit(WhisperKitConfig(model: "large-v3-v20240930_626MB"))

var options = DecodingOptions()
options.wordTimestamps = true
options.language = "ja"

if let result = try await whisperKit.transcribe(audioPath: "audio.m4a", decodingOptions: options) {
    for segment in result.segments {
        if let words = segment.words {
            for word in words {
                print("\(word.word): \(word.start) --> \(word.end)")
            }
        }
    }
}
```

### WordTiming 型

```swift
struct WordTiming {
    var word: String
    var tokens: [Int]
    var start: Float      // 秒
    var end: Float        // 秒
    var probability: Float
}
```

### 推奨モデル

| モデル | サイズ | 用途 |
|---|---|---|
| `large-v3-v20240930_626MB` | 約626MB | 最高精度（日本語推奨） |
| `base` | 約74MB | 高速・軽量 |
| `small` | 約244MB | バランス型 |

---

## ディレクトリ構造

```
vtt-synced-voice-whisperkit/
├── Package.swift
├── Sources/
│   ├── VTTSyncedVoice/
│   │   ├── VTTSyncedVoice.swift       ← 公開API（エントリポイント）
│   │   ├── SpeechPipeline.swift       ← WhisperKit呼び出しパイプライン
│   │   ├── WordGrouper.swift          ← WordTiming → フレーズ グループ化
│   │   ├── VTTWriter.swift            ← SubtitleEntry → VTT文字列変換
│   │   ├── AudioLoader.swift          ← 音声ファイル読み込み
│   │   └── SubtitleEntry.swift        ← 公開データモデル
│   └── VTTSyncedVoiceCLI/
│       └── main.swift
├── Tests/
│   └── VTTSyncedVoiceTests/
├── AudioFiles/                        ← テスト用音声（git管理外）
├── VttFiles/                          ← 比較用VTT（Python版の正解データ）
│   └── test_audio_no_merge.vtt        ← Python版の正解（WhisperX出力）
└── CLAUDE.md
```

---

## 公開API（speech-swift版から流用）

### VTTSyncedVoice.swift

```swift
public final class VTTSyncedVoice: Sendable {

    public struct Configuration: Sendable {
        public var language: String = "ja"
        public var phraseGapThreshold: Double = 0.5
        public var model: String = "large-v3-v20240930_626MB"
        public init() {}
    }

    public enum Progress: Sendable {
        case loadingModels
        case downloadingModel(name: String, progress: Double)
        case transcribing
        case grouping
        case completed(entryCount: Int)
    }

    public init(configuration: Configuration = Configuration()) async throws
    public func analyze(audioURL: URL, onProgress: (@Sendable (Progress) -> Void)?) async throws -> [SubtitleEntry]
    public func generateVTT(audioURL: URL, onProgress: (@Sendable (Progress) -> Void)?) async throws -> String
}
```

### SubtitleEntry.swift（変更なし）

```swift
public struct SubtitleEntry: Sendable, Equatable {
    public let startTime: Double
    public let endTime: Double
    public let text: String
}
```

---

## ビルド・実行

```bash
# Xcodeでビルド（⌘+B）— swift buildではなくXcodeビルドが必要
# 理由: WhisperKitのCoreMLモデルはXcodeビルド時にバンドルされる

# 生成バイナリを確認
find ~/Library/Developer/Xcode/DerivedData/vtt-synced-voice-whisperkit-*/Build -name "vtt-synced-voice" -type f

# バイナリ直接実行
<DerivedDataのパス>/vtt-synced-voice AudioFiles/test_audio.m4a --language ja

# テスト
swift test
```

### 初回実行時の注意

- Whisperモデルが HuggingFace からダウンロードされる（large-v3: 約626MB）
- Xcode → Settings → Locations → Command Line Tools を正しいXcodeバージョンに設定すること
  （設定漏れで `MLX error: Failed to load the default metallib` が発生する）

---

## 開発プラン

### Phase 1: 動作確認優先

1. Package.swift 作成、WhisperKit 依存追加
2. speech-swift版からファイルを流用（SubtitleEntry, VTTWriter, WordGrouper, AudioLoader, CLIツール）
3. SpeechPipeline.swift を WhisperKit で書き直す
4. VTTSyncedVoice.swift を WhisperKit 対応に更新
5. 日本語音声で動作確認
6. **Python版との精度比較**（ここで精度が出なければ方針を再検討）

### Phase 2: 精度向上

7. 波形レベルの onset 補正を追加（TimestampRefiner + AudioLoader + OnsetDetector）
8. WordGrouperのギャップ閾値チューニング
9. モデルバリアントの比較（large-v3 vs small）

#### Phase 2 詳細：onset補正アーキテクチャ

Python版 `vtt-synced-voice`（`/Users/user_name/GitHub-imin-minnade/vtt-synced-voice-dev`）の
`onset.py` / `transcriber.py` を参考に実装する。

**処理フロー:**
```
音声ファイル
    ↓
AudioLoader（AVFoundation）
    → 16kHz / モノラル PCM [Float] を抽出
    → ピーク正規化（audio / max(abs(audio))）
    ↓
WhisperKit（既存）
    → WordTiming[] を取得
    ↓
WordGrouper（既存）
    → SubtitleEntry[] を生成
    ↓
TimestampRefiner（新規）
    → 各エントリの startTime に OnsetDetector を適用
    → startTime = onset - marginBefore
    → endTime を次エントリの start - 0.1s でクランプ
    ↓
出力: [SubtitleEntry]
```

**OnsetDetector（`onset.py` の Swift 移植）:**

2フェーズ処理（フレームサイズ: 5ms = 80サンプル @ 16kHz、探索範囲: ±300ms）:
- フェーズ1: CTC start 付近 3フレーム（15ms）の最大RMSで有音/無音を判定
- フェーズ2a（有音）: 逆方向スキャンで最初の無音フレームを探す → その終端 = onset
- フェーズ2b（無音）: 前方スキャンで最初の有音フレームを探す → その先頭 = onset

**RMS計算: Accelerate フレームワーク（vDSP）を使用**
- `vDSP.rootMeanSquare()` でSIMD演算による高速化
- 追加依存なし（Apple標準フレームワーク）
- Python版の `np.sqrt(np.mean(frame ** 2))` と等価

**パラメータ（`Configuration` に追加）:**
- `silenceThreshold: Double = 0.001`（ピーク正規化後のRMS閾値）
- `marginBefore: Double = 0.066`（onset検出後に早める秒数 = 30fps×2フレーム）
- `marginAfter: Double = 0.0`（終了時刻を延ばす秒数）

**目標精度:** 33ms（30fps 1フレーム）

**VAD手法の選定経緯（2026-05-21調査）:**

| 手法 | 精度 | 依存 | 採用 |
|---|---|---|---|
| RMS + vDSP（Accelerate） | 5ms | なし（Apple標準） | ✅ 採用 |
| RMS スキャン（生ループ） | 5ms | なし | Python版と同等だが低速 |
| AVAudioEngine タップ | ~256ms | なし | 粗すぎ |
| SileroVAD（MLモデル） | 32ms | speech-swift等 | 依存追加が必要 |
| Core ML カスタムVAD | 32ms | モデル変換 | 工数大 |

うまくいかない場合は SileroVAD（選択肢4）に切り替える。

### Phase 3: テスト・公開

10. ユニットテスト
11. README作成
12. GitHub公開
13. AutoTrim統合テスト

---

## 精度検証方法

Python版の正解VTTと比較する：

```bash
# Python版（正解）: VttFiles/test_audio_no_merge.vtt
# Swift版の出力と比較
python3 Examples/compare_vtt.py VttFiles/test_audio_no_merge.vtt result.vtt
```

目標: 全エントリのタイムスタンプ差が33ms以内（30fps換算で1フレーム）

---

## 署名・配布情報

- **GitHub:** https://github.com/mikai-daichi/vtt-synced-voice-whisperkit
- **ブランド名:** ミカイ｜プログラミング×創作
- **公開メール:** mikai.daichi@gmail.com
- **ライセンス:** MIT
- **Python版:** https://github.com/mikai-daichi/vtt-synced-voice
- **旧Swift版（凍結）:** https://github.com/mikai-daichi/vtt-synced-voice-swift
