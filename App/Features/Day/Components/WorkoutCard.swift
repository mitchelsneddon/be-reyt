import ReytKit
import SwiftData
import SwiftUI

/// The day's workouts as quiet cards after the photo strip. Nothing at all on a day without workouts, and
/// workouts never make a day count as having an entry. Duplicates from several sources show once.
struct WorkoutSection: View {
    @Query private var records: [WorkoutSnapshot]

    init(dateKey: DateKey) {
        let key = dateKey.string
        _records = Query(
            filter: #Predicate<WorkoutSnapshot> { $0.dateKey == key },
            sort: [SortDescriptor(\WorkoutSnapshot.start), SortDescriptor(\WorkoutSnapshot.healthKitUUID)])
    }

    private var groups: [WorkoutGroup] { WorkoutDedupe.collapse(records.map(WorkoutSnapshotValue.init)) }

    var body: some View {
        let groups = groups
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(Copy.Workouts.activitiesTitle)
                VStack(spacing: 10) {
                    ForEach(groups) { WorkoutCard(group: $0) }
                }
            }
        }
    }
}

struct WorkoutCard: View {
    let group: WorkoutGroup

    private var workout: WorkoutSnapshotValue { group.representative }
    private var activity: WorkoutActivity { WorkoutActivity(id: workout.activityType) }
    private var duration: String { Copy.Workouts.duration(seconds: workout.durationSeconds) }
    private var distance: String? {
        guard let meters = workout.distanceMeters, meters > 0 else { return nil }
        return Copy.Workouts.distance(meters: meters, swimming: activity == .swimming)
    }

