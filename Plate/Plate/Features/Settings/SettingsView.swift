import SwiftUI

/// Settings.
///
/// Framed as *upgrading* the app rather than as making it work — Plate is complete with
/// nothing configured, so nothing here is marked missing or required, and each row says
/// what a key adds rather than what its absence breaks.
///
/// Set as a ruled list rather than as grouped cards: the same structure, none of the
/// furniture.
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var calorieTarget = ""
    @State private var proteinTarget = ""
    @State private var context = ""
    @State private var cacheSize: Int64 = 0
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.generous) {
                    connections
                    you
                    imagery
                    about
                }
                .padding(.vertical, Metrics.wide)
            }
            .background(Palette.paper)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save(); dismiss() }
                        .typeStyle(.label, Palette.ember)
                }
            }
        }
        .task { load() }
    }

    // MARK: Sections

    private var connections: some View {
        SettingsSection(
            "Connections",
            note: "Plate works without any of these. Adding one upgrades that part of the app. Keys are kept in the Keychain and only ever sent to the service they belong to."
        ) {
            ForEach(Array(CredentialKey.allCases.enumerated()), id: \.element) { index, key in
                if index > 0 { Hairline(inset: Metrics.margin) }
                KeyRow(key: key)
            }
        }
    }

    private var you: some View {
        SettingsSection(
            "You",
            note: "All optional. A target turns the measure into a goal; leave it empty and it shows composition only."
        ) {
            SettingsField(label: "Name", placeholder: "What to call you", text: $name)
            Hairline(inset: Metrics.margin)
            SettingsField(label: "Calories", placeholder: "No target", text: $calorieTarget, keyboard: .numberPad)
            Hairline(inset: Metrics.margin)
            SettingsField(label: "Protein", placeholder: "No target", text: $proteinTarget, keyboard: .numberPad)
            Hairline(inset: Metrics.margin)
            SettingsField(label: "Notes", placeholder: "Vegetarian, training for a half…", text: $context, axis: .vertical)
        }
    }

    private var imagery: some View {
        SettingsSection(
            "Pictures",
            note: "Images are cached by food, so each dish is made once and reused everywhere it appears."
        ) {
            HStack {
                Text("Cached").typeStyle(.body)
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: cacheSize, countStyle: .file))
                    .typeStyle(.numeric, Palette.inkFaint)
            }
            .plateMargins()
            .padding(.vertical, Metrics.wide)

            Hairline(inset: Metrics.margin)
            Button {
                isWorking = true
                Task {
                    await app.backfillImages()
                    isWorking = false
                    cacheSize = ImageCache.shared.diskUsage()
                }
            } label: {
                settingsAction(
                    isWorking ? "Working…" : (FoodImageService.shared.isConfigured
                                              ? "Photograph past meals"
                                              : "Render past meals"),
                    tint: Palette.ember,
                    showsSpinner: isWorking
                )
            }
            .buttonStyle(RowPressStyle())
            .disabled(isWorking)

            Hairline(inset: Metrics.margin)
            Button {
                ImageCache.shared.removeAll()
                cacheSize = 0
                Haptics.shared.select()
            } label: {
                settingsAction("Clear cached pictures", tint: Palette.alert)
            }
            .buttonStyle(RowPressStyle())
        }
    }

    private func settingsAction(_ title: String, tint: Color, showsSpinner: Bool = false) -> some View {
        HStack {
            Text(title).typeStyle(.body, tint)
            Spacer()
            if showsSpinner { ProgressView().controlSize(.small) }
        }
        .plateMargins()
        .padding(.vertical, Metrics.wide)
        .contentShape(Rectangle())
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: Metrics.tight) {
            Hairline()
            Text("Plate")
                .typeStyle(.subtitle, Palette.inkSoft)
                .padding(.top, Metrics.wide)
            Text(credits)
                .typeStyle(.micro, Palette.inkFaint)
        }
        .plateMargins()
    }

    private var credits: String {
        let brain = Credentials.has(.anthropic) ? "Claude" : "on-device parsing"
        let eyes = FoodImageService.shared.provider?.displayName ?? "on-device rendering"
        return "Conversation by \(brain) · Pictures by \(eyes)"
    }

    // MARK: Data

    private func load() {
        name = app.profile.name ?? ""
        calorieTarget = app.profile.calorieTarget.map { String(Int($0)) } ?? ""
        proteinTarget = app.profile.proteinTarget.map { String(Int($0)) } ?? ""
        context = app.profile.context ?? ""
        cacheSize = ImageCache.shared.diskUsage()
    }

    private func save() {
        let name = name, context = context
        let calories = Double(calorieTarget), protein = Double(proteinTarget)
        Task {
            await app.saveProfile { profile in
                profile.name = name.isEmpty ? nil : name
                profile.context = context.isEmpty ? nil : context
                profile.calorieTarget = calories
                profile.proteinTarget = protein
                profile.hasCompletedOnboarding = true
            }
        }
    }
}

// MARK: - Pieces

private struct SettingsSection<Content: View>: View {
    let title: String
    var note: String?
    @ViewBuilder var content: Content

    init(_ title: String, note: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.note = note
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .typeStyle(.micro, Palette.inkFaint)
                .plateMargins()
                .padding(.bottom, Metrics.snug)

            Hairline()
            content
            Hairline()

            if let note {
                Text(note)
                    .typeStyle(.note, Palette.inkFaint)
                    .plateMargins()
                    .padding(.top, Metrics.step)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SettingsField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var axis: Axis = .horizontal

    var body: some View {
        HStack(alignment: .top, spacing: Metrics.step) {
            Text(label)
                .typeStyle(.body)
                .frame(width: 76, alignment: .leading)

            TextField(placeholder, text: $text, axis: axis)
                .typeStyle(.body)
                .tint(Palette.ember)
                .keyboardType(keyboard)
                .multilineTextAlignment(axis == .horizontal ? .trailing : .leading)
                .lineLimit(axis == .vertical ? 1...4 : 1...1)
        }
        .plateMargins()
        .padding(.vertical, Metrics.wide)
    }
}

/// One API key. Shows a redacted form once set, and never re-displays the secret.
private struct KeyRow: View {
    let key: CredentialKey

    @State private var isEditing = false
    @State private var entry = ""
    @State private var stored: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.step) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(key.displayName).typeStyle(.body)
                    Text(key.purpose).typeStyle(.micro, Palette.inkFaint)
                }

                Spacer(minLength: Metrics.step)

                if let stored, !isEditing {
                    Text(stored)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Palette.inkFaint)
                }

                Button(buttonTitle) {
                    if isEditing {
                        Credentials.set(entry, for: key)
                        entry = ""
                        isEditing = false
                        refresh()
                        Haptics.shared.commit()
                    } else if stored != nil {
                        Credentials.set(nil, for: key)
                        refresh()
                        Haptics.shared.select()
                    } else {
                        withAnimation(Motion.snap) { isEditing = true }
                    }
                }
                .typeStyle(.micro, stored != nil && !isEditing ? Palette.alert : Palette.ember)
            }

            if isEditing {
                SecureField("Paste key", text: $entry)
                    .font(.system(size: 12, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(Metrics.step)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Palette.inkGhost.opacity(0.4))
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .plateMargins()
        .padding(.vertical, Metrics.wide)
        .task { refresh() }
    }

    private var buttonTitle: String {
        if isEditing { return "Save" }
        return stored == nil ? "Add" : "Remove"
    }

    private func refresh() { stored = Credentials.redacted(for: key) }
}
