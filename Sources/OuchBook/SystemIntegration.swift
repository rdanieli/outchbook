import Foundation
import ServiceManagement

public protocol AppPreferencesStoring: AnyObject, Sendable {
    func containsValue(forKey key: String) -> Bool
    func bool(forKey key: String) -> Bool
    func double(forKey key: String) -> Double
    func set(_ value: Bool, forKey key: String)
    func set(_ value: Double, forKey key: String)
}

extension UserDefaults: AppPreferencesStoring {
    public func containsValue(forKey key: String) -> Bool {
        object(forKey: key) != nil
    }
}

public protocol LaunchAtLoginManaging: AnyObject, Sendable {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

public final class MainAppLaunchAtLoginManager: LaunchAtLoginManaging, @unchecked Sendable {
    public init() {}

    public var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
