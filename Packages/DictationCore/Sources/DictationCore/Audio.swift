import Foundation

/// Writes mono Float samples as a 16-bit PCM WAV file, the smallest lossless format Groq accepts.
/// At 16 kHz that is 32 KB per second, so Groq's 25 MB free-tier limit is about 13 minutes.
public enum WAVEncoder {
    public static func encode(samples: [Float], sampleRate: Int = 16_000) -> Data {
        let channels = 1
        let bitsPerSample = 16
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = samples.count * blockAlign

        var data = Data(capacity: 44 + dataSize)
        data.append(contentsOf: Array("RIFF".utf8))
        data.appendLittleEndian(UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(1)) // PCM
        data.appendLittleEndian(UInt16(channels))
        data.appendLittleEndian(UInt32(sampleRate))
        data.appendLittleEndian(UInt32(byteRate))
        data.appendLittleEndian(UInt16(blockAlign))
        data.appendLittleEndian(UInt16(bitsPerSample))
        data.append(contentsOf: Array("data".utf8))
        data.appendLittleEndian(UInt32(dataSize))

        var pcm = [Int16](repeating: 0, count: samples.count)
        for (index, sample) in samples.enumerated() {
            let clamped = max(-1, min(1, sample.isFinite ? sample : 0))
            pcm[index] = Int16((clamped * Float(Int16.max)).rounded())
        }
        pcm.withUnsafeBufferPointer { buffer in
            for value in buffer { data.appendLittleEndian(UInt16(bitPattern: value)) }
        }
        return data
    }
}

public enum AudioLevel {
    /// Maps the RMS of a buffer to 0...1 on a -50...0 dB scale, which suits a speech meter.
    public static func normalized(rms: Float) -> Float {
        guard rms > 0, rms.isFinite else { return 0 }
        let decibels = 20 * log10(rms)
        return max(0, min(1, (decibels + 50) / 50))
    }

    public static func rms(_ samples: UnsafeBufferPointer<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for sample in samples { sum += sample * sample }
        return (sum / Float(samples.count)).squareRoot()
    }

    public static func rms(_ samples: [Float]) -> Float {
        samples.withUnsafeBufferPointer { rms($0) }
    }
}

/// The shortest recording worth transcribing. Anything shorter is almost always an accidental tap,
/// and Whisper tends to hallucinate text for it.
public enum RecordingLimits {
    public static let minimumDuration: TimeInterval = 0.4
    /// Long dictations are stopped automatically so a forgotten recording can't run forever.
    public static let maximumDuration: TimeInterval = 10 * 60

    public static func isLongEnough(sampleCount: Int, sampleRate: Int = 16_000) -> Bool {
        Double(sampleCount) / Double(sampleRate) >= minimumDuration
    }
}

private extension Data {
    mutating func appendLittleEndian(_ value: UInt16) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendLittleEndian(_ value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