    @ScaledMetric(relativeTo: .body) private var tileSide: CGFloat = 42
    @ScaledMetric(relativeTo: .body) private var glyphSide: CGFloat = 22
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var expanded = false
    @State private var detail: WorkoutDetail?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if reduceMotion { expanded.toggle() } else { withAnimation(.snappy) { expanded.toggle() } }
            } label: {
                summary
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                Copy.Workouts.cardLabel(name: activity.displayName, duration: duration, distance: distance)
            )
            .accessibilityValue(expanded ? Copy.Workouts.expanded : Copy.Workouts.collapsed)
            .accessibilityHint(expanded ? Copy.Workouts.hideDetailsHint : Copy.Workouts.showDetailsHint)
            if expanded {
                WorkoutDetails(group: group, activity: activity, detail: detail)
                    .padding(.top, 14)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 2)
        .cardSurface(padding: 14)
        .task(id: expanded) {
            guard expanded, detail == nil else { return }
            detail = await WorkoutDetailReader.shared.detail(for: group.members.map(\.healthKitUUID))
        }
    }

    private var summary: some View {
        HStack(spacing: 14) {
            Image(systemName: Self.symbol(for: activity))
                .resizable().scaledToFit()
                .frame(width: min(glyphSide, 34), height: min(glyphSide, 34))
                .foregroundStyle(Palette.accent)
                .frame(width: min(tileSide, 64), height: min(tileSide, 64))
                .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.displayName).brFont(.cardTitle).foregroundStyle(Palette.ink)
                Text([Optional(duration), distance].compactMap { $0 }.joined(separator: " · "))
                    .brFont(.label).foregroundStyle(Palette.ink2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(Copy.Workouts.startTime(workout.start))
                .brFont(.captionItalic).foregroundStyle(Palette.ink2)
            Image(systemName: "chevron.down")
                .symbolSize(14)
                .foregroundStyle(Palette.ink3)
                .rotationEffect(.degrees(expanded ? 180 : 0))
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    static func symbol(for activity: WorkoutActivity) -> String {
        switch activity {
        case .running: "figure.run"
        case .walking: "figure.walk"
        case .hiking: "figure.hiking"
        case .cycling: "figure.outdoor.cycle"
        case .swimming: "figure.pool.swim"
        case .strength: "figure.strengthtraining.traditional"
        case .yoga: "figure.yoga"
        case .pilates: "figure.pilates"
        case .rowing: "figure.rower"
        case .elliptical: "figure.elliptical"
        case .hiit: "figure.highintensity.intervaltraining"
        case .dance: "figure.dance"
        case .other: "figure.mixed.cardio"
        }
    }
}

/// The expanded part of an activity card: a route drawing when Health has one, then the numbers.
private struct WorkoutDetails: View {
    let group: WorkoutGroup
    let activity: WorkoutActivity
    /// Nil while Health is being read.
    let detail: WorkoutDetail?

    private var workout: WorkoutSnapshotValue { group.representative }

    private var rows: [(label: String, value: String)] {
        var rows: [(String, String)] = [
            (Copy.Workouts.timeLabel, Copy.Workouts.timeRange(workout.start, workout.end)),
            (Copy.Workouts.durationLabel, Copy.Workouts.duration(seconds: workout.durationSeconds)),
        ]
        if let meters = workout.distanceMeters, meters > 0 {
            let swimming = activity == .swimming
            rows.append((Copy.Workouts.distanceLabel, Copy.Workouts.distance(meters: meters, swimming: swimming)))
            if activity == .cycling {
                if let speed = Copy.Workouts.speed(seconds: workout.durationSeconds, meters: meters) {
                    rows.append((Copy.Workouts.speedLabel, speed))
                }
            } else if let pace = Copy.Workouts.pace(
                seconds: workout.durationSeconds, meters: meters, swimming: swimming)
            {
                rows.append((Copy.Workouts.paceLabel, pace))
            }
        }
        if let kcal = group.members.compactMap(\.energyKcal).first, kcal > 0 {
            rows.append((Copy.Workouts.caloriesLabel, Copy.Workouts.calories(kcal)))
        }
        if let gain = detail?.elevationGainMeters {
            rows.append((Copy.Workouts.elevationLabel, Copy.Workouts.elevation(meters: gain)))
        }
        var sources: [String] = []
        for name in group.members.map(\.sourceName) where !name.isEmpty && !sources.contains(name) {
            sources.append(name)
        }
        if !sources.isEmpty { rows.append((Copy.Workouts.sourceLabel, sources.joined(separator: ", "))) }
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let route = detail?.route, route.count > 1 {
                RouteDrawing(points: route)
                    .frame(height: 180)
                    .accessibilityElement()
                    .accessibilityLabel(Copy.Workouts.routeAccessibility(activity.displayName))
            } else if detail == nil {
                ProgressRing(size: 18, lineWidth: 2)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityHidden(true)
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                ForEach(rows, id: \.label) { row in
                    GridRow {
                        Text(row.label).brFont(.label).foregroundStyle(Palette.ink2)
                        Text(row.value).brFont(.row).foregroundStyle(Palette.ink)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// The route as a line on paper: no map tiles, so nothing is fetched from the network (A7). Start is a hollow
/// dot, finish a filled one.
private struct RouteDrawing: View {
    let points: [WorkoutDetail.Point]

    var body: some View {
        GeometryReader { geo in
            let projected = RouteProjection.fit(points, in: geo.size.insetBy(18))
            ZStack(alignment: .topLeading) {
                Path { path in path.addLines(projected) }
                    .stroke(Palette.accent, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                if let first = projected.first {
                    Circle().stroke(Palette.accent, lineWidth: 2.5).background(Circle().fill(Palette.paper))
                        .frame(width: 11, height: 11).position(first)
                }
                if let last = projected.last {
                    Circle().fill(Palette.accent).frame(width: 11, height: 11).position(last)
                }
            }
            .offset(x: 18, y: 18)
        }
        .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

/// Flattens latitude/longitude onto a plane (fine at the scale of one workout) and fits it, centred and
/// aspect-preserved, into `size`.
enum RouteProjection {
    static func fit(_ points: [WorkoutDetail.Point], in size: CGSize) -> [CGPoint] {
        guard let first = points.first, size.width > 0, size.height > 0 else { return [] }
        let scaleX = cos(first.latitude * .pi / 180)
        let raw = points.map { CGPoint(x: $0.longitude * scaleX, y: -$0.latitude) }
        let minX = raw.map(\.x).min() ?? 0
        let maxX = raw.map(\.x).max() ?? 0
        let minY = raw.map(\.y).min() ?? 0
        let maxY = raw.map(\.y).max() ?? 0
        let spanX = max(maxX - minX, 1e-9)
        let spanY = max(maxY - minY, 1e-9)
        let scale = min(size.width / spanX, size.height / spanY)
        let offsetX = (size.width - spanX * scale) / 2
        let offsetY = (size.height - spanY * scale) / 2
        return raw.map { CGPoint(x: ($0.x - minX) * scale + offsetX, y: ($0.y - minY) * scale + offsetY) }
    }
}

extension CGSize {
    fileprivate func insetBy(_ inset: CGFloat) -> CGSize {
        CGSize(width: max(width - inset * 2, 0), height: max(height - inset * 2, 0))
    }
}
