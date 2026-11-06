import ReytKit
import SwiftUI

/// The written reflection in a review. Always started by the reader. Every state keeps the rest of the review
/// visible, so a failure never hides the numbers.
struct ReflectionSection: View {
    let model: ReflectionModel

    var body: some View {
        if model.state != .loading {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(Copy.WeekReflection.title)
                card
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.default, value: model.state)
        }
    }

    @ViewBuilder private var card: some View {
        switch model.state {
        case .loading:
            EmptyView()
        case .notGenerated:
            simpleCard { writeButton(prominent: true) }
        case .generating:
            simpleCard { generating }
        case .ready(let content, let newer):
            ready(content, newerPromptAvailable: newer)
        case .unavailable(let reason):
            simpleCard {
                note(Copy.WeekReflection.failure(reason), icon: .phoneStrike)
                tryAgainButton
            }
        case .failed(let reason):
            simpleCard {
                note(Copy.WeekReflection.failure(reason), icon: .retry)
                if reason != .noEntries { writeButton(prominent: false) }
            }
        case .purged:
            simpleCard {
                note(Copy.WeekReflection.purged, icon: .pencil)
                writeButton(prominent: true)
            }
        }
    }

    private func simpleCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(padding: 20)
    }

    // MARK: States

    private var generating: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                ProgressRing(size: 20, lineWidth: 2.4)
                Text(Copy.WeekReflection.generating).brFont(.rowWrapping).foregroundStyle(Palette.ink2)
            }
            VStack(spacing: 12) {
                SkeletonLine(fraction: 1)
                SkeletonLine(fraction: 0.92)
                SkeletonLine(fraction: 0.64)
            }
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.WeekReflection.generating)
    }

    private func note(_ text: String, icon: ReflectionIcon.Kind) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ReflectionTile(icon: icon)
            Text(text).brFont(.point).foregroundStyle(Palette.ink)
                .padding(.top, 5)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var tryAgainButton: some View {
        Button(Copy.WeekReflection.tryAgain) { Task { await model.recheck() } }
            .buttonStyle(.brOutline)
    }

    @ViewBuilder private func writeButton(prominent: Bool) -> some View {
        let button = Button {
            Task { await model.generate() }
        } label: {
            HStack(spacing: 8) {
                if prominent { ReflectionIcon(kind: .phoneSparkle, size: 20) }
                Text(Copy.WeekReflection.write)
            }
        }
        .accessibilityHint(Copy.WeekReflection.writeHint)
        if prominent {
            button.buttonStyle(ReflectionPrimaryButtonStyle())
        } else {
            button.buttonStyle(.brOutline)
        }
    }

    // MARK: Ready

    private func ready(_ content: WeeklyReflectionContent, newerPromptAvailable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(content.overview)
                .brFont(.body).foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            points(title: Copy.WeekReflection.highlights, content.highlights)
            points(title: Copy.WeekReflection.difficult, content.difficult)
            if !content.themes.isEmpty {
                subsection(Copy.WeekReflection.themes) {
                    ForEach(Array(content.themes.enumerated()), id: \.offset) { _, theme in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(theme.title).brFont(.navTitle).foregroundStyle(Palette.ink)
                            Text(theme.summary).brFont(.point).foregroundStyle(Palette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            DayPills(dates: theme.dateKeys)
                        }
                    }
                }
            }
            if !content.questions.isEmpty {
                subsection(Copy.WeekReflection.questions) {
                    ForEach(Array(content.questions.enumerated()), id: \.offset) { _, q in
                        Text(q).brFont(.bodyItalicTight).foregroundStyle(Palette.accentText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            footer
            if newerPromptAvailable {
                Button(Copy.WeekReflection.regenerate) { Task { await model.generate() } }
                    .buttonStyle(.brOutline)
                    .accessibilityHint(Copy.WeekReflection.regenerateHint)
                    .padding(.top, 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 20, leading: 20, bottom: 16, trailing: 20))
        .cardSurface(padding: 0)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            ReflectionIcon(kind: .phone, size: 16)
            Text(Copy.WeekReflection.footnote)
        }
        .brFont(.label)
        .foregroundStyle(Palette.ink2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 14)
        .overlay(alignment: .top) { Rectangle().fill(Palette.border).frame(height: 1) }
        .padding(.top, 20)
    }

    private func subsection<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).brFont(.subhead).foregroundStyle(Palette.ink2)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 2)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 22)
    }

    @ViewBuilder private func points(title: String, _ points: [WeeklyReflectionContent.Point]) -> some View {
        if !points.isEmpty {
            subsection(title) {
                ForEach(Array(points.enumerated()), id: \.offset) { _, p in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(p.text).brFont(.point).foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        DayPills(dates: p.dateKeys)
                    }
                }
            }
        }
    }
}

/// Small tappable weekday pills under a point or theme, each opening that day's page. The pill is the visible
/// shape, the hit area is 44pt high.
private struct DayPills: View {
    let dates: [DateKey]

    var body: some View {
        if !dates.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(dates, id: \.self) { key in
                    NavigationLink(value: ReviewRoute.day(key)) {
                        Text(Copy.Reviews.weekdayShort[key.weekday])
                            .brFont(.pill)
                            .foregroundStyle(Palette.accentText)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 10)
                            .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(Copy.History.rowDate(key))
                    .accessibilityHint(Copy.Reviews.openDayHint)
                }
            }
            .padding(.top, -4)
            .padding(.bottom, -6)
        }
    }
}

private struct SkeletonLine: View {
    let fraction: CGFloat

    var body: some View {
        Color.clear.frame(height: 12)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Palette.chip)
                        .frame(width: proxy.size.width * fraction)
                }
            }
    }
}

/// 50 high, radius 14, accent fill: the reflection card's call to action.
private struct ReflectionPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brFont(.navTitle)
            .foregroundStyle(Palette.onAccent)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Palette.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

private struct ReflectionTile: View {
    let icon: ReflectionIcon.Kind
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 34

    var body: some View {
        ReflectionIcon(kind: icon, size: 18)
            .foregroundStyle(Palette.ink2)
            .frame(width: min(side, 52), height: min(side, 52))
            .background(Palette.chip, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// The small stroked icons of the reflection card (viewBox 24).
private struct ReflectionIcon: View {
    enum Kind {
        case phone, phoneSparkle, phoneStrike, retry, pencil

        var paths: [String] {
            let body =
                "M9 2.5h6A2.5 2.5 0 0 1 17.5 5v14a2.5 2.5 0 0 1-2.5 2.5H9A2.5 2.5 0 0 1 6.5 19V5A2.5 2.5 0 0 1 9 2.5z"
            switch self {
            case .phone: return [body, "M10.5 18.5h3"]
            case .phoneSparkle: return [body, "M12 8.5l.9 2.1 2.1.9-2.1.9-.9 2.1-.9-2.1-2.1-.9 2.1-.9z"]
            case .phoneStrike: return [body, "M3 3l18 18"]
            case .retry: return ["M20 12a8 8 0 1 1-2.3-5.6", "M20 4v5h-5"]
            case .pencil: return ["M4 20h4L19 9l-4-4L4 16z", "M13.5 6.5l4 4"]
            }
        }
    }

    let kind: Kind
    let size: CGFloat
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        let side = size * min(scale, 1.6)
        let style = StrokeStyle(lineWidth: 1.9 / 24 * side, lineCap: .round, lineJoin: .round)
        ZStack {
            ForEach(kind.paths, id: \.self) { d in
                SVGPathShape(d, viewBox: 24).stroke(.foreground, style: style)
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}
