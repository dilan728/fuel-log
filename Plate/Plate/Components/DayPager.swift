import SwiftUI

/// Horizontal paging across days.
///
/// Hand-built rather than a paged `TabView` because the neighbouring days need to be
/// visibly *behind* the current one — scaled back and dimmed — which is the cue that
/// makes a swipe feel like turning a page rather than sliding a panel. Only three days
/// are ever alive at once.
struct DayPager<Content: View>: View {
    @Binding var day: DayID
    let earliest: DayID
    let latest: DayID
    @ViewBuilder var content: (DayID) -> Content

    @State private var drag: CGFloat = 0
    @State private var isSettling = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            HStack(spacing: 0) {
                page(day.advanced(by: -1), size: proxy.size, slot: -1)
                page(day, size: proxy.size, slot: 0)
                page(day.advanced(by: 1), size: proxy.size, slot: 1)
            }
            // Height matters as much as width here: a GeometryReader sizes its content
            // to *ideal*, not to fill, so without this the page collapses to the height
            // of its header and the scrolling body never appears.
            .frame(width: width * 3, height: height, alignment: .leading)
            .offset(x: -width + drag)
            .contentShape(Rectangle())
            .gesture(gesture(width: width))
        }
    }

    @ViewBuilder
    private func page(_ pageDay: DayID, size: CGSize, slot: Int) -> some View {
        // How far this page is from centre, in pages. 0 is front and centre.
        let distance = abs(Double(slot) - Double(drag / max(size.width, 1)))
        let isReachable = pageDay >= earliest && pageDay <= latest

        Group {
            if isReachable {
                content(pageDay)
            } else {
                // Past the ends there is nothing to show; the rubber band means this
                // is only ever briefly visible.
                Color.clear
            }
        }
        .frame(width: size.width, height: size.height)
        .scaleEffect(1 - 0.05 * min(distance, 1))
        .opacity(1 - 0.55 * min(distance, 1))
        .allowsHitTesting(slot == 0 && drag == 0)
    }

    private func gesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                guard !isSettling else { return }
                // Only steal horizontal drags — the thread underneath scrolls vertically.
                guard abs(value.translation.width) > abs(value.translation.height) else { return }

                let proposed = value.translation.width
                let wantsPast = proposed > 0 ? day.advanced(by: -1) < earliest
                                             : day.advanced(by: 1) > latest
                drag = wantsPast
                    ? Curve.rubberBand(offset: proposed, dimension: width)
                    : proposed
            }
            .onEnded { value in
                guard !isSettling else { return }

                let velocity = value.predictedEndTranslation.width
                let shouldTurn = abs(velocity) > width * 0.32 || abs(drag) > width * 0.4
                let direction = drag > 0 ? -1 : 1

                guard shouldTurn, drag != 0 else {
                    withAnimation(Motion.glide) { drag = 0 }
                    return
                }

                let target = day.advanced(by: direction)
                guard target >= earliest, target <= latest else {
                    withAnimation(Motion.glide) { drag = 0 }
                    return
                }

                isSettling = true
                Haptics.shared.pageTurn()

                // Animate the turn, then swap the anchor day and snap back to centre in
                // the same frame the animation lands, so nothing visibly jumps.
                withAnimation(Motion.glide, completionCriteria: .logicallyComplete) {
                    drag = CGFloat(-direction) * width
                } completion: {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        day = target
                        drag = 0
                    }
                    isSettling = false
                }
            }
    }
}
