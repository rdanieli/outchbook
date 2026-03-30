import AppKit
import Foundation
import IOKit.hid
import IOKit.pwr_mgt

public enum AccelerometerProviderError: Error, Sendable {
    case unsupportedHardware(String)
    case hidManagerOpenFailed(IOReturn)
    case deviceNotFound
    case deviceOpenFailed(IOReturn)
}

public final class UnsupportedAccelerometerProvider: AccelerometerProvider, @unchecked Sendable {
    public let availability: AccelerometerAvailability

    public init(reason: String) {
        self.availability = .unsupported(reason)
    }

    public func start(_ handler: @escaping (AccelerometerReading) -> Void) throws {
        let reason: String
        if case let .unsupported(message) = availability {
            reason = message
        } else {
            reason = "Accelerometer unavailable."
        }

        throw AccelerometerProviderError.unsupportedHardware(reason)
    }

    public func stop() {}
}

public enum DefaultAccelerometerProviderFactory {
    public static func currentArchitecture() -> MachineArchitecture {
        #if arch(arm64)
        .appleSilicon
        #elseif arch(x86_64)
        .intel
        #else
        .unknown
        #endif
    }

    public static func makeDefault() -> any AccelerometerProvider {
        switch AccelerometerBackendResolver.backend(for: currentArchitecture()) {
        case .appleSiliconHID:
            AppleSiliconHIDAccelerometerProvider()
        case .unsupported:
            UnsupportedAccelerometerProvider(
                reason: "This Mac does not expose a supported accelerometer backend yet."
            )
        }
    }
}

public final class AppleSiliconHIDAccelerometerProvider: AccelerometerProvider, @unchecked Sendable {
    public let availability: AccelerometerAvailability = .available(.appleSiliconHID)

    private let manager: IOHIDManager
    private let reportBuffer: UnsafeMutablePointer<UInt8>
    private let reportBufferLength: CFIndex
    private var device: IOHIDDevice?
    private var onReading: ((AccelerometerReading) -> Void)?

    public init(reportBufferLength: CFIndex = 64) {
        self.manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.reportBufferLength = reportBufferLength
        self.reportBuffer = .allocate(capacity: reportBufferLength)
        self.reportBuffer.initialize(repeating: 0, count: reportBufferLength)
    }

    deinit {
        stop()
        reportBuffer.deinitialize(count: reportBufferLength)
        reportBuffer.deallocate()
    }

    public func start(_ handler: @escaping (AccelerometerReading) -> Void) throws {
        stop()
        onReading = handler

        let matching: [String: Any] = [
            kIOHIDPrimaryUsagePageKey as String: 0xFF00,
            kIOHIDPrimaryUsageKey as String: 0x03,
        ]

        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        IOHIDManagerScheduleWithRunLoop(
            manager,
            CFRunLoopGetMain(),
            CFRunLoopMode.defaultMode.rawValue
        )

        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
            throw AccelerometerProviderError.hidManagerOpenFailed(openResult)
        }

        do {
            guard let matchedDevice = copyMatchedDevices().first else {
                throw AccelerometerProviderError.deviceNotFound
            }

            try attachDeviceIfNeeded(matchedDevice)
        } catch {
            stop()
            throw error
        }
    }

    public func stop() {
        if let device {
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }

        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        device = nil
        onReading = nil
    }

    private func attachDeviceIfNeeded(_ device: IOHIDDevice) throws {
        guard self.device == nil else {
            return
        }

        let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
            throw AccelerometerProviderError.deviceOpenFailed(openResult)
        }

        self.device = device
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        IOHIDDeviceRegisterInputReportCallback(
            device,
            reportBuffer,
            reportBufferLength,
            Self.reportCallback,
            context
        )
    }

    private func copyMatchedDevices() -> [IOHIDDevice] {
        guard let devices = IOHIDManagerCopyDevices(manager) else {
            return []
        }

        let count = CFSetGetCount(devices)
        guard count > 0 else {
            return []
        }

        let values = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(capacity: count)
        defer { values.deallocate() }

        CFSetGetValues(devices, values)

        return (0..<count).compactMap { index in
            guard let value = values[index] else {
                return nil
            }

            return unsafeBitCast(value, to: IOHIDDevice.self)
        }
    }

    private static let reportCallback: IOHIDReportCallback = { context, _, _, _, _, report, reportLength in
        guard let context else {
            return
        }

        let provider = Unmanaged<AppleSiliconHIDAccelerometerProvider>
            .fromOpaque(context)
            .takeUnretainedValue()

        let bytes = Array(UnsafeBufferPointer(start: report, count: reportLength))
        guard let reading = AppleSiliconAccelerometerReportDecoder.decode(
            bytes,
            timestamp: ProcessInfo.processInfo.systemUptime
        ) else {
            return
        }

        provider.onReading?(reading)
    }
}

