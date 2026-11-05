import ReytKit
import SwiftUI

/// One day's page: heading, score, moods, tags, editor. Reflections, photos and workouts slot in below the editor.
struct DayPageView: View {
    let model: DayPageModel
    let photos: PhotosModel
    /// The latest civil day; the next-day arrow stops here (no future days).
    let today: DateKey
    let onNavigate: (DateKey) -> Void

    static let reflectionsAnchor = "reflections"
    static let planAnchor = "plan"
    static let photosAnchor = "photos"

    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var editorFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            page
                .task(id: model.prompt?.id) { await scrollToReflectionsIfRequested(proxy) }
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
                model.prompt != nil
            else { return }
            try? await Task.sleep(for: .milliseconds(400))
            let anchor =
                args.contains("-scrollToPhotos")
                ? Self.photosAnchor : args.contains("-scrollToPlan") ? Self.planAnchor : Self.reflectionsAnchor
            proxy.scrollTo(anchor, anchor: .top)
        #endif
    }

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(Copy.Day.heading(for: model.dateKey))
                    .font(.system(.largeTitle, design: .serif))
                    .foregroundStyle(Color("ink"))
                    .accessibilityAddTraits(.isHeader)

                if model.loadFailed {
                    Button(Copy.Day.loadFailed) { Task { await model.load() } }
                        .font(.footnote)
                        .foregroundStyle(Color("accent"))
                        .frame(minHeight: 44)
                } else {
                    if let plan = model.coveringPlan {
                        PlanThisWeekCard(plan: plan, today: today, onOpenSunday: go)
                    }
                    DayScoreControl(score: model.score, onChange: model.setScore)
                    moods
                    TagEditor()
                    editor
                    reflections
                    planLifecycle
                    PhotoStrip(model: photos).id(DayPageView.photosAnchor)
                    // INSERT S9: workout cards go here.
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color("paper"))
        .environment(model)
        .task { await model.load() }
        .onChange(of: editorFocused) { _, focused in model.isEditorFocused = focused }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.flush() } }
        .onDisappear { model.flush() }
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                Button {
                    go(model.dateKey.adding(days: -1))
                } label: {
                    Image(systemName: "chevron.left").frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel(Copy.Day.previousDay)
                Button {
                    go(model.dateKey.adding(days: 1))
                } label: {
                    Image(systemName: "chevron.right").frame(minWidth: 44, minHeight: 44)
                }
                .disabled(model.dateKey >= today)
                .accessibilityLabel(Copy.Day.nextDay)
            }
            ToolbarItem(placement: .topBarTrailing) {
                SavedIndicator(state: model.saveState, retry: model.retry)
            }
        }
    }

    @ViewBuilder private var planLifecycle: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let plan = model.followUpPlan { FollowUpCard(plan: plan) }
            if model.isSunday { SundayPlanSection() }
        }
        .id(DayPageView.planAnchor)
    }

    private func go(_ key: DateKey) {
        model.flush()
        onNavigate(key)
    }

    private var moods: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Copy.Day.moodsTitle).font(.footnote).foregroundStyle(Color("inkSecondary"))
            ChipGroup(
                items: MoodCatalog.all.map { ChipItem(id: $0.id, label: $0.label) },
                selection: Binding(get: { Set(model.moodIDs) }, set: { _ in }),
                onToggle: { model.toggleMood($0) })
        }
    }

    @ViewBuilder private var reflections: some View {
        ReflectionCard(
            question: Copy.Reflection.smileQuestion, helper: Copy.Reflection.smileHelper,
            answerLabel: Copy.Reflection.smileAnswerLabel,
            answer: Binding(get: { model.smileAnswer }, set: { model.setSmileAnswer($0) }),
            isEnabled: model.isLoaded
        )
        .id(DayPageView.reflectionsAnchor)
        if let prompt = model.prompt {
            ReflectionCard(
                question: prompt.text, helper: Copy.Reflection.promptHelper,
                answerLabel: Copy.Reflection.promptAnswerLabel(prompt.text),
                answer: Binding(get: { model.rotatingAnswer }, set: { model.setRotatingAnswer($0) }),
                isEnabled: model.isLoaded
            ) {
                if model.canRerollPrompt {
                    Button(Copy.Reflection.anotherPrompt) { Task { await model.rerollPrompt() } }
                        .font(.footnote)
                        .foregroundStyle(Color("accent"))
                        .frame(minHeight: 44)
                        .accessibilityHint(Copy.Reflection.anotherPromptHint)
                }
            }
        }
    }

    private var editor: some View {
        TextField(
            Copy.Day.editorPlaceholder,
            text: Binding(get: { model.text }, set: { model.setText($0) }),
            axis: .vertical
        )
        .font(.body)
        .foregroundStyle(Color("ink"))
        .lineLimit(8...)
        .focused($editorFocused)
        .disabled(!model.isLoaded)
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color("card")))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color("hairline"), lineWidth: 1))
        .accessibilityLabel(Copy.Day.editorLabel)
    }
}

private struct SavedIndicator: View {
    let state: DayPageModel.SaveState
    let retry: () -> Void

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .saving:
            label(Copy.Save.saving)
        case .saved:
            label(Copy.Save.saved)
        case .failed:
            Button(action: retry) {
                Text(Copy.Save.failed).font(.footnote).foregroundStyle(Color("accent")).frame(minHeight: 44)
            }
            .accessibilityHint(Copy.Save.retryHint)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundStyle(Color("inkSecondary"))
            .accessibilityLabel("\(Copy.Save.indicatorLabel), \(text)")
    }
}
