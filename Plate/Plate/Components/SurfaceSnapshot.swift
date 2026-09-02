import SwiftUI
import UIKit

/// A still of whatever is currently on screen.
///
/// The zoom transition warps, blurs and chromatically separates the surface you are
/// leaving. None of those can be applied to a live surface here: both Thread and
/// Catalog are scroll views, and a shader or blur on an ancestor of a `ScrollView`
/// stops its content from rendering at all — you get a correctly-sized empty box.
///
/// So the departing surface is captured once, at the moment the gesture begins, and it
/// is the *still* that gets warped away while the arriving surface animates in live.
/// This is also how you would want it for performance: one texture, warped, instead of
/// a full re-render of a scrolling hierarchy every frame.
enum SurfaceSnapshot {

    @MainActor
    static func capture() -> UIImage? {
        guard let window = activeWindow else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = window.screen.scale

        return UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            // `afterScreenUpdates: false` reuses what has already been rendered. It is
            // both much faster and safer here — forcing an update mid-gesture can
            // re-enter layout and deadlock the very view we are capturing.
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
    }

    @MainActor
    private static var activeWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .keyWindow
    }
}

/// One in-flight surface transition.
struct SurfaceTransition: Equatable {
    enum Direction { case toCatalog, toThread }

    var direction: Direction
    var still: UIImage

    static func == (lhs: SurfaceTransition, rhs: SurfaceTransition) -> Bool {
        lhs.direction == rhs.direction && lhs.still === rhs.still
    }
}
