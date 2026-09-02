import SwiftUI

/// The app.
///
/// Two surfaces — the day's Thread and the Catalog — with a scrubbable pinch between
/// them. `app.zoom` is 0 at the Thread and 1 at the Catalog and is driven directly by
/// the gesture, so you can push halfway out, change your mind, and come back.
///
/// The surface you are leaving is captured as a still and warped away (see
/// `SurfaceSnapshot` for why it has to be a still); the surface you are arriving at
/// animates in live underneath it.
struct RootView: View {
    @State private var app = AppModel()
    @Namespace private var mealNamespace

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var transition: SurfaceTransition?
    /// Zoom at the moment the current pinch began, so a gesture can start from either surface.
    @State private var pinchAnchor: Double = 0

    var body: some View {
        @Bindable var app = app

        ZStack {
            background

            if showsThread { threadSurface }
            if showsCatalog { catalogSurface }
            if let transition { still(transition) }

            composerLayer
            topBar
        }
        .background(Palette.paper)
        .gesture(pinch)
        .task { await app.bootstrap() }
        .onChange(of: scenePhase) { _, phase in
            // Flush on the way out rather than relying on the debounce timer, which
            // may not fire if the app is suspended immediately.
            if phase != .active { Task { await app.flush() } }
        }
        .sheet(item: $app.presentedEntry) { reference in
            EntryDetailView(reference: reference)
                .environment(app)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Palette.paper)
        }
        .sheet(isPresented: $app.isShowingSettings) {
            SettingsView()
                .environment(app)
                .presentationBackground(Palette.paper)
        }
        .environment(app)
    }

    // MARK: Which surfaces are live
    //
    // The departing surface is never live during a transition — it is the still.

    private var showsThread: Bool {
        switch transition?.direction {
        case .toCatalog: return false
        case .toThread: return true
        case nil: return app.zoom < 0.5
        }
    }

    private var showsCatalog: Bool {
        switch transition?.direction {
        case .toCatalog: return true
        case .toThread: return false
        case nil: return app.zoom >= 0.5
        }
    }

    /// 0 at the start of the current transition, 1 at its end — whichever way it runs.
    private var progress: Double {
        switch transition?.direction {
        case .toCatalog: return app.zoom
        case .toThread: return 1 - app.zoom
        case nil: return 0
        }
    }

    // MARK: Surfaces

    private var threadSurface: some View {
        DayPager(
            day: Binding(get: { app.focusedDay }, set: { app.focus($0) }),
            earliest: app.earliestDay,
            latest: .today
        ) { day in
            DayThreadView(
                session: app.session(for: day),
                profile: app.profile,
                namespace: mealNamespace,
                onOpenEntry: { app.presentedEntry = .init(id: $0, day: day) },
                onOpenSummary: {}
            )
        }
        // Arriving from the Catalog: rises from slightly small. Scale and opacity are
        // safe on a scroll view; blur and shaders are not.
        .scaleEffect(transition?.direction == .toThread ? 0.9 + 0.1 * progress : 1)
        .opacity(transition?.direction == .toThread ? min(progress * 1.6, 1) : 1)
        .allowsHitTesting(transition == nil)
    }

    private var catalogSurface: some View {
        CatalogView(namespace: mealNamespace) { id, day in
            app.presentedEntry = .init(id: id, day: day)
        }
        .environment(app)
        // Arriving from the Thread: rushes toward you from oversized.
        .scaleEffect(transition?.direction == .toCatalog ? 1.12 - 0.12 * progress : 1)
        .opacity(transition?.direction == .toCatalog ? max(progress * 1.5 - 0.35, 0) : 1)
        .allowsHitTesting(transition == nil)
    }

    /// The departing surface, warped away.
    private func still(_ transition: SurfaceTransition) -> some View {
        let leaving = transition.direction == .toCatalog

        return Image(uiImage: transition.still)
            .resizable()
            .ignoresSafeArea()
            .scaleEffect(leaving ? 1 - 0.18 * progress : 1 + 0.22 * progress)
            .blur(radius: progress * 9)
            .opacity(1 - min(progress * 1.2, 1))
            .platePinchWarp(
                amount: (leaving ? -1 : 1) * progress * 0.9,
                chroma: reduceMotion ? 0 : 1
            )
            .allowsHitTesting(false)
    }

    // MARK: Chrome
    //
    // Live chrome fades in as the still (which contains the old chrome) fades out, so
    // the bars cross-dissolve rather than popping at the end of the transition.

    private var chromeOpacity: Double {
        transition == nil ? 1 : min(progress * 1.4, 1)
    }

    private var composerLayer: some View {
        VStack {
            Spacer()
            let session = app.session(for: app.focusedDay)
            Composer(
                text: Bindable(session).draft,
                isResponding: session.isResponding,
                placeholder: placeholder,
                onSend: { session.send(session.draft) },
                onStop: { session.cancel() }
            )
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
        .opacity((1 - app.zoom * 1.8) * chromeOpacity)
        .offset(y: app.zoom * 44)
        .allowsHitTesting(app.zoom < 0.15 && transition == nil)
    }

    private var topBar: some View {
        VStack {
            HStack(spacing: 12) {
                Button {
                    toggleSurface()
                } label: {
                    Image(systemName: app.zoom > 0.5 ? "bubble.left.and.text.bubble.right" : "square.grid.2x2")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Palette.inkSoft)
                        .frame(width: 34, height: 34)
                        .background(GlassSurface(cornerRadius: 17, thickness: 9))
                }
                .accessibilityLabel(app.zoom > 0.5 ? "Back to the conversation" : "See all meals")

                Spacer()

                if app.focusedDay != .today && app.zoom < 0.5 {
                    Button("Today") { app.focus(.today) }
                        .font(.plateLabel)
                        .foregroundStyle(Palette.ember)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(GlassSurface(cornerRadius: 17, thickness: 9))
                        .transition(.scale.combined(with: .opacity))
                }

                Button {
                    app.isShowingSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Palette.inkSoft)
                        .frame(width: 34, height: 34)
                        .background(GlassSurface(cornerRadius: 17, thickness: 9))
                }
                .accessibilityLabel("Settings")
            }
            .padding(.horizontal, 14)
            .padding(.top, 4)

            Spacer()
        }
        .opacity(chromeOpacity)
        .allowsHitTesting(transition == nil)
        .plateAnimation(Motion.snap, value: app.focusedDay)
        .plateAnimation(Motion.snap, value: app.zoom > 0.5)
    }

    /// A wash that tracks the hour. Never announced, but 7am and 9pm shouldn't feel
    /// identical.
    private var background: some View {
        let wash = Palette.groundWash(hour: Calendar.current.component(.hour, from: .now))
        return LinearGradient(
            colors: [wash.top, wash.bottom],
            startPoint: .top,
            endPoint: .center
        )
        .ignoresSafeArea()
    }

    private var placeholder: String {
        app.focusedDay.isToday ? "What did you eat?" : "Add to \(app.focusedDay.title.lowercased())"
    }

    // MARK: Transition control

    private var pinch: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.004)
            .onChanged { value in
                if transition == nil {
                    // Capture before anything moves, so the still is of the surface at rest.
                    guard let image = SurfaceSnapshot.capture() else { return }
                    transition = SurfaceTransition(
                        direction: app.zoom < 0.5 ? .toCatalog : .toThread,
                        still: image
                    )
                    pinchAnchor = app.zoom
                    Haptics.shared.prepare()
                }

                // Pinching in pushes toward the Catalog. The 1.7 multiplier means the
                // full transition takes a comfortable pinch rather than requiring the
                // fingers to meet.
                let next = min(max(pinchAnchor + (1 - value.magnification) * 1.7, 0), 1)
                if (next > 0.5) != (app.zoom > 0.5) { Haptics.shared.detent() }
                app.zoom = next
            }
            .onEnded { _ in
                settle(to: app.zoom > 0.5 ? 1 : 0)
            }
    }

    /// The visible alternative to the pinch. Gestures need one.
    private func toggleSurface() {
        let target: Double = app.zoom > 0.5 ? 0 : 1
        if transition == nil, let image = SurfaceSnapshot.capture() {
            transition = SurfaceTransition(
                direction: target > 0.5 ? .toCatalog : .toThread,
                still: image
            )
        }
        Haptics.shared.select()
        settle(to: target)
    }

    private func settle(to target: Double) {
        withAnimation(reduceMotion ? Motion.reduced : Motion.glide, completionCriteria: .logicallyComplete) {
            app.zoom = target
            app.surface = target > 0.5 ? .catalog : .thread
        } completion: {
            // Drop the still only once it has finished fading, or the departing surface
            // blinks out a frame early.
            transition = nil
            pinchAnchor = target
        }
    }
}

#Preview {
    RootView()
}
