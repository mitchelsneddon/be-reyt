import Foundation

/// Optional 1...5 day score. Absence is modelled by `nil` at the call site, never 0.
public enum DayScore: Int, CaseIterable, Sendable, Codable {
    case veryDifficult = 1
    case difficult
    case okay
    case good
    case excellent

    public init?(_ value: Int) { self.init(rawValue: value) }

    public var label: String {
        switch self {
        case .veryDifficult: "very difficult"
        case .difficult: "difficult"
        case .okay: "okay"
        case .good: "good"
        case .excellent: "excellent"
        }
    }
}
