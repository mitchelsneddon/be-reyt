import ReytKit
import SwiftUI
import UIKit

/// `UICalendarView` wrapped for SwiftUI: Gregorian, selectable from the earliest day through today, a small accent
/// dot on every day in `dotDays`. Selecting a day calls `onSelect`; the selection clears when no day is open.
struct HistoryCalendar: UIViewRepresentable {
    let dotDays: Set<DateKey>
    let earliest: DateKey
    let today: DateKey
    /// The day currently pushed from the calendar, if any.
    let openDay: DateKey?
    let onSelect: (DateKey) -> Void

    private static var gregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Calendar.current.timeZone
        calendar.locale = Calendar.current.locale
        calendar.firstWeekday = Calendar.current.firstWeekday
        return calendar
    }

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect, today: today) }

    func makeUIView(context: Context) -> UICalendarView {
        let view = UICalendarView()
        view.calendar = Self.gregorian
        view.delegate = context.coordinator
        view.tintColor = Palette.UI.accent
        view.fontDesign = .default
        view.accessibilityLabel = Copy.History.calendarLabel
        let selection = UICalendarSelectionSingleDate(delegate: context.coordinator)
        view.selectionBehavior = selection
        context.coordinator.selection = selection
        view.visibleDateComponents = DateComponents(calendar: Self.gregorian, year: today.year, month: today.month)
        view.setContentHuggingPriority(.required, for: .vertical)
        return view
    }

    func updateUIView(_ view: UICalendarView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onSelect = onSelect
        coordinator.today = today

        let calendar = Self.gregorian
        let start = min(earliest, today).date(in: calendar)
        let end = today.adding(days: 1).date(in: calendar).addingTimeInterval(-1)
        view.availableDateRange = DateInterval(start: start, end: end)

        let changed = coordinator.dots.symmetricDifference(dotDays)
        coordinator.dots = dotDays
        if !changed.isEmpty {
            view.reloadDecorations(
                forDateComponents: changed.map {
                    DateComponents(calendar: calendar, year: $0.year, month: $0.month, day: $0.day)
                }, animated: false)
        }
        if openDay == nil, coordinator.selection?.selectedDate != nil {
            coordinator.selection?.setSelected(nil, animated: false)
        }
    }

    @MainActor
    final class Coordinator: NSObject, UICalendarViewDelegate, UICalendarSelectionSingleDateDelegate {
        var onSelect: (DateKey) -> Void
        var today: DateKey
        var dots: Set<DateKey> = []
        var selection: UICalendarSelectionSingleDate?

        init(onSelect: @escaping (DateKey) -> Void, today: DateKey) {
            self.onSelect = onSelect
            self.today = today
        }

        private func key(_ c: DateComponents) -> DateKey? {
            guard let y = c.year, let m = c.month, let d = c.day else { return nil }
            return DateKey(year: y, month: m, day: d)
        }

        func calendarView(_ calendarView: UICalendarView, decorationFor dateComponents: DateComponents)
            -> UICalendarView.Decoration?
        {
            guard let key = key(dateComponents), dots.contains(key) else { return nil }
            // A custom view rather than the stock dot so the dot can carry a spoken label.
            return .customView {
                let dot = UIView(frame: CGRect(x: 0, y: 0, width: 8, height: 8))
                dot.backgroundColor = Palette.UI.accent
                dot.layer.cornerRadius = 4
                dot.isAccessibilityElement = true
                dot.accessibilityLabel = Copy.History.hasEntry
                return dot
            }
        }

        func dateSelection(_ selection: UICalendarSelectionSingleDate, canSelectDate dateComponents: DateComponents?)
            -> Bool
        {
            guard let c = dateComponents, let key = key(c) else { return false }
            return key <= today
        }

        func dateSelection(
            _ selection: UICalendarSelectionSingleDate, didSelectDate dateComponents: DateComponents?
        ) {
            guard let c = dateComponents, let key = key(c), key <= today else { return }
            onSelect(key)
        }
    }
}
