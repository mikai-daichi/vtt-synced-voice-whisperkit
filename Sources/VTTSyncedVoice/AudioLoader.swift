import Foundation
import AVFoundation

public enum AudioLoader {

    public enum Error: Swift.Error {
        case fileNotFound(URL)
        case formatConversionFailed
        case readFailed(Swift.Error)
        case emptyAudio
    }

    /// 音声ファイルを16kHz/モノラルPCMとして読み込み、ピーク正規化して返す。
    /// ピーク正規化: audio / max(abs(audio)) — Python版と同一の前処理。
    public static func loadNormalized(url: URL, targetSampleRate: Int = 16000) throws -> [Float] {
        let samples = try load(url: url, targetSampleRate: targetSampleRate)
        return normalize(samples)
    }

    public static func load(url: URL, targetSampleRate: Int = 16000) throws -> [Float] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw Error.fileNotFound(url)
        }

        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw Error.readFailed(error)
        }

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(targetSampleRate),
            channels: 1,
            interleaved: false
        ) else {
            throw Error.formatConversionFailed
        }

        guard let converter = AVAudioConverter(from: file.processingFormat, to: outputFormat) else {
            throw Error.formatConversionFailed
        }

        let frameCapacity = AVAudioFrameCount(
            Double(file.length) * Double(targetSampleRate) / file.processingFormat.sampleRate + 1
        )
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCapacity) else {
            throw Error.formatConversionFailed
        }

        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            let frameCount = AVAudioFrameCount(file.processingFormat.sampleRate * 0.1)
            guard let inputBuffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: frameCount
            ) else {
                outStatus.pointee = .noDataNow
                return nil
            }
            do {
                try file.read(into: inputBuffer)
                if inputBuffer.frameLength == 0 {
                    outStatus.pointee = .endOfStream
                    return nil
                }
                outStatus.pointee = .haveData
                return inputBuffer
            } catch {
                outStatus.pointee = .endOfStream
                return nil
            }
        }

        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError, withInputFrom: inputBlock)
        if status == .error {
            throw Error.formatConversionFailed
        }

        guard let channelData = outputBuffer.floatChannelData else {
            throw Error.formatConversionFailed
        }

        let frameLength = Int(outputBuffer.frameLength)
        guard frameLength > 0 else { throw Error.emptyAudio }
        return Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
    }

    /// ピーク正規化: Python版の audio / max(abs(audio)) と等価。
    public static func normalize(_ samples: [Float]) -> [Float] {
        guard let peak = samples.max(by: { abs($0) < abs($1) }).map({ abs($0) }), peak > 0 else {
            return samples
        }
        return samples.map { $0 / peak }
    }
}
