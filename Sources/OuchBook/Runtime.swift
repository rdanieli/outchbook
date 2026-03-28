import Foundation

public enum AccelerometerAvailability: Equatable, Sendable {
    case available(AccelerometerBackendKind)
    case unsupported(String)
}

public protocol AccelerometerProvider: AnyObject, Sendable {
    var availability: AccelerometerAvailability { get }
    func start(_ handler: @escaping (AccelerometerReading) -> Void) throws
    func stop()
}

public protocol SleepMonitor: AnyObject, Sendable {
    func start(_ handler: @escaping () -> Void)
    func stop()
}

public final class OuchBookCoreController: @unchecked Sendable {
    private let provider: AccelerometerProvider
    private let sleepMonitor: SleepMonitor
    private let buffer: MotionWindowBuffer
    private let coordinator: SleepEventCoordinator
    private let masterVolumeProvider: () -> Double

    public init(
        provider: AccelerometerProvider,
        sleepMonitor: SleepMonitor,
        mapper: ImpactProfileMapper,
        masterVolumeProvider: @escaping () -> Double,
        onImpactProfileChosen: @escaping (ImpactProfile) -> Void
    ) {
        self.provider = provider
        self.sleepMonitor = sleepMonitor
        self.buffer = MotionWindowBuffer(windowDuration: 0.300)
        self.coordinator = SleepEventCoordinator(
            analyzer: LidCloseImpactAnalyzer(buffer: buffer, mapper: mapper),
            onProfileChosen: onImpactProfileChosen
        )
        self.masterVolumeProvider = masterVolumeProvider
    }

    public func start() throws {
        try provider.start { [buffer] reading in
            buffer.append(reading)
        }

        sleepMonitor.start { [coordinator, masterVolumeProvider] in
            coordinator.handleSleep(masterVolume: masterVolumeProvider())
        }
    }

    public func stop() {
        sleepMonitor.stop()
        provider.stop()
    }
}
