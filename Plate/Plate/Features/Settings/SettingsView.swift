import SwiftUI

/// Settings.
///
/// The framing matters here: Plate works with nothing configured, so this screen is
/// about *upgrading* the app rather than about making it function. Nothing is marked
/// as missing or required, and the copy says what each key adds rather than what its
/// absence breaks.
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var calorieTarget: String = ""
    @State private var proteinTarget: String = ""
    @State private var context: String = ""
    @State private var cacheSize: Int64 = 0
    @State private var isBackfilling = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    connections
                    you
                    photography
                    about
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
            .background(Palette.paper)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save(); dismiss() }
                        .foregroundStyle(Palette.ember)
                }
            }
        }
        .task { load() }
    }

    // MARK: Sections

    private var connections: some View {
        Section(
            "Connections",
            note: "Plate works without any of these. Adding one upgrades that part of the app; keys are kept in the Keychain and only ever sent to the service they belong to."
        ) {
            VStack(spacing: 0) {
                ForEach(Array(CredentialKey.allCases.enumerated()), id: \.element) { index, key in
                    if index > 0 { Divider().overlay(Palette.hairline) }
                    KeyField(key: key)
                }
            }
        }
    }

    private var you: some View {
        Section("You", note: "All optional. Targets turn the ring into a goal; leave them empty and it shows composition only.") {
            VStack(spacing: 0) {
                LabeledField(label: "Name", placeholder: "What to call you", text: $name)
                Divider().overlay(Palette.hairline)
                LabeledField(label: "Calories", placeholder: "No target", text: $calorieTarget, keyboard: .numberPad)
                Divider().overlay(Palette.hairline)
                LabeledField(label: "Protein", placeholder: "No target", text: $proteinTarget, keyboard: .numberPad)
                Divider().overlay(Palette.hairline)
                LabeledField(
                    label: "Notes",
                    placeholder: "Vegetarian, training for a half…",
                    text: $context,
                    axis: .vertical
                )
            }
        }
    }

    private var photography: some View {
        Section("Photography", note: "Images are cached by food, so each dish is generated once and reused everywhere it appears.") {
            VStack(spacing: 0) {
                HStack {
                    Text("Cached images").font(.plateBody).foregroundStyle(Palette.ink)
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: cacheSize, countStyle: .file))
                        .font(.plateNumeric)
                        .foregroundStyle(Palette.inkFaint)
                }
                .padding(14)

                if FoodImageService.shared.isConfigured {
                    Divider().overlay(Palette.hairline)
                    Button {
                        isBackfilling = true
                        Task {
                            await app.backfillImages()
                            isBackfilling = false
                            cacheSize = ImageCache.shared.diskUsage()
                        }
                    } label: {
                        HStack {
                            Text(isBackfilling ? "Filling in…" : "Photograph past meals")
                            Spacer()
                            if isBackfilling { ProgressView().controlSize(.small) }
                        }
                        .font(.plateBody)
                        .foregroundStyle(Palette.ember)
                        .padding(14)
                    }
                    .disabled(isBackfilling)
                }

                Divider().overlay(Palette.hairline)
                Button {
                    ImageCache.shared.removeAll()
                    cacheSize = 0
                    Haptics.shared.select()
                } label: {
                    HStack {
                        Text("Clear cached images")
                        Spacer()
                    }
                    .font(.plateBody)
                    .foregroundStyle(Palette.alert)
                    .padding(14)
                }
            }
        }
    }

    private var about: some View {
        VStack(spacing: 6) {
            Text("Plate")
                .font(.plateTitleSmall)
                .foregroundStyle(Palette.inkSoft)
            Text(agentDescription)
                .font(.plateCaption)
                .foregroundStyle(Palette.inkFaint)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var agentDescription: String {
        let brain = Credentials.has(.anthropic) ? "Claude" : "on-device parsing"
        let eyes = FoodImageService.shared.provider?.displayName ?? "procedural rendering"
        return "Conversation by \(brain) · Imagery by \(eyes)"
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

private struct Section<Content: View>: View {
    let title: String
    var note: String?
    @ViewBuilder var content: Content

    init(_ title: String, note: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.note = note
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).plateCaptionStyle()
                .padding(.leading, 4)

            content
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Palette.paperRaised)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Palette.hairline, lineWidth: 0.5)
                }

            if let note {
                Text(note)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.inkFaint)
                    .padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct LabeledField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var axis: Axis = .horizontal

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.plateBody)
                .foregroundStyle(Palette.ink)
                .frame(width: 74, alignment: .leading)

            TextField(placeholder, text: $text, axis: axis)
                .font(.plateBody)
                .foregroundStyle(Palette.ink)
                .tint(Palette.ember)
                .keyboardType(keyboard)
                .multilineTextAlignment(axis == .horizontal ? .trailing : .leading)
                .lineLimit(axis == .vertical ? 1...4 : 1...1)
        }
        .padding(14)
    }
}

/// One API key. Shows a redacted form once set, and never re-displays the secret.
private struct KeyField: View {
    let key: CredentialKey

    @State private var isEditing = false
    @State private var entry = ""
    @State private var stored: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(key.displayName)
                        .font(.plateBody)
                        .foregroundStyle(Palette.ink)
                    Text(key.purpose)
                        .font(.plateCaption)
                        .foregroundStyle(Palette.inkFaint)
                }

                Spacer()

                if let stored, !isEditing {
                    Text(stored)
                        .font(.system(size: 12, design: .monospaced))
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
                .font(.plateLabel)
                .foregroundStyle(stored != nil && !isEditing ? Palette.alert : Palette.ember)
            }

            if isEditing {
                SecureField("Paste key", text: $entry)
                    .font(.system(size: 13, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(10)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Palette.inkGhost.opacity(0.3))
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .task { refresh() }
    }

    private var buttonTitle: String {
        if isEditing { return "Save" }
        return stored == nil ? "Add" : "Remove"
    }

    private func refresh() {
        stored = Credentials.redacted(for: key)
    }
}
