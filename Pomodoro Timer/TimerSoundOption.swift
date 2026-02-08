import Foundation

enum TimerSoundOption: Int, CaseIterable, Identifiable {
    case none = 0
    case crystalBell = 1
    case gentleWave = 2
    case brightPing = 3
    case warmChime = 4
    case digitalTick = 5
    case softMarimba = 6

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .none:
            return "No Sound"
        case .crystalBell:
            return "Crystal Bell"
        case .gentleWave:
            return "Gentle Wave"
        case .brightPing:
            return "Bright Ping"
        case .warmChime:
            return "Warm Chime"
        case .digitalTick:
            return "Digital Tick"
        case .softMarimba:
            return "Soft Marimba"
        }
    }

    var fileName: String? {
        switch self {
        case .none:
            return nil
        case .crystalBell:
            return "crystal-bell"
        case .gentleWave:
            return "gentle-wave"
        case .brightPing:
            return "bright-ping"
        case .warmChime:
            return "warm-chime"
        case .digitalTick:
            return "digital-tick"
        case .softMarimba:
            return "soft-marimba"
        }
    }

    static let defaultFocus = TimerSoundOption.crystalBell
    static let defaultShortBreak = TimerSoundOption.gentleWave
    static let defaultLongBreak = TimerSoundOption.warmChime
}
