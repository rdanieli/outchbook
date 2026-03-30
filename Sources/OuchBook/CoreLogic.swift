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

public struct ImpactSignal: Equatable, Sendable {
    public let peakMagnitude: Double
    public let closingVelocity: Double?

    public init(peakMagnitude: Double, closingVelocity: Double? = nil) {
        self.peakMagnitude = peakMagnitude
        self.closingVelocity = closingVelocity
    }
}

public struct ImpactProfileMapper: Sendable {
    public static let aggressiveTierFileNames = [
        "tier3-agony.mp3",
        "tier3-why-distorted.mp3",
        "tier3-soul-out.mp3",
        "tier3-not-again.mp3",
    ]

    public let softThreshold: Double
    public let aggressiveThreshold: Double
    private let aggressiveVariantSelector: @Sendable ([String]) -> String

    public init(
        softThreshold: Double = 0.8,
        aggressiveThreshold: Double = 1.8,
        aggressiveVariantSelector: @escaping @Sendable ([String]) -> String = { variants in
            variants.randomElement() ?? "tier3-agony.mp3"
        }
    ) {
        self.softThreshold = softThreshold
        self.aggressiveThreshold = aggressiveThreshold
        self.aggressiveVariantSelector = aggressiveVariantSelector
    }

    public func profile(for signal: ImpactSignal, masterVolume: Double) -> ImpactProfile {
        if let closingVelocity = signal.closingVelocity {
            return profile(forClosingVelocity: closingVelocity, masterVolume: masterVolume)
        }

        return profile(forPeakMagnitude: signal.peakMagnitude, masterVolume: masterVolume)
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
            fileName: aggressiveVariantSelector(Self.aggressiveTierFileNames),
            volume: clampedVolume(clampedMasterVolume),
            pitchMultiplier: 1.35
        )
    }

    private func profile(forClosingVelocity closingVelocity: Double, masterVolume: Double) -> ImpactProfile {
        let closingSpeed = abs(closingVelocity)
        let clampedMasterVolume = min(max(masterVolume, 0), 1)

        if closingSpeed < 80 {
            return ImpactProfile(
                tier: .gentle,
                fileName: "ow-soft.mp3",
                volume: clampedVolume(0.3 * clampedMasterVolume),
                pitchMultiplier: 0.95
            )
        }

        if closingSpeed < 180 {
            return ImpactProfile(
                tier: .normal,
                fileName: "ow.mp3",
                volume: clampedVolume(0.6 * clampedMasterVolume),
                pitchMultiplier: 1.1
            )
        }

        return ImpactProfile(
            tier: .aggressive,
            fileName: aggressiveVariantSelector(Self.aggressiveTierFileNames),
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

    public func profileForLidClose(masterVolume: Double, closingVelocity: Double? = nil) -> ImpactProfile {
        mapper.profile(
            for: ImpactSignal(
                peakMagnitude: buffer.peakMagnitude(),
                closingVelocity: closingVelocity
            ),
            masterVolume: masterVolume
        )
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

    public func handleSleep(masterVolume: Double, closingVelocity: Double? = nil) {
        onProfileChosen(
            analyzer.profileForLidClose(
                masterVolume: masterVolume,
                closingVelocity: closingVelocity
            )
        )
    }
}

public enum SleepTriggerSource: Equatable, Sendable {
    case lidAngle
    case systemPower
}

public struct SleepTriggerEvent: Equatable, Sendable {
    public let source: SleepTriggerSource
    public let closingVelocity: Double?

    public init(source: SleepTriggerSource, closingVelocity: Double? = nil) {
        self.source = source
        self.closingVelocity = closingVelocity
    }
}

public final class LidClosureDetector: @unchecked Sendable {
    private let closeAngleThreshold: Double
    private let reopenAngleThreshold: Double
    private let closingVelocityThreshold: Double

    private var lastAngle: Double?
    private var lastTimestamp: TimeInterval?
    private var isArmed = true

    public init(
        closeAngleThreshold: Double = 50,
        reopenAngleThreshold: Double = 85,
        closingVelocityThreshold: Double = -40
    ) {
        self.closeAngleThreshold = closeAngleThreshold
        self.reopenAngleThreshold = reopenAngleThreshold
        self.closingVelocityThreshold = closingVelocityThreshold
    }

    public func process(angleDegrees: Double, timestamp: TimeInterval) -> SleepTriggerEvent? {
        defer {
            lastAngle = angleDegrees
            lastTimestamp = timestamp
        }

        if angleDegrees >= reopenAngleThreshold {
            isArmed = true
        }

        guard
            isArmed,
            let lastAngle,
            let lastTimestamp,
            timestamp > lastTimestamp
        else {
            return nil
        }

        let velocity = (angleDegrees - lastAngle) / (timestamp - lastTimestamp)
        guard angleDegrees <= closeAngleThreshold, velocity <= closingVelocityThreshold else {
            return nil
        }

        isArmed = false
        return SleepTriggerEvent(source: .lidAngle, closingVelocity: velocity)
    }
}

public enum LidAngleNormalizer {
    public static func angleDegrees(fromRawValue rawValue: Int) -> Double {
        if rawValue > 360 {
            return Double(rawValue) / 100.0
        }

        return Double(rawValue)
    }
}
