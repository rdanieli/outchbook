import AppKit
import Foundation
import IOKit.hid

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
        let handler: () -> Void

        init(handler: @escaping () -> Void) {
            self.handler = handler
        }
    }

    private var observer: NSObjectProtocol?

    public init() {}

    public func start(_ handler: @escaping () -> Void) {
        stop()
        let handlerBox = HandlerBox(handler: handler)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { _ in
            handlerBox.handler()
        }
    }

    public func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }

        observer = nil
    }
}