public final class WorkspaceSleepMonitor: SleepMonitor, @unchecked Sendable {
    private final class HandlerBox: @unchecked Sendable {
        let handler: (SleepTriggerEvent) -> Void

        init(handler: @escaping (SleepTriggerEvent) -> Void) {
            self.handler = handler
        }
    }

    private var observer: NSObjectProtocol?

    public init() {}

    public func start(_ handler: @escaping (SleepTriggerEvent) -> Void) {
        stop()
        let handlerBox = HandlerBox(handler: handler)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { _ in
            handlerBox.handler(SleepTriggerEvent(source: .systemPower))
        }
    }

    public func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }

        observer = nil
    }
}

public final class SystemPowerSleepMonitor: SleepMonitor, @unchecked Sendable {
    private static let messageCanSystemSleep = natural_t(0xE0000270)
    private static let messageSystemWillSleep = natural_t(0xE0000280)
    private static let messageSystemHasPoweredOn = natural_t(0xE0000300)
    private static let sleepAcknowledgeDelay: TimeInterval = 0.15

    private final class HandlerBox: @unchecked Sendable {
        let handler: (SleepTriggerEvent) -> Void

        init(handler: @escaping (SleepTriggerEvent) -> Void) {
            self.handler = handler
        }
    }

    private var rootPort: io_connect_t = 0
    private var notifier: io_object_t = 0
    private var notificationPort: IONotificationPortRef?
    private var handlerBox: HandlerBox?

    public init() {}

    deinit {
        stop()
    }

    public func start(_ handler: @escaping (SleepTriggerEvent) -> Void) {
        stop()

        let handlerBox = HandlerBox(handler: handler)
        self.handlerBox = handlerBox

        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        var notificationPort: IONotificationPortRef?
        var notifier: io_object_t = 0

        let rootPort = IORegisterForSystemPower(
            context,
            &notificationPort,
            Self.powerCallback,
            &notifier
        )

        guard rootPort != 0, let notificationPort else {
            self.handlerBox = nil
            return
        }

        self.rootPort = rootPort
        self.notifier = notifier
        self.notificationPort = notificationPort

        if let runLoopSource = IONotificationPortGetRunLoopSource(notificationPort)?.takeUnretainedValue() {
            CFRunLoopAddSource(
                CFRunLoopGetMain(),
                runLoopSource,
                CFRunLoopMode.commonModes
            )
        }
    }

    public func stop() {
        if let notificationPort,
           let runLoopSource = IONotificationPortGetRunLoopSource(notificationPort)?.takeUnretainedValue() {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                runLoopSource,
                CFRunLoopMode.commonModes
            )
        }

        if notifier != 0 {
            IODeregisterForSystemPower(&notifier)
            notifier = 0
        }

        if rootPort != 0 {
            IOServiceClose(rootPort)
            rootPort = 0
        }

        if let notificationPort {
            IONotificationPortDestroy(notificationPort)
            self.notificationPort = nil
        }

