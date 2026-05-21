# vtt-synced-voice-whisperkit

[WhisperKit](https://github.com/argmaxinc/WhisperKit) を使って音声ファイルからタイムスタンプ付き WebVTT 字幕を生成する Swift パッケージです。Apple Silicon 上で完全にオンデバイス動作します。クラウド API 不要、データがデバイスの外に出ません。

## 特徴

- WhisperKit によるワード単位タイムスタンプ（Whisper large-v3）
- 波形レベルの onset/offset 補正で ±33ms（30fps 換算 1 フレーム）精度
- 幻聴フィルタ — 音声ファイルの長さを超えて生成された幻聴ワードを除去
- WebVTT 文字列または `[SubtitleEntry]` 配列で出力
- Swift 6 並行処理対応（`Sendable`、actor セーフ）
- CLI ツール同梱

## 動作環境

- macOS 14 以降
- Apple Silicon（M1/M2/M3/M4）推奨
- Xcode 16 以降（CoreML モデルのバンドルに必要。`swift build` 単独では動作しません）

## インストール

`Package.swift` に追加してください：

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

## 使い方

### Swift ライブラリとして

```swift
import VTTSyncedVoice

// WebVTT 文字列を生成
let analyzer = try await VTTSyncedVoice()
let vtt = try await analyzer.generateVTT(audioURL: audioURL) { progress in
    switch progress {
    case .loadingModels:    print("モデル読み込み中...")
    case .transcribing:     print("文字起こし中...")
    case .grouping:         print("フレーズグループ化中...")
    case .refining:         print("タイムスタンプ補正中...")
    case .completed(let n): print("完了: \(n) エントリ")
    default: break
    }
}
print(vtt)

// SubtitleEntry 配列を直接取得
let entries = try await analyzer.analyze(audioURL: audioURL)
```

**カスタム設定：**

```swift
var config = VTTSyncedVoice.Configuration()
config.language = "ja"                     // 言語コード（デフォルト: "ja"）
config.model = "large-v3-v20240930_626MB"  // WhisperKit モデル名（デフォルト: large-v3-v20240930_626MB）
config.phraseGapThreshold = 0.5            // フレーズ分割の無音閾値（デフォルト: 0.5 秒）
config.marginBefore = 0.033               // onset から開始時刻を早める余白（デフォルト: 0.033 秒）
config.marginAfter  = 0.2                 // offset から終了時刻を延ばす余白（デフォルト: 0.2 秒）
config.silenceThreshold = 0.001           // 無音判定の RMS 閾値（デフォルト: 0.001）

let analyzer = try await VTTSyncedVoice(configuration: config)
```

### CLI

リポジトリをクローンしてそのルートから実行：

```bash
git clone https://github.com/mikai-daichi/vtt-synced-voice-whisperkit.git
cd vtt-synced-voice-whisperkit
swift run -c release vtt-synced-voice audio.m4a --language ja --output subtitles.vtt
```

初回実行時に Whisper モデルが自動ダウンロードされます（large-v3 は約 626 MB）。

**全オプション：**

```
USAGE: vtt-synced-voice <audio-file> [OPTIONS]

ARGUMENTS:
  <audio-file>            入力音声ファイルのパス

OPTIONS:
  -l, --language <code>   言語コード（デフォルト: ja）
  -o, --output <path>     出力 VTT ファイルパス（デフォルト: 標準出力）
  --gap-threshold <sec>   フレーズ分割の無音閾値（デフォルト: 0.5 秒）
  --model <name>          WhisperKit モデル名（デフォルト: large-v3-v20240930_626MB）
  --margin-before <sec>   onset から開始時刻を早める余白（デフォルト: 0.033 秒）
  --margin-after <sec>    offset から終了時刻を延ばす余白（デフォルト: 0.2 秒）
  --dump-words            WhisperKit の生ワードタイムスタンプを stderr に出力
  --verbose               エントリごとの onset/offset 補正詳細を表示
  --dump-rms-at <sec>     指定時刻 ±0.5 秒の RMS 値をダンプ（波形調査用）
  -h, --help              ヘルプを表示
```

**`--verbose` 出力例：**

```
[idx] S: CTC→onset→final (note)  |  E: CTC→offset→final (note)  text
[ 0] S:  3.449→ 3.416→ 3.383 (←-33ms)  E: 6.120→ 6.120→ 6.153 (→±0ms)  「皆さんテロップ作業で」
```

## 対応音声フォーマット

`.m4a`, `.wav`, `.mp3`, `.aac`, `.flac`, `.mp4`

## モデル

| モデル | サイズ | 備考 |
|---|---|---|
| `large-v3-v20240930_626MB` | 約 626 MB | 最高精度、日本語推奨 |
| `small` | 約 244 MB | バランス型 |
| `base` | 約 74 MB | 高速・軽量 |

初回実行時に Hugging Face からモデルが自動ダウンロードされます（large-v3 は約 626 MB）。以降は キャッシュが使われます。

## 注意事項

- **`swift run` または Xcode を使用**：WhisperKit はモデルを実行時にダウンロードするため、`swift run` で動作します。`swift build` で生成したバイナリは実行ディレクトリによってモデルの検索に失敗する場合があります。
- **Command Line Tools の設定**：Xcode → Settings → Locations → Command Line Tools が正しい Xcode バージョンを指していることを確認してください。設定が誤っていると `MLX error: Failed to load the default metallib` が発生します。
- **繰り返し発話**：WhisperKit（および Whisper ベースのモデル全般）は、同じフレーズの繰り返しをスキップまたは折りたたむことがあります。これは Whisper アーキテクチャの既知の制限事項です。

## ライセンス

MIT License

Copyright (c) 2026 mikai-daichi

本ソフトウェアおよび関連するドキュメントファイル（以下「ソフトウェア」）のコピーを取得するすべての人に対し、無償で、ソフトウェアを制限なく取り扱う権限を付与します。これには、ソフトウェアのコピーを使用、複製、変更、統合、掲載、頒布、サブライセンス、および販売する権利、ならびにソフトウェアを提供する相手に同様のことを許可する権利が含まれますが、これらに限りません。

上記の著作権表示および本許諾表示を、ソフトウェアのすべてのコピーまたは重要な部分に記載するものとします。

ソフトウェアは「現状のまま」提供されるものとし、明示または黙示を問わず、商品性、特定目的への適合性、および権利侵害の不存在に関する保証を含むがこれらに限らない、いかなる種類の保証もありません。
