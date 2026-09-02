import CoreHaptics
import UIKit

/// Plate's haptic vocabulary.
///
/// The standard generators cover most of it, but two moments get bespoke Core Haptics
/// patterns because they are the app's signature: a meal *landing* in the log, and an
/// image *resolving* out of noise. Both are continuous textures rather than taps, which
/// the UIKit generators cannot express.
@MainActor
final class Haptics {
    static let shared = Haptics()

    private var engine: CHHapticEngine?
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let selection = UISelectionFeedbackGenerator()
    private let notice = UINotificationFeedbackGenerator()

    private init() {
        prepareEngine()
    }

    // MARK: Simple

    /// Crossing a day boundary in the pager.
    func pageTurn() { soft.impactOccurred(intensity: 0.7) }

    /// Any discrete selection: a chip, a segment, a macro toggle.
    func select() { selection.selectionChanged() }

    /// A button that commits something.
    func commit() { rigid.impactOccurred(intensity: 0.8) }

    /// Reaching a detent in a continuous gesture (the pinch snapping to Catalog).
    func detent() { light.impactOccurred(intensity: 0.55) }

    func failure() { notice.notificationOccurred(.error) }

    /// Call before a gesture begins so the Taptic engine is warm and the first
    /// impact isn't late.
    func prepare() {
        light.prepare()
        soft.prepare()
        rigid.prepare()
        selection.prepare()
    }

    // MARK: Bespoke textures

    /// A meal landing in the log: a soft swell that resolves into a single click.
    /// Reads like something being *set down*.
    func mealLanded() {
        play(events: [
            .init(
                eventType: .hapticContinuous,
                parameters: [
                    .init(parameterID: .hapticIntensity, value: 0.35),
                    .init(parameterID: .hapticSharpness, value: 0.15)
                ],
                relativeTime: 0,
                duration: 0.18
            ),
            .init(
                eventType: .hapticTransient,
                parameters: [
                    .init(parameterID: .hapticIntensity, value: 0.85),
                    .init(parameterID: .hapticSharpness, value: 0.6)
                ],
                relativeTime: 0.18
            )
        ], fallback: { rigid.impactOccurred(intensity: 0.9) })
    }

    /// An image resolving: a low, grainy rumble that fades out. Matches the
    /// `materialize` shader's duration so the two land together.
    func materialize() {
        var events: [CHHapticEvent] = []
        let steps = 7
        for i in 0..<steps {
            let t = Double(i) / Double(steps - 1)
            events.append(
                .init(
                    eventType: .hapticTransient,
                    parameters: [
                        .init(parameterID: .hapticIntensity, value: Float(0.28 * (1 - t))),
                        .init(parameterID: .hapticSharpness, value: Float(0.1 + 0.5 * t))
                    ],
                    relativeTime: t * 0.55
                )
            )
        }
        play(events: events, fallback: { soft.impactOccurred(intensity: 0.4) })
    }

    // MARK: Engine

    private func prepareEngine() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        engine = try? CHHapticEngine()
        // The system stops the engine when the app backgrounds; restart lazily
        // rather than holding it running and burning power.
        engine?.stoppedHandler = { [weak self] _ in
            Task { @MainActor in self?.engine = nil }
        }
        engine?.resetHandler = { [weak self] in
            Task { @MainActor in try? self?.engine?.start() }
        }
        try? engine?.start()
    }

    private func play(events: [CHHapticEvent], fallback: () -> Void) {
        if engine == nil { prepareEngine() }
        guard let engine,
              let pattern = try? CHHapticPattern(events: events, parameters: []),
              let player = try? engine.makePlayer(with: pattern),
              (try? player.start(atTime: CHHapticTimeImmediate)) != nil
        else {
            fallback()
            return
        }
    }
}
