import ReytKit
import SwiftUI

/// One day's page: heading, score, moods, editor. Reflections, workouts and visual reminders slot in below.
struct DayPageView: View {
    let model: DayPageModel
    let photos: PhotosModel
    /// The latest civil day; the next-day arrow stops here (no future days).
    let today: DateKey
    /// Jumps the pager to another day (the plan card's "edit plan" opens its Sunday).
    let onOpenDay: (DateKey) -> Void

    static let reflectionsAnchor = "reflections"
    static let planAnchor = "plan"
    static let photosAnchor = "photos"
    static let editorEndAnchor = "editorEnd"
    static let smileEndAnchor = "smileEnd"

    @Environment(\.scenePhase) private var scenePhase
    @Environment(HealthCoordinator.self) private var health
    @FocusState private var editorFocused: Bool
    @State private var smileFocused = false
    /// Top of the keyboard on screen, `.infinity` while hidden (see `KeepAboveKeyboard`).
    @State private var keyboardTop: CGFloat = .infinity

    var body: some View {
        ScrollViewReader { proxy in
            page(proxy)
                .task(id: model.isLoaded) { await scrollToReflectionsIfRequested(proxy) }
        }
    }

    private func scrollToReflectionsIfRequested(_ proxy: ScrollViewProxy) async {
        #if DEBUG
            // Simulator-only: `-scrollToReflections` brings the reflection cards into view for screenshots.
            // `-scrollToPlan` brings the follow-up and Sunday plan cards into view instead.
            let args = CommandLine.arguments
            guard
                args.contains("-scrollToReflections") || args.contains("-scrollToPlan")
                    || args.contains("-scrollToPhotos"),
                model.isLoaded
            else { return }
            try? await Task.sleep(for: .milliseconds(400))
            let anchor =
                args.contains("-scrollToPhotos")
                ? Self.photosAnchor : args.contains("-scrollToPlan") ? Self.planAnchor : Self.reflectionsAnchor
            proxy.scrollTo(anchor, anchor: .top)
        #endif
    }

    private func page(_ proxy: ScrollViewProxy) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if model.loadFailed {
                    Button {
                        Task { await model.load() }
                    } label: {
                        VStack(spacing: 12) {
                            SymbolGlyph(systemName: "arrow.clockwise").foregroundStyle(Palette.accent)
                            Text(Copy.Day.loadFailed)
                                .brFont(.body)
                                .foregroundStyle(Palette.ink2)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: 300, minHeight: 44)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 48)
                    .accessibilityLabel(Copy.Day.loadFailed)
                } else {
                    if let plan = model.coveringPlan {
                        PlanThisWeekCard(plan: plan, today: today, onOpenSunday: onOpenDay)
                    }
                    DayScoreControl(score: model.score, onChange: model.setScore)
                    MoodTileGrid(
                        selected: model.moodIDs, loadedIDs: model.loadedMoodIDs, onToggle: model.toggleMood)
                    editor(proxy)
                    reflections(proxy)
                    planLifecycle
                    WorkoutSection(dateKey: model.dateKey)
                    PhotoStrip(model: photos).id(DayPageView.photosAnchor)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .trackingKeyboardTop($keyboardTop)
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.paper)
        .environment(model)
        // Keyed by model: a pager page that is handed a fresh model (after the cache pruned its day) loads it.
        .task(id: ObjectIdentifier(model)) { await model.load() }
        .task { await health.syncIfDue() }
        .onChange(of: editorFocused) { _, focused in model.setFocus(.editor, focused) }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.flush() } }
        .onChange(of: model.contentRevision) { _, _ in Task { await model.reloadClean() } }
        .onDisappear { model.flush() }
    }

    @ViewBuilder private var planLifecycle: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let plan = model.followUpPlan { FollowUpCard(plan: plan) }
            if model.isSunday { SundayPlanSection() }
        }
        .id(DayPageView.planAnchor)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Copy.Day.eyebrow(for: model.dateKey)).brFont(.eyebrow).foregroundStyle(Palette.ink2)
            Text(Copy.Day.dateTitle(for: model.dateKey)).brFont(.largeTitle).foregroundStyle(Palette.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.Day.headerLabel(for: model.dateKey))
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private func reflections(_ proxy: ScrollViewProxy) -> some View {
        ReflectionCard(
            question: Copy.Reflection.smileQuestion,
            answerLabel: Copy.Reflection.smileAnswerLabel,
            answer: Binding(get: { model.smileAnswer }, set: { model.setSmileAnswer($0) }),
            isEnabled: model.isLoaded,
            onFocusChange: {
                smileFocused = $0
                model.setFocus(.smile, $0)
            },
            placeholder: Copy.Reflection.smilePlaceholder, plainHeading: true
        )
        .modifier(
            KeepAboveKeyboard(
                anchorID: Self.smileEndAnchor, text: model.smileAnswer, isFocused: smileFocused,
                keyboardTop: keyboardTop, proxy: proxy)
        )
        .id(DayPageView.reflectionsAnchor)
        if model.showsRotatingPrompt, let prompt = model.prompt {
            ReflectionCard(
                question: prompt.text,
                answerLabel: Copy.Reflection.promptAnswerLabel(prompt.text),
                answer: Binding(get: { model.rotatingAnswer }, set: { model.setRotatingAnswer($0) }),
                isEnabled: model.isLoaded, onFocusChange: { model.setFocus(.rotating, $0) })
        }
    }

    private func editor(_ proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(Copy.Day.entryTitle)
            TextField("", text: Binding(get: { model.text }, set: { model.setText($0) }), axis: .vertical)
                .brFont(.body)
                .foregroundStyle(Palette.ink)
                .lineLimit(3...)
                .focused($editorFocused)
                .disabled(!model.isLoaded)
                .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
                .brPlaceholder(Copy.Day.editorPlaceholder, show: model.text.isEmpty)
                .accessibilityLabel(Copy.Day.editorLabel)
                .modifier(
                    KeepAboveKeyboard(
                        anchorID: Self.editorEndAnchor, text: model.text, isFocused: editorFocused,
                        keyboardTop: keyboardTop, proxy: proxy))
        }
    }
}

struct SavedIndicator: View {
    let state: DayPageModel.SaveState
    let retry: () -> Void

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .saving:
            ProgressRing(size: 18, lineWidth: 2)
                .frame(width: 30, height: 44)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(Copy.Save.indicatorLabel), \(Copy.Save.saving)")
        case .saved:
            SymbolGlyph(systemName: "checkmark.circle")
                .foregroundStyle(Palette.ink2)
                .frame(width: 30, height: 44)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(Copy.Save.indicatorLabel), \(Copy.Save.saved)")
        case .failed:
            Button(action: retry) {
                HStack(spacing: 5) {
                    SymbolGlyph(systemName: "exclamationmark.arrow.circlepath")
                    Text(Copy.Save.failed).brFont(.label)
                }
                .foregroundStyle(Palette.danger)
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Copy.Save.failed)
            .accessibilityHint(Copy.Save.retryHint)
        }
    }
}
