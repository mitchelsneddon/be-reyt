import SwiftUI

/// A `Shape` built from SVG path data, scaled uniformly (and centred) from its viewBox into the rect it is given.
///
/// Supports M m L l H h V v C c S s Q q T t A a Z z, implicit repeated commands, and compact numbers such as
/// `-.5`, `1.4-1.4` and `5e-1`. Malformed input never crashes: the bad command is skipped, and what was parsed
/// before it is kept.
struct SVGPathShape: Shape {
    let data: String
    let viewBox: CGSize

    init(_ data: String, viewBox: CGFloat) {
        self.data = data
        self.viewBox = CGSize(width: viewBox, height: viewBox)
    }

    init(_ data: String, viewBox: CGSize) {
        self.data = data
        self.viewBox = viewBox
    }

    func path(in rect: CGRect) -> Path {
        guard viewBox.width > 0, viewBox.height > 0 else { return Path() }
        let scale = min(rect.width / viewBox.width, rect.height / viewBox.height)
        let dx = rect.minX + (rect.width - viewBox.width * scale) / 2
        let dy = rect.minY + (rect.height - viewBox.height * scale) / 2
        let transform = CGAffineTransform(translationX: dx, y: dy).scaledBy(x: scale, y: scale)
        return SVGPathParser.parse(data).applying(transform)
    }
}

/// Pure parsing, kept separate from the `Shape` so it is easy to reason about.
enum SVGPathParser {
    static func parse(_ data: String) -> Path {
        var scanner = Scanner(Array(data.unicodeScalars))
        var path = Path()
        var current = CGPoint.zero
        var start = CGPoint.zero
        var lastCubicControl: CGPoint?
        var lastQuadControl: CGPoint?
        var command: Character?

        while true {
            scanner.skipSeparators()
            guard !scanner.atEnd else { break }
            if let letter = scanner.peekCommand() {
                command = letter
                scanner.advance()
                if letter == "Z" || letter == "z" {
                    path.closeSubpath()
                    current = start
                    lastCubicControl = nil
                    lastQuadControl = nil
                    command = nil
                    continue
                }
            } else if command == nil {
                break  // numbers with no command to own them
            }
            guard let cmd = command else { break }
            let relative = cmd.isLowercase
            let base = relative ? current : .zero

            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: base.x + x, y: base.y + y)
            }

