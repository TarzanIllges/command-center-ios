import SwiftUI
import WidgetKit

/// Home-screen widget: a picture of the Bot Office (re-rendered on the server every few minutes) plus who is working.
/// Tapping it opens the office in the app.

struct OfficeStatus: Decodable {
    struct Ellie: Decodable { let state: String; let task: String }
    struct Bot: Decodable { let name: String; let color: String; let state: String; let task: String }
    struct Theme: Decodable { let label: String; let emoji: String }
    let working: Int
    let waiting: Int
    let ellie: Ellie?
    let bots: [Bot]?
    let theme: Theme?
}

struct OfficeEntry: TimelineEntry {
    let date: Date
    let image: UIImage?
    let status: OfficeStatus?
    let problem: String?
}

struct OfficeProvider: TimelineProvider {
    func placeholder(in context: Context) -> OfficeEntry { OfficeEntry(date: .now, image: nil, status: nil, problem: nil) }

    func getSnapshot(in context: Context, completion: @escaping (OfficeEntry) -> Void) {
        Task { completion(await load(context.family)) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<OfficeEntry>) -> Void) {
        Task {
            let entry = await load(context.family)
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(10 * 60))))
        }
    }

    private func load(_ family: WidgetFamily) async -> OfficeEntry {
        let size = family == .systemSmall ? "small" : family == .systemLarge ? "large" : "medium"
        guard let statusURL = WidgetShared.endpoint("widget/status.json"),
              let imageURL = WidgetShared.endpoint("widget/office.png", [URLQueryItem(name: "size", value: size)]) else {
            return OfficeEntry(date: .now, image: nil, status: nil, problem: "Open Command Center once to connect")
        }
        var status: OfficeStatus?
        var image: UIImage?
        if let (data, resp) = try? await URLSession.shared.data(from: statusURL), (resp as? HTTPURLResponse)?.statusCode == 200 {
            status = try? JSONDecoder().decode(OfficeStatus.self, from: data)
        }
        if let (data, resp) = try? await URLSession.shared.data(from: imageURL), (resp as? HTTPURLResponse)?.statusCode == 200 {
            image = UIImage(data: data)
        }
        let problem = status == nil && image == nil ? "Can't reach your server (is Tailscale on?)" : nil
        return OfficeEntry(date: .now, image: image, status: status, problem: problem)
    }
}

struct OfficeWidgetView: View {
    let entry: OfficeEntry
    @Environment(\.widgetFamily) private var family
    private let navy = Color(red: 0.043, green: 0.063, blue: 0.125)

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let image = entry.image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                navy
            }
            LinearGradient(colors: [.clear, navy.opacity(0.85)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                if let p = entry.problem {
                    Text(p).font(.caption2).foregroundStyle(.white)
                } else if let s = entry.status {
                    HStack(spacing: 6) {
                        label("\(s.working)", color: .green)
                        if s.waiting > 0 { label("\(s.waiting)", color: .orange) }
                        if family != .systemSmall, let t = s.theme { Text("\(t.emoji) \(t.label)").font(.caption2).foregroundStyle(.white.opacity(0.8)) }
                    }
                    if let e = s.ellie {
                        Text("Ellie: \(e.task)").font(.caption2.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                    }
                    if family == .systemLarge, let bots = s.bots {
                        ForEach(Array(bots.prefix(4).enumerated()), id: \.offset) { _, b in
                            Text("\(b.name): \(b.task)").font(.caption2).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                        }
                    }
                }
                Text(entry.date, style: .time).font(.system(size: 9)).foregroundStyle(.white.opacity(0.6))
            }
            .padding(10)
        }
        .widgetURL(URL(string: "commandcenter://office"))
    }

    private func label(_ text: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.caption.bold()).foregroundStyle(.white)
        }
    }
}

struct OfficeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OfficeWidget", provider: OfficeProvider()) { entry in
            if #available(iOS 17.0, *) {
                OfficeWidgetView(entry: entry).containerBackground(for: .widget) { Color(red: 0.043, green: 0.063, blue: 0.125) }
            } else {
                OfficeWidgetView(entry: entry)
            }
        }
        .configurationDisplayName("Bot Office")
        .description("Your bots at work, live from the server.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct OfficeWidgets: WidgetBundle {
    var body: some Widget { OfficeWidget() }
}
