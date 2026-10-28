import IOKit.ps

/// Plugged in or on battery, and how full the battery is (IOKit's power sources).
struct PowerSource: Equatable {
    var onBattery = false
    /// 0…1; nil without a battery (desktop Macs).
    var level: Double?

    /// The frame limit "Save battery when unplugged" sets.
    static let batteryFrameLimit = 30

    static func current() -> PowerSource {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return PowerSource() }
        let providing = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        var source = PowerSource(onBattery: providing == kIOPSBatteryPowerValue)
        let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] ?? []
        for item in list {
            guard let description = IOPSGetPowerSourceDescription(info, item)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let capacity = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0
            else { continue }
            source.level = Double(capacity) / Double(maximum)
        }
        return source
    }

    static func symbol(_ level: Double) -> String {
        switch level {
        case ..<0.13: return "battery.0percent"
        case ..<0.38: return "battery.25percent"
        case ..<0.63: return "battery.50percent"
        case ..<0.88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    /// The limit a start uses: on battery with the setting on, at most 30 FPS (0 = no limit).
    static func cappedLimit(_ limit: Int, onBattery: Bool, saveBattery: Bool) -> Int {
        guard onBattery, saveBattery else { return limit }
        return limit > 0 ? min(limit, batteryFrameLimit) : batteryFrameLimit
    }
}
