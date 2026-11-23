import Foundation
import WidgetKit

/// Settings the app shares with the home-screen widget (App Group).
enum WidgetShared {
    /// AltStore re-signs with your team and renames the App Group (it adds your team ID, like it does to the bundle ID),
    /// so the group is worked out from this install's bundle ID and the first one iOS actually grants is used.
    static let group: String = {
        let base = "group.com.tarzanillges.commandcenter"
        let bundle = (Bundle.main.bundleIdentifier ?? "").replacingOccurrences(of: ".widget", with: "")
        let candidates = [base, "group." + bundle]
        return candidates.first { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil } ?? base
    }()
    static var defaults: UserDefaults { UserDefaults(suiteName: group) ?? .standard }

    /// Called when the app is pointed at a different server: the widget must not keep showing the old one.
    static func forget() {
        serverURL = nil
        widgetKey = nil
        WidgetCenter.shared.reloadAllTimelines()
    }

    static var serverURL: URL? {
        get { defaults.string(forKey: "serverURL").flatMap(URL.init(string:)) }
        set { defaults.set(newValue?.absoluteString, forKey: "serverURL") }
    }

    /// Read-only key for the widget's office picture and status, fetched from /api/widget/key while signed in.
    static var widgetKey: String? {
        get { defaults.string(forKey: "widgetKey") }
        set { defaults.set(newValue, forKey: "widgetKey") }
    }

    static func endpoint(_ path: String, _ extra: [URLQueryItem] = []) -> URL? {
        guard let base = serverURL, let key = widgetKey,
              var c = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false) else { return nil }
        c.queryItems = [URLQueryItem(name: "key", value: key)] + extra
        return c.url
    }
}
