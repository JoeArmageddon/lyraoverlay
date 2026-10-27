import SwiftUI
import UniformTypeIdentifiers
import LyraCore

/// Helpers for drawing a font's own preview in SwiftUI through the same resolver the overlay uses,
/// so a row looks exactly like the lyrics will.
enum FontPreview {
    static func font(_ family: String, size: CGFloat, weight: Double = 0.4, italic: Bool = false) -> Font {
        Font(FontResolver.ctFont(FontSpec(family: family, size: Double(size), weight: weight, italic: italic)))
    }

    /// Invented, lyric-length phrases for the sample lines. Rows rotate through them so the list
    /// shows different letters rather than one repeated phrase.
    static let samples = [
        "Midnight in the city lights",
        "Hold on to the feeling",
        "We were golden in the rain",
        "Turn it up and let it ring",
        "Dancing through the afterglow",
        "Every window holds a story",
        "Run with me till morning",
        "Echoes on the avenue",
    ]

    static func sample(_ index: Int) -> String { samples[abs(index) % samples.count] }
}

/// A searchable list of fonts, each shown in itself, with category chips and a place to add your own.
/// Selecting one writes `overlay.font.family`.
struct FontPicker: View {
    @ObservedObject var model: SettingsModel
    @State private var query = ""
    @State private var chip = Chip.all
    @State private var installed = FontCatalog.families()
    @State private var userFonts = FontCatalog.userFonts()
    @State private var dropTargeted = false
    @State private var pendingRemoval: UserFont?

    init(model: SettingsModel, initialChip: Chip = .all) {
        self.model = model
        _chip = State(initialValue: initialChip)
    }

    enum Chip: Hashable {
        case all
        case myFonts
        case category(FontCategory)

        var title: String {
            switch self {
            case .all: return "All"
            case .myFonts: return "My Fonts"
            case .category(let c):
                switch c {
                case .originals: return "Lyra Originals"
                case .handDrawn: return "Hand-Drawn"
                case .sans: return "Sans"
                case .serif: return "Serif"
                case .display: return "Display"
                case .mono: return "Mono"
                case .rounded: return "Rounded"
                case .condensed: return "Condensed"
                case .novelty: return "More System Fonts"
                }
            }
        }

        static var all_: [Chip] { [.all, .myFonts] + FontCategory.allCases.map { .category($0) } }
    }

    struct Row: Identifiable, Equatable {
        /// The value stored in `FontSpec.family`.
        let id: String
        let name: String
        /// Set for an imported font: its file in the user fonts folder (it can be removed).
        var userFileName: String? = nil
    }

    struct Group: Identifiable, Equatable {
        let title: String
        let rows: [Row]
        var id: String { title }
    }

    static let installedTitle = "All installed fonts"
    static let myFontsTitle = "My Fonts"
    static let emptyStateText = "Drop font files here or click Add Custom Font"
    static let storageHint = "Added fonts are copied to Application Support/Lyra/Fonts and load every time Lyra starts."

    /// A note for the picker when the saved font isn't installed (a removed custom font, or a theme made
    /// on another Mac). Lyra draws the system font meanwhile. Nil when the font is fine.
    static func missingFontNote(current: String) -> String? {
        guard !current.isEmpty, current != "System", !FontCatalog.isInstalled(current) else { return nil }
        return "“\(current)” isn't installed, so Lyra is using the system font. Add it again or pick another font."
    }

    /// The groups to show for a search and a chip. Pure, so the ordering rules are testable:
    /// My Fonts first (when there are any), then featured categories in their fixed order (Lyra Originals
    /// first, system extras last), then every other installed family, with the current font added if it
    /// is installed but in none of those lists.
    static func groups(query: String, chip: Chip, installed: [String], current: String,
                       userFonts: [UserFont] = FontCatalog.userFonts()) -> [Group] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        func matches(_ name: String) -> Bool { needle.isEmpty || name.lowercased().contains(needle) }

        var result: [Group] = []
        // A copy of a font that already ships with Lyra (say, a Lyra font imported by hand earlier) is not "yours".
        let shipped = Set(FontCatalog.featured.map(\.id))
        let mine = userFonts.filter { !$0.postScriptNames.isEmpty && !$0.postScriptNames.allSatisfy(shipped.contains) }
        if chip == .all || chip == .myFonts {
            let rows = mine.filter { matches($0.displayName) || $0.families.contains(where: matches) }
                .map { Row(id: $0.fontID, name: $0.displayName, userFileName: $0.fileName) }
            if !rows.isEmpty { result.append(Group(title: myFontsTitle, rows: rows)) }
        }
        if chip == .myFonts { return result }

        for (category, fonts) in FontCatalog.featuredByCategory() {
            if case .category(let wanted) = chip, wanted != category { continue }
            let rows = fonts.filter { matches($0.name) }.map { Row(id: $0.id, name: $0.name) }
            if !rows.isEmpty { result.append(Group(title: category.title, rows: rows)) }
        }

