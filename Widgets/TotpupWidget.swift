import SwiftUI
import WidgetKit

private struct PupEntry: TimelineEntry { let date: Date }
private struct PupProvider: TimelineProvider {
    func placeholder(in context: Context) -> PupEntry { PupEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (PupEntry) -> Void) { completion(PupEntry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PupEntry>) -> Void) {
        completion(Timeline(entries: [PupEntry(date: .now)], policy: .never))
    }
}
private struct PupWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 7) {
                Label("totpup", systemImage: "pawprint.fill").font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundStyle(Palette.ink)
                if family != .systemSmall {
                    Text("Your little authentication companion.").font(.system(size: 11)).foregroundStyle(Palette.muted)
                    Spacer(minLength: 0)
                }
                Link(destination: URL(string: "totpup://fetch")!) {
                    Label("Fetch a code", systemImage: "arrow.up.right").font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 9).foregroundStyle(.white).background(Palette.ink, in: Capsule())
                }
            }
            if family != .systemSmall {
                Spacer(minLength: 0)
                PupView(awake: true, celebrate: false, animate: false).frame(width: 105, height: 120)
            }
        }.containerBackground(Palette.background, for: .widget).widgetURL(URL(string: "totpup://fetch"))
    }
}
@main struct TotpupWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.totpup.fetch", provider: PupProvider()) { _ in PupWidgetView() }
            .configurationDisplayName("Totpup")
            .description("Fetch your live verification codes from the desktop or Notification Center.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
