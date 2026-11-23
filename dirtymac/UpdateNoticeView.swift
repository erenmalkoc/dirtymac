import SwiftUI
import AppKit

/// What each button of the panel notice does. Kept apart from the view so
/// which buttons a notice offers is tested, and so a button can only open
/// an address UpdateCheck built.
enum UpdateNoticeAction: Equatable {
    case releaseNotes(String)
    case copyBrewCommand
    case download(String)
    case viewReleases
    case turnOnChecks
    case later

    /// A found version offers its notes and the way to install it: the
    /// Homebrew command for people who installed with Homebrew, the disk
    /// image for everyone else. A reminder offers the releases page, the
    /// setting and "Later".
    static func actions(for notice: UpdateChecker.Notice, homebrew: Bool) -> [UpdateNoticeAction] {
        switch notice {
        case .available(let version):
            return [.releaseNotes(version), homebrew ? .copyBrewCommand : .download(version)]
        case .reminder:
            return [.viewReleases, .turnOnChecks, .later]
        }
    }

    /// The address the button opens in the browser, nil for the others.
    var url: URL? {
        switch self {
        case .releaseNotes(let version): UpdateCheck.notesURL(version: version)
        case .download(let version): UpdateCheck.dmgURL(version: version)
        case .viewReleases: UpdateCheck.releasesPage
        case .copyBrewCommand, .turnOnChecks, .later: nil
        }
    }
}

/// The strip at the top of the panel: a newer version, or the 60-day
/// reminder for people who keep update checks off.
struct UpdateNoticeView: View {
    @EnvironmentObject private var updates: UpdateChecker
    /// "Turn on update checks" goes to Settings, where the toggle sits
    /// next to the sentence that says what it sends.
    var openSettings: () -> Void

    @State private var copied = false
    private let homebrew = UpdateCheck.isHomebrewInstall()

    var body: some View {
        if let notice = updates.notice {
            let actions = UpdateNoticeAction.actions(for: notice, homebrew: homebrew)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: notice.systemImage)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.tint)
                        .frame(width: 20)
                        .accessibilityHidden(true)
                    message(for: notice)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // Long languages do not fit side by side in 300 points.
                WrappingRow(spacing: 8) { buttons(actions) }
                    .padding(.leading, 30)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.08))
            .accessibilityElement(children: .contain)

            Divider()
        }
    }

    @ViewBuilder
    private func message(for notice: UpdateChecker.Notice) -> some View {
        switch notice {
        case .available(let version):
            Text("dirtymac \(version) is available.")
        case .reminder(let days):
            Text("It has been \(days) days since you installed this version. A newer one may be available. You can check the releases page, or turn on update checks in Settings.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func buttons(_ actions: [UpdateNoticeAction]) -> some View {
        ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
            Button { perform(action) } label: { label(for: action) }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(index == 0 ? .accentColor : nil)
        }
    }

    @ViewBuilder
    private func label(for action: UpdateNoticeAction) -> some View {
        switch action {
        case .releaseNotes: Text("Release notes")
        case .copyBrewCommand: Text(copied ? "Copied" : "Copy brew command")
        case .download: Text("Download")
        case .viewReleases: Text("View releases")
        case .turnOnChecks: Text("Turn on update checks")
        case .later: Text("Later")
        }
    }

    private func perform(_ action: UpdateNoticeAction) {
        if let url = action.url {
            NSWorkspace.shared.open(url)
            return
        }
        switch action {
        case .copyBrewCommand:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(UpdateCheck.brewCommand, forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
        case .turnOnChecks:
            openSettings()
        case .later:
            updates.dismissReminder()
        case .releaseNotes, .download, .viewReleases:
            break
        }
    }
}

/// Buttons in a row that wraps to the next line when the width runs out,
/// so a long translation costs a line, not a clipped label.
struct WrappingRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let origins = arrange(width: bounds.width, subviews).origins
        for (subview, origin) in zip(subviews, origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, _ subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (CGSize(width: widest, height: y + rowHeight), origins)
    }
}

extension UpdateChecker.Notice {
    var systemImage: String {
        switch self {
        case .available: "arrow.down.circle"
        case .reminder: "clock"
        }
    }
}
