import Foundation

public struct AccelerometerReading: Equatable, Sendable {
    public let timestamp: TimeInterval
    public let x: Double
    public let y: Double
    public let z: Double

    public init(timestamp: TimeInterval, x: Double, y: Double, z: Double) {
        self.timestamp = timestamp
        self.x = x
        self.y = y
        self.z = z
    }

    public var magnitude: Double {
        sqrt((x * x) + (y * y) + (z * z))
    }
}

public final class MotionWindowBuffer: @unchecked Sendable {
    private let windowDuration: TimeInterval
    public private(set) var readings: [AccelerometerReading] = []

    public init(windowDuration: TimeInterval = 0.300) {
        self.windowDuration = windowDuration
    }

    public func append(_ reading: AccelerometerReading) {
        readings.append(reading)
        trimReadings(relativeTo: reading.timestamp)
    }

    public func peakMagnitude() -> Double {
        readings.map(\.magnitude).max() ?? 0
    }

    private func trimReadings(relativeTo latestTimestamp: TimeInterval) {
        let cutoff = latestTimestamp - windowDuration
        readings.removeAll { $0.timestamp < cutoff }
    }
}

public enum ImpactTier: Equatable, Sendable {
    case gentle
    case normal
    case aggressive
}

public struct ImpactProfile: Equatable, Sendable {
    public let tier: ImpactTier
    public let fileName: String
    public let volume: Double
    public let pitchMultiplier: Double

    public init(tier: ImpactTier, fileName: String, volume: Double, pitchMultiplier: Double) {
        self.tier = tier
        self.fileName = fileName
        self.volume = volume
        self.pitchMultiplier = pitchMultiplier
    }
}

public struct ImpactProfileMapper: Sendable {
    public let softThreshold: Double
    public let aggressiveThreshold: Double

    public init(softThreshold: Double = 0.8, aggressiveThreshold: Double = 1.8) {
        self.softThreshold = softThreshold
        self.aggressiveThreshold = aggressiveThreshold
    }

    public func profile(forPeakMagnitude peakMagnitude: Double, masterVolume: Double) -> ImpactProfile {
        let clampedMasterVolume = min(max(masterVolume, 0), 1)

        if peakMagnitude < softThreshold {
            return ImpactProfile(
                tier: .gentle,
                fileName: "ow-soft.mp3",
                volume: clampedVolume(0.3 * clampedMasterVolume),
                pitchMultiplier: 0.95
            )
        }

        if peakMagnitude < aggressiveThreshold {
            return ImpactProfile(
                tier: .normal,
                fileName: "ow.mp3",
                volume: clampedVolume(0.6 * clampedMasterVolume),
                pitchMultiplier: 1.1
            )
        }

        return ImpactProfile(
            tier: .aggressive,
            fileName: "ouch-scream.mp3",
            volume: clampedVolume(clampedMasterVolume),
            pitchMultiplier: 1.35
        )
    }

    private func clampedVolume(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

public struct LidCloseImpactAnalyzer: Sendable {
    private let buffer: MotionWindowBuffer
    private let mapper: ImpactProfileMapper

    public init(buffer: MotionWindowBuffer, mapper: ImpactProfileMapper) {
        self.buffer = buffer
        self.mapper = mapper
    }

    public func profileForLidClose(masterVolume: Double) -> ImpactProfile {
        mapper.profile(forPeakMagnitude: buffer.peakMagnitude(), masterVolume: masterVolume)
    }
}

public enum AppleSiliconAccelerometerReportDecoder {
    public static func decode(_ bytes: [UInt8], timestamp: TimeInterval) -> AccelerometerReading? {
        guard bytes.count >= 18 else {
            return nil
        }

        let x = Double(readInt32(from: bytes, startingAt: 6)) / 65_536.0
        let y = Double(readInt32(from: bytes, startingAt: 10)) / 65_536.0
        let z = Double(readInt32(from: bytes, startingAt: 14)) / 65_536.0

        return AccelerometerReading(timestamp: timestamp, x: x, y: y, z: z)
    }

    private static func readInt32(from bytes: [UInt8], startingAt offset: Int) -> Int32 {
        let b0 = UInt32(bytes[offset])
        let b1 = UInt32(bytes[offset + 1]) << 8
        let b2 = UInt32(bytes[offset + 2]) << 16
        let b3 = UInt32(bytes[offset + 3]) << 24
        return Int32(bitPattern: b0 | b1 | b2 | b3)
    }
}

public enum MachineArchitecture: Sendable {
    case appleSilicon
    case intel
    case unknown
}

public enum AccelerometerBackendKind: Equatable, Sendable {
    case appleSiliconHID
    case unsupported
}

public enum AccelerometerBackendResolver {
    public static func backend(for architecture: MachineArchitecture) -> AccelerometerBackendKind {
        switch architecture {
        case .appleSilicon:
            .appleSiliconHID
        case .intel, .unknown:
            .unsupported
        }
    }
}

public struct SleepEventCoordinator {
    private let analyzer: LidCloseImpactAnalyzer
    private let onProfileChosen: (ImpactProfile) -> Void

    public init(
        analyzer: LidCloseImpactAnalyzer,
        onProfileChosen: @escaping (ImpactProfile) -> Void
    ) {
        self.analyzer = analyzer
        self.onProfileChosen = onProfileChosen
    }

    public func handleSleep(masterVolume: Double) {
        onProfileChosen(analyzer.profileForLidClose(masterVolume: masterVolume))
    }
}
