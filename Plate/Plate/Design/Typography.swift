import SwiftUI

/// Plate's type scale.
///
/// Serif for content — food names, numbers, dates. Sans for chrome — labels, buttons,
/// captions. That split is most of what makes the app read like a page rather than a
/// dashboard.
///
/// Every style carries its own tracking, because the correct value is a function of
/// size and it is the detail most often left at zero: large type needs to be pulled in,
/// and small uppercase type falls apart without being opened out.
enum TypeStyle {
    /// The day's energy figure. Once per screen, and nothing else at this size.
    case masthead
    /// A compressed masthead, for the collapsed header.
    case mastheadSmall
    /// Section titles, food names in detail.
    case title
    /// Food names in a row, catalog captions.
    case subtitle
    /// Chat, prose.
    case body
    /// Buttons, inline controls.
    case label
    /// Uppercase micro-labels: dates, meal names, section titles.
    case micro
    /// Lower-case units sitting beside a figure. Separate from `.micro` because a unit
    /// set in caps competes with the number it belongs to.
    case unit
    /// Figures inside dense contexts. Tabular, so columns of numbers align and animated
    /// values do not jitter.
    case numeric
    /// A row's energy figure.
    case numericLarge

    var font: Font {
        switch self {
        case .masthead:      return .system(size: 44, weight: .regular, design: .serif)
        case .mastheadSmall: return .system(size: 26, weight: .regular, design: .serif)
        case .title:         return .system(size: 22, weight: .regular, design: .serif)
        case .subtitle:      return .system(size: 17, weight: .regular, design: .serif)
        case .body:          return .system(size: 16, weight: .regular)
        case .label:         return .system(size: 13, weight: .medium)
        case .micro:         return .system(size: 10.5, weight: .semibold)
        case .unit:          return .system(size: 11, weight: .medium)
        case .numeric:       return .system(size: 14, weight: .medium).monospacedDigit()
        case .numericLarge:  return .system(size: 19, weight: .regular, design: .serif).monospacedDigit()
        }
    }

    /// Negative at display sizes, positive for small uppercase. The single most
    /// neglected typographic control.
    var tracking: CGFloat {
        switch self {
        case .masthead:      return -1.4
        case .mastheadSmall: return -0.7
        case .title:         return -0.35
        case .subtitle:      return -0.15
        case .body:          return 0
        case .label:         return 0
        case .micro:         return 0.85
        case .unit:          return 0.1
        case .numeric:       return 0
        case .numericLarge:  return -0.2
        }
    }

    var lineSpacing: CGFloat {
        switch self {
        case .body:  return 5
        case .title: return 2
        default:     return 0
        }
    }

    var isUppercase: Bool { self == .micro }
}

extension View {
    func typeStyle(_ style: TypeStyle, _ color: Color = Palette.ink) -> some View {
        self
            .font(style.font)
            .tracking(style.tracking)
            .lineSpacing(style.lineSpacing)
            .textCase(style.isUppercase ? .uppercase : nil)
            .foregroundStyle(color)
    }
}

extension Text {
    /// `Text`-preserving variant, so styled runs can still be concatenated. Case is not
    /// applied here — `Text` has no case transform, so uppercase styles need `.typeStyle`.
    func typed(_ style: TypeStyle, _ color: Color = Palette.ink) -> Text {
        font(style.font)
            .tracking(style.tracking)
            .foregroundColor(color)
    }
}
