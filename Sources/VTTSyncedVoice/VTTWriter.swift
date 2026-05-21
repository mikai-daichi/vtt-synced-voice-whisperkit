import Foundation

public enum VTTWriter {
    public static func write(entries: [SubtitleEntry]) -> String {
        var lines = ["WEBVTT", ""]
        for entry in entries {
            lines.append("\(formatTime(entry.startTime)) --> \(formatTime(entry.endTime))")
            lines.append(entry.text)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private static func formatTime(_ seconds: Double) -> String {
        let total = Int(seconds * 1000)
        let ms = total % 1000
        let s = (total / 1000) % 60
        let m = (total / 60000) % 60
        let h = total / 3600000
        return String(format: "%02d:%02d:%02d.%03d", h, m, s, ms)
    }
}