            switch cmd.uppercased() {
            case "M":
                guard let x = scanner.number(), let y = scanner.number() else { return path }
                current = point(x, y)
                start = current
                path.move(to: current)
                command = relative ? "l" : "L"  // extra pairs after M are implicit line-tos
                lastCubicControl = nil
                lastQuadControl = nil
            case "L":
                guard let x = scanner.number(), let y = scanner.number() else { return path }
                current = point(x, y)
                path.addLine(to: current)
                lastCubicControl = nil
                lastQuadControl = nil
            case "H":
                guard let x = scanner.number() else { return path }
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: current)
                lastCubicControl = nil
                lastQuadControl = nil
            case "V":
                guard let y = scanner.number() else { return path }
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: current)
                lastCubicControl = nil
                lastQuadControl = nil
            case "C":
                guard let x1 = scanner.number(), let y1 = scanner.number(),
                    let x2 = scanner.number(), let y2 = scanner.number(),
                    let x = scanner.number(), let y = scanner.number()
                else { return path }
                let c1 = point(x1, y1)
                let c2 = point(x2, y2)
                let end = point(x, y)
                path.addCurve(to: end, control1: c1, control2: c2)
                lastCubicControl = c2
                lastQuadControl = nil
                current = end
            case "S":
                guard let x2 = scanner.number(), let y2 = scanner.number(),
                    let x = scanner.number(), let y = scanner.number()
                else { return path }
                let c1 = reflect(lastCubicControl, about: current)
                let c2 = point(x2, y2)
                let end = point(x, y)
                path.addCurve(to: end, control1: c1, control2: c2)
                lastCubicControl = c2
                lastQuadControl = nil
                current = end
            case "Q":
                guard let x1 = scanner.number(), let y1 = scanner.number(),
                    let x = scanner.number(), let y = scanner.number()
                else { return path }
                let c = point(x1, y1)
                let end = point(x, y)
                path.addQuadCurve(to: end, control: c)
                lastQuadControl = c
                lastCubicControl = nil
                current = end
            case "T":
                guard let x = scanner.number(), let y = scanner.number() else { return path }
                let c = reflect(lastQuadControl, about: current)
                let end = point(x, y)
                path.addQuadCurve(to: end, control: c)
                lastQuadControl = c
                lastCubicControl = nil
                current = end
            case "A":
                guard let rx = scanner.number(), let ry = scanner.number(), let rotation = scanner.number(),
                    let large = scanner.flag(), let sweep = scanner.flag(),
                    let x = scanner.number(), let y = scanner.number()
                else { return path }
                let end = point(x, y)
                addArc(
                    to: &path, from: current, to: end, rx: rx, ry: ry, rotation: rotation,
                    largeArc: large, sweep: sweep)
                current = end
                lastCubicControl = nil
                lastQuadControl = nil
            default:
                scanner.advance()  // unknown letter: skip it
                command = nil
            }
        }
        return path
    }

    private static func reflect(_ control: CGPoint?, about point: CGPoint) -> CGPoint {
        guard let control else { return point }
        return CGPoint(x: 2 * point.x - control.x, y: 2 * point.y - control.y)
    }

    /// SVG endpoint-to-centre parameterisation (SVG 1.1 implementation notes F.6.5), then cubic segments.
    private static func addArc(
        to path: inout Path, from p0: CGPoint, to p1: CGPoint, rx rxIn: CGFloat, ry ryIn: CGFloat,
        rotation: CGFloat, largeArc: Bool, sweep: Bool
    ) {
        var rx = abs(rxIn)
        var ry = abs(ryIn)
        if p0 == p1 { return }
        if rx == 0 || ry == 0 {
            path.addLine(to: p1)
            return
        }
        let phi = rotation * .pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)
        let dx = (p0.x - p1.x) / 2
        let dy = (p0.y - p1.y) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let s = lambda.squareRoot()
            rx *= s
            ry *= s
        }
        let numerator = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let denominator = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        guard denominator != 0 else {
            path.addLine(to: p1)
            return
        }
        var coefficient = (max(0, numerator) / denominator).squareRoot()
        if largeArc == sweep { coefficient = -coefficient }
        let cxp = coefficient * rx * y1p / ry
        let cyp = -coefficient * ry * x1p / rx
        let cx = cosPhi * cxp - sinPhi * cyp + (p0.x + p1.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (p0.y + p1.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        }
        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var delta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }

        let segments = max(1, Int((abs(delta) / (.pi / 2)).rounded(.up)))
        let step = delta / CGFloat(segments)
        let k = 4.0 / 3.0 * tan(step / 4)
        var t = theta1
        for _ in 0..<segments {
            let cosT1 = cos(t)
            let sinT1 = sin(t)
            let cosT2 = cos(t + step)
            let sinT2 = sin(t + step)
            func map(_ ux: CGFloat, _ uy: CGFloat) -> CGPoint {
                CGPoint(
                    x: cosPhi * rx * ux - sinPhi * ry * uy + cx,
                    y: sinPhi * rx * ux + cosPhi * ry * uy + cy)
            }
            path.addCurve(
                to: map(cosT2, sinT2),
                control1: map(cosT1 - k * sinT1, sinT1 + k * cosT1),
                control2: map(cosT2 + k * sinT2, sinT2 - k * cosT2))
            t += step
        }
    }

    /// A tiny cursor over the path string.
    private struct Scanner {
        let chars: [Unicode.Scalar]
        var index = 0

        init(_ chars: [Unicode.Scalar]) { self.chars = chars }

        var atEnd: Bool { index >= chars.count }

        mutating func advance() { index += 1 }

        mutating func skipSeparators() {
            while index < chars.count, chars[index] == "," || chars[index].properties.isWhitespace {
                index += 1
            }
        }

        func peekCommand() -> Character? {
            guard index < chars.count else { return nil }
            let c = Character(chars[index])
            return "MmLlHhVvCcSsQqTtAaZz".contains(c) || (c.isLetter && !"eE".contains(c)) ? c : nil
        }

        /// Reads a number; on failure skips one scalar so the caller cannot loop forever.
        mutating func number() -> CGFloat? {
            skipSeparators()
            let begin = index
            var i = index
            if i < chars.count, chars[i] == "+" || chars[i] == "-" { i += 1 }
            var digits = 0
            while i < chars.count, isDigit(chars[i]) {
                i += 1
                digits += 1
            }
            if i < chars.count, chars[i] == "." {
                i += 1
                while i < chars.count, isDigit(chars[i]) {
                    i += 1
                    digits += 1
                }
            }
            guard digits > 0 else {
                if index < chars.count, peekCommand() == nil { index += 1 }
                return nil
            }
            if i < chars.count, chars[i] == "e" || chars[i] == "E" {
                var j = i + 1
                if j < chars.count, chars[j] == "+" || chars[j] == "-" { j += 1 }
                var expDigits = 0
                while j < chars.count, isDigit(chars[j]) {
                    j += 1
                    expDigits += 1
                }
                if expDigits > 0 { i = j }
            }
            index = i
            let text = String(String.UnicodeScalarView(chars[begin..<i]))
            return Double(text).map { CGFloat($0) }
        }

        /// Arc flags are a single 0 or 1 and may be packed against the next number.
        mutating func flag() -> Bool? {
            skipSeparators()
            guard index < chars.count else { return nil }
            if chars[index] == "0" {
                index += 1
                return false
            }
            if chars[index] == "1" {
                index += 1
                return true
            }
            return nil
        }

        private func isDigit(_ s: Unicode.Scalar) -> Bool { s.value >= 48 && s.value <= 57 }
    }
}
