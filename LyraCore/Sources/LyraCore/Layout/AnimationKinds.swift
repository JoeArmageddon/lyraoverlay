import Foundation

/// How a lyric line arrives. Applied on top of the style's own layout, per line and per word.
/// `.fade` is the baseline every style already has (a quick fade-in) and adds nothing extra.
public enum EntranceAnimation: String, Codable, CaseIterable, Sendable {
    case none
    case fade
    case rise
    case drop
    case slideLeft
    case slideRight
    case zoomIn
    case zoomOut
    case spring
    case blur
    case cascade
    case glitch

    public var title: String {
        switch self {
        case .none: return "None"
        case .fade: return "Fade"
        case .rise: return "Rise"
        case .drop: return "Drop"
        case .slideLeft: return "Slide from Left"
        case .slideRight: return "Slide from Right"
        case .zoomIn: return "Zoom In"
        case .zoomOut: return "Zoom Out"
        case .spring: return "Spring"
        case .blur: return "Focus Pull"
        case .cascade: return "Cascade"
        case .glitch: return "Glitch"
        }
    }
}

/// How a finished line leaves. `.fade` is the baseline every style already has.
public enum ExitAnimation: String, Codable, CaseIterable, Sendable {
    case none
    case fade
    case rise
    case shrink
    case blur

    public var title: String {
        switch self {
        case .none: return "None"
        case .fade: return "Fade"
        case .rise: return "Float Up"
        case .shrink: return "Shrink"
        case .blur: return "Defocus"
        }
    }
}