        handlerBox = nil
    }

    private static let powerCallback: IOServiceInterestCallback = { context, _, messageType, messageArgument in
        guard let context else {
            return
        }

        let monitor = Unmanaged<SystemPowerSleepMonitor>
            .fromOpaque(context)
            .takeUnretainedValue()

        switch messageType {
        case SystemPowerSleepMonitor.messageCanSystemSleep:
            IOAllowPowerChange(monitor.rootPort, Int(bitPattern: messageArgument))

        case SystemPowerSleepMonitor.messageSystemWillSleep:
            monitor.handlerBox?.handler(SleepTriggerEvent(source: .systemPower))
            let rootPort = monitor.rootPort
            let notificationID = Int(bitPattern: messageArgument)
            DispatchQueue.main.asyncAfter(deadline: .now() + SystemPowerSleepMonitor.sleepAcknowledgeDelay) {
                IOAllowPowerChange(rootPort, notificationID)
            }

        case SystemPowerSleepMonitor.messageSystemHasPoweredOn:
            break

        default:
            break
        }
    }
}

public final class LidAngleCloseMonitor: SleepMonitor, @unchecked Sendable {
    private let manager: IOHIDManager
    private let detector: LidClosureDetector

    private var device: IOHIDDevice?
    private var timer: Timer?
    private var handler: ((SleepTriggerEvent) -> Void)?

    public init(detector: LidClosureDetector = LidClosureDetector()) {
        self.manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.detector = detector
    }

    deinit {
        stop()
    }

    public func start(_ handler: @escaping (SleepTriggerEvent) -> Void) {
        stop()
        self.handler = handler

        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: 0x05AC,
            kIOHIDProductIDKey as String: 0x8104,
            kIOHIDPrimaryUsagePageKey as String: 0x0020,
            kIOHIDPrimaryUsageKey as String: 0x008A,
        ]

        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        IOHIDManagerScheduleWithRunLoop(
            manager,
            CFRunLoopGetMain(),
            CFRunLoopMode.defaultMode.rawValue
        )

        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            return
        }

        device = copyMatchedDevices().first
        guard let device else {
            return
        }

        guard IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            self.device = nil
            return
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.pollLidAngle()
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil

        if let device {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }

        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        device = nil
        handler = nil
    }

    private func pollLidAngle() {
        guard let device else {
            return
        }

        var report = [UInt8](repeating: 0, count: 8)
        var reportLength = CFIndex(report.count)

        let result = IOHIDDeviceGetReport(
            device,
            kIOHIDReportTypeFeature,
            1,
            &report,
            &reportLength
        )

        guard result == kIOReturnSuccess, reportLength >= 3 else {
            return
        }

        let angleRaw = Int(report[1]) | (Int(report[2]) << 8)
        guard angleRaw > 1 else {
            return
        }

        let angleDegrees = LidAngleNormalizer.angleDegrees(fromRawValue: angleRaw)

        if let event = detector.process(
            angleDegrees: angleDegrees,
            timestamp: ProcessInfo.processInfo.systemUptime
        ) {
            handler?(event)
        }
    }

    private func copyMatchedDevices() -> [IOHIDDevice] {
        guard let devices = IOHIDManagerCopyDevices(manager) else {
            return []
        }

        let count = CFSetGetCount(devices)
        guard count > 0 else {
            return []
        }

        let values = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(capacity: count)
        defer { values.deallocate() }

        CFSetGetValues(devices, values)

        return (0..<count).compactMap { index in
            guard let value = values[index] else {
                return nil
            }

            return unsafeBitCast(value, to: IOHIDDevice.self)
        }
    }
}

public final class CompositeSleepMonitor: SleepMonitor, @unchecked Sendable {
    private let monitors: [SleepMonitor]
    private let cooldown: TimeInterval
    private var lastTriggerTimestamp: TimeInterval?

    public init(monitors: [SleepMonitor], cooldown: TimeInterval = 1.5) {
        self.monitors = monitors
        self.cooldown = cooldown
    }

    public func start(_ handler: @escaping (SleepTriggerEvent) -> Void) {
        for monitor in monitors {
            monitor.start { [weak self] in
                guard let self else {
                    return
                }

                let now = ProcessInfo.processInfo.systemUptime
                if let lastTriggerTimestamp, now - lastTriggerTimestamp < cooldown {
                    return
                }

                lastTriggerTimestamp = now
                handler($0)
            }
        }
    }

    public func stop() {
        monitors.forEach { $0.stop() }
        lastTriggerTimestamp = nil
    }
}