        if chip == .all {
            var taken = Set(FontCatalog.featured.map(\.id))
            for font in mine { taken.formUnion(font.families); taken.formUnion(font.postScriptNames) }
            var others = installed.filter { !taken.contains($0) }
            if !taken.contains(current), !others.contains(current), FontCatalog.isInstalled(current) { others.insert(current, at: 0) }
            let rows = others.filter { matches($0) }.map { Row(id: $0, name: $0) }
            if !rows.isEmpty { result.append(Group(title: installedTitle, rows: rows)) }
        }
        return result
    }

    private var groups: [Group] {
        Self.groups(query: query, chip: chip, installed: installed, current: model.settings.overlay.font.family, userFonts: userFonts)
    }

    var body: some View {
        let groups = groups
        let current = model.settings.overlay.font.family
        VStack(spacing: 0) {
            addBar
            if let note = Self.missingFontNote(current: current) {
                Label(note, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.top, 8)
            }
            searchField
            chips
            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(groups) { group in
                        Section {
                            ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, row in
                                FontRow(id: row.id, name: row.name, sample: FontPreview.sample(index),
                                        selected: row.id == current)
                                    .onTapGesture { model.settings.overlay.font.family = row.id }
                                    .contextMenu { userMenu(for: row) }
                            }
                        } header: {
                            Text(group.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14).padding(.vertical, 5)
                                .background(.regularMaterial)
                        }
                    }
                    if chip == .myFonts, userFonts.isEmpty {
                        emptyState
                    } else if groups.isEmpty {
                        Text("No fonts match “\(query)”.").foregroundStyle(.secondary).padding(24)
                    }
                }
            }

            Divider()
            HStack(spacing: 8) {
                Image(systemName: "info.circle").foregroundStyle(.secondary)
                Text(Self.storageHint).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                Text("\(groups.reduce(0) { $0 + $1.rows.count }) fonts").font(.caption).foregroundStyle(.secondary)
            }
            .padding(10)
        }
        .frame(width: 480, height: 600)
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8, 5]))
                    .background(Color.accentColor.opacity(0.08))
                    .overlay { Label("Drop to add custom fonts", systemImage: "square.and.arrow.down").font(.headline) }
                    .padding(6).allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in handleDrop(providers) }
        .onReceive(NotificationCenter.default.publisher(for: FontCatalog.didChangeNotification)) { _ in refresh() }
        .alert("Remove this font?", isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
               presenting: pendingRemoval) { font in
            Button("Remove", role: .destructive) { remove(font) }
            Button("Cancel", role: .cancel) {}
        } message: { font in
            Text("“\(font.displayName)” is deleted from Lyra's custom fonts folder. Themes that use it fall back to the system font.")
        }
    }

    private var addBar: some View {
        HStack(spacing: 10) {
            Button { addFromPanel() } label: {
                Label("Add Custom Font…", systemImage: "plus.circle.fill")
                    .font(.body.weight(.semibold)).foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.accentColor))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button { FontCatalog.revealUserFontsFolder() } label: { Image(systemName: "folder") }
                .controlSize(.large).help("Show the custom fonts folder in Finder")
        }
        .padding([.horizontal, .top], 12)
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Chip.all_, id: \.self) { c in
                    Button { chip = c } label: {
                        HStack(spacing: 4) {
                            Text(c.title)
                            if c == .myFonts, !userFonts.isEmpty { Text("\(userFonts.count)").opacity(0.7) }
                        }
                        .font(.caption).padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(chip == c ? Color.accentColor : Color.secondary.opacity(0.18)))
                        .foregroundStyle(chip == c ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "textformat").font(.system(size: 34)).foregroundStyle(.secondary)
            Text(Self.emptyStateText).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Text(".ttf  .otf  .ttc  .otc").font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 48)
    }

    @ViewBuilder private func userMenu(for row: Row) -> some View {
        if let file = row.userFileName, let font = userFonts.first(where: { $0.fileName == file }) {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([font.url]) }
            Button("Remove…", role: .destructive) { pendingRemoval = font }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search fonts", text: $query).textFieldStyle(.plain)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.15)))
        .padding([.horizontal, .top], 12)
    }

    // MARK: - Actions

    private func refresh() {
        installed = FontCatalog.families()
        userFonts = FontCatalog.userFonts()
    }

    private func finish(_ results: [ImportResult]) {
        guard !results.isEmpty else { return }
        refresh()
        model.message = ImportResult.summary(results)
        if let id = results.first(where: \.succeeded)?.fontID {
            model.settings.overlay.font.family = id
            chip = .myFonts
        }
    }

    private func addFromPanel() { finish(FontCatalog.addCustomFontsFromPanel()) }

    /// The file URLs carried by dropped items, delivered on the main queue.
    static func fileURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        let providers = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { lock.withLock { urls.append(url) } }
                group.leave()
            }
        }
        group.notify(queue: .main) { completion(urls.sorted { $0.path < $1.path }) }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard providers.contains(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else { return false }
        Self.fileURLs(from: providers) { finish(FontCatalog.importFonts(urls: $0)) }
        return true
    }

    private func remove(_ font: UserFont) {
        do {
            try FontCatalog.removeUserFont(font)
            model.message = "Removed \(font.displayName)."
        } catch {
            model.message = error.localizedDescription
        }
        refresh()
    }
}

/// One row: the font's name in small type and a lyric-length sample drawn in the font itself.
struct FontRow: View {
    let id: String
    let name: String
    let sample: String
    let selected: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.caption).foregroundStyle(.secondary)
                Text(sample)
                    .font(FontPreview.font(id, size: 24))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 8)
            if selected { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(selected ? Color.accentColor.opacity(0.14) : Color.clear)
        .contentShape(Rectangle())
    }
}
