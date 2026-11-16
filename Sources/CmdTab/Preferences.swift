import AppKit

enum ThumbnailSize: String, CaseIterable {
    case small
    case medium
    case large

    var title: String {
        switch self {
        case .small:
            return "Small"
        case .medium:
            return "Medium"
        case .large:
            return "Large"
        }
    }

    var cardSize: NSSize {
        switch self {
        case .small:
            return NSSize(width: 152, height: 140)
        case .medium:
            return NSSize(width: 200, height: 172)
        case .large:
            return NSSize(width: 276, height: 220)
        }
    }

    var thumbSize: NSSize {
        switch self {
        case .small:
            return NSSize(width: 136, height: 84)
        case .medium:
            return NSSize(width: 184, height: 116)
        case .large:
            return NSSize(width: 260, height: 164)
        }
    }
}

final class Preferences {
    static let shared = Preferences()

    private enum Key {
        static let showMenuBarIcon = "showMenuBarIcon"
        static let includeWindowsFromOtherSpaces = "includeWindowsFromOtherSpaces"
        static let thumbnailSize = "thumbnailSize"
    }

    private let defaults = UserDefaults.standard

    var showMenuBarIcon: Bool {
        get {
            if defaults.object(forKey: Key.showMenuBarIcon) == nil {
                return true
            }
            return defaults.bool(forKey: Key.showMenuBarIcon)
        }
        set {
            defaults.set(newValue, forKey: Key.showMenuBarIcon)
        }
    }

    var includeWindowsFromOtherSpaces: Bool {
        get {
            defaults.bool(forKey: Key.includeWindowsFromOtherSpaces)
        }
        set {
            defaults.set(newValue, forKey: Key.includeWindowsFromOtherSpaces)
        }
    }

    var thumbnailSize: ThumbnailSize {
        get {
            guard let raw = defaults.string(forKey: Key.thumbnailSize),
                  let size = ThumbnailSize(rawValue: raw) else {
                return .medium
            }
            return size
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.thumbnailSize)
        }
    }
}
