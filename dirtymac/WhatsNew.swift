import SwiftUI

// MARK: - Release notes

/// One user-facing change, as shown in the What's New window. Keep these
/// short and about what the user can now do — the CHANGELOG carries the
/// engineering detail.
struct ReleaseNoteItem: Identifiable {
    let id = UUID()
    let systemImage: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
}

struct ReleaseNote: Identifiable {
    /// Marketing version (CFBundleShortVersionString) this entry ships in.
    let version: String
    let items: [ReleaseNoteItem]

    var id: String { version }
}

enum WhatsNew {
    static let lastSeenKey = "whatsNewLastSeenVersion"

    /// Newest first. Add an entry here in the same commit that bumps
    /// MARKETING_VERSION for a release with user-visible changes; a
    /// release without an entry simply shows no window.
    static let catalog: [ReleaseNote] = [
        ReleaseNote(version: "1.2.0", items: [
            ReleaseNoteItem(
                systemImage: "command",
                title: "Global shortcut",
                detail: "Open dirtymac from any app with ⌃⌥⌘K. Pick another combination or turn it off in Settings."
            ),
            ReleaseNoteItem(
                systemImage: "magnifyingglass",
                title: "Spotlight and Shortcuts",
                detail: "Search for “Lock keyboard” in Spotlight or add it to a shortcut. It works even when dirtymac isn't running."
            ),
            ReleaseNoteItem(
                systemImage: "power",
                title: "Open at login",
                detail: "dirtymac can start with your Mac, so it's always one shortcut away."
            ),
            ReleaseNoteItem(
                systemImage: "sparkles",
                title: "What's New",
                detail: "This window appears once after each update so you never miss a change."
            ),
        ]),
    ]

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Entries to show after an update: everything newer than the last
    /// version the user saw, up to the running one — so skipping a
    /// release doesn't hide its notes.
    ///
    /// `lastSeen == nil` means the user predates this window. They get the
    /// running version's entry only; replaying the whole history at them
    /// would be noise.
    static func notesToShow(
        current: String,
        lastSeen: String?,
        catalog: [ReleaseNote] = catalog
    ) -> [ReleaseNote] {
        let upToCurrent = catalog.filter { compare($0.version, current) != .orderedDescending }
        guard let lastSeen else {
            return upToCurrent.filter { compare($0.version, current) == .orderedSame }
        }
        return upToCurrent
            .filter { compare($0.version, lastSeen) == .orderedDescending }
            .sorted { compare($0.version, $1.version) == .orderedDescending }
    }

    /// Every entry up to the running version, newest first — for opening
    /// the window by hand from Settings.
    static func allNotes(current: String, catalog: [ReleaseNote] = catalog) -> [ReleaseNote] {
        catalog
            .filter { compare($0.version, current) != .orderedDescending }
            .sorted { compare($0.version, $1.version) == .orderedDescending }
    }

    /// Numeric dotted-version comparison: "1.10.0" > "1.9.2", and missing
    /// components count as zero ("1.2" == "1.2.0").
    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let lhs = a.split(separator: ".").map { Int($0) ?? 0 }
        let rhs = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(lhs.count, rhs.count) {
            let l = i < lhs.count ? lhs[i] : 0
            let r = i < rhs.count ? rhs[i] : 0
            if l != r { return l < r ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    static var lastSeenVersion: String? {
        UserDefaults.standard.string(forKey: lastSeenKey)
    }

    static func markCurrentSeen() {
        UserDefaults.standard.set(currentVersion, forKey: lastSeenKey)
    }
}

// MARK: - View

struct WhatsNewView: View {
    let notes: [ReleaseNote]
    /// Existing users are offered launch-at-login here once; it's the
    /// only place they'd otherwise discover it.
    let offerLaunchAtLogin: Bool
    var onFinish: (_ launchAtLogin: Bool) -> Void

    @State private var launchAtLogin = true

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 36)
                .padding(.horizontal, 32)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(notes) { note in
                        noteSection(note)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 20)
            }
            .frame(maxHeight: 360)
            .fixedSize(horizontal: false, vertical: true)

            footer
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
        }
        .frame(width: 460)
        .background(.background)
    }

    private var header: some View {
        VStack(spacing: 12) {
            AppIconView(size: 64)
            Text("What's New in dirtymac")
                .font(.title2).fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func noteSection(_ note: ReleaseNote) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Version \(note.version)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(note.items) { item in
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: item.systemImage)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.tint)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.headline)
                        Text(item.detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if offerLaunchAtLogin {
                Toggle("Open dirtymac at login", isOn: $launchAtLogin)
                    .toggleStyle(.checkbox)
            }
            Spacer()
            Button("Continue") { onFinish(offerLaunchAtLogin && launchAtLogin) }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }
}

#Preview {
    WhatsNewView(notes: WhatsNew.catalog, offerLaunchAtLogin: true, onFinish: { _ in })
}
