import Foundation

/// Settings the app shares with the home-screen widget (App Group).
enum WidgetShared {
    static let group = "group.com.tarzanillges.commandcenter"
    static var defaults: UserDefaults { UserDefaults(suiteName: group) ?? .standard }

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
