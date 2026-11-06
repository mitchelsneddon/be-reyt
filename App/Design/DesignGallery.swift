#if DEBUG
    import ReytKit
    import SwiftUI

    /// Debug-only visual check of every glyph and component. Launch with `-designGallery`, and
    /// `-galleryPage 1|2|3` to pick a page (default shows all).
    struct DesignGallery: View {
        private var page: Int {
            let args = CommandLine.arguments
            guard let i = args.firstIndex(of: "-galleryPage"), i + 1 < args.count else { return 0 }
            return Int(args[i + 1]) ?? 0
        }

        init() {
            assert(
                MoodCatalog.all.allSatisfy { MoodGlyph.hasGlyph($0.id) },
                "a mood id has no glyph")
        }

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if page == 0 || page == 1 { facesPage }
                    if page == 0 || page == 2 { moodsPage }
                    if page == 0 || page == 3 { componentsPage }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .background(Palette.paper)
            .tint(Palette.accent)
        }

        private func scoreColor(_ s: DayScore) -> Color {
            switch s {
            case .veryDifficult: Palette.score1
            case .difficult: Palette.score2
            case .okay: Palette.score3
            case .good: Palette.score4
            case .excellent: Palette.score5
            }
        }

        // MARK: faces

        private var facesPage: some View {
            VStack(alignment: .leading, spacing: 16) {
                SectionTitle("faces")
                ForEach([56.0, 38.0, 28.0], id: \.self) { circle in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("circle \(Int(circle)), selected").brFont(.label).foregroundStyle(Palette.ink2)
                        HStack(spacing: 8) {
                            ForEach(DayScore.allCases, id: \.self) { s in face(s, circle: circle, selected: true) }
                        }
                        Text("unselected").brFont(.label).foregroundStyle(Palette.ink2)
                        HStack(spacing: 8) {
                            ForEach(DayScore.allCases, id: \.self) { s in face(s, circle: circle, selected: false) }
                        }
                    }
                }
                Text("glyph only, stroke 2.6").brFont(.label).foregroundStyle(Palette.ink2)
                HStack(spacing: 12) {
                    ForEach(DayScore.allCases, id: \.self) { s in
                        ScoreGlyph(score: s, size: 56).foregroundStyle(Palette.ink)
                    }
                }
            }
        }

        private func face(_ s: DayScore, circle: CGFloat, selected: Bool) -> some View {
            let glyph: CGFloat = circle == 56 ? 34 : circle == 38 ? 25 : 19
            return ZStack {
                Circle().fill(selected ? scoreColor(s) : Palette.chip)
                ScoreGlyph(score: s, size: glyph, strokeUnits: circle == 56 ? 2.6 : 2.8)
                    .foregroundStyle(selected ? Palette.faceInk : Palette.ink3)
            }
            .frame(width: circle, height: circle)
            .padding(3)
            .overlay {
                if selected {
                    Circle().strokeBorder(scoreColor(s), lineWidth: 2)
                }
            }
        }

        // MARK: moods

        private var moodsPage: some View {
            VStack(alignment: .leading, spacing: 16) {
                SectionTitle("moods")
                let ids = MoodCatalog.all.map(\.id)
                Text("selected").brFont(.label).foregroundStyle(Palette.ink2)
                ScrollView(.horizontal) {
                    HStack(spacing: 6) { ForEach(ids, id: \.self) { moodTile($0, selected: true) } }
                }
                Text("unselected").brFont(.label).foregroundStyle(Palette.ink2)
                ScrollView(.horizontal) {
                    HStack(spacing: 6) { ForEach(ids, id: \.self) { moodTile($0, selected: false) } }
                }
                Text("large").brFont(.label).foregroundStyle(Palette.ink2)
                HStack(spacing: 8) {
                    ForEach(ids, id: \.self) {
                        MoodGlyph(id: $0, size: 44).foregroundStyle(Palette.ink)
                    }
                }
                SectionTitle("marks")
                HStack(spacing: 24) {
                    LockMark()
                    FolderLock()
                }
            }
        }

        private func moodTile(_ id: String, selected: Bool) -> some View {
            MoodGlyph(id: id, size: 26)
                .foregroundStyle(selected ? Palette.accent : Palette.ink2)
                .frame(width: 48, height: 48)
                .background(
                    selected ? Palette.accentSoft : Palette.chip,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .overlay {
                    if selected {
                        RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(
                            Palette.accent, lineWidth: 1.5)
                    }
                }
        }

        // MARK: components

        private var componentsPage: some View {
            VStack(alignment: .leading, spacing: 18) {
                SectionTitle("buttons")
                Button("primary") {}.buttonStyle(PrimaryButtonStyle())
                Button("primary disabled") {}.buttonStyle(PrimaryButtonStyle()).disabled(true)
                Button("secondary") {}.buttonStyle(SecondaryButtonStyle())
                Button("outline") {}.buttonStyle(OutlineButtonStyle())
                Button("destructive outline") {}.buttonStyle(DestructiveButtonStyle())
                Button("destructive filled") {}.buttonStyle(DestructiveButtonStyle(filled: true))

                SectionTitle("small parts")
                HStack(spacing: 16) {
                    Pill(text: "on this phone")
                    StatusDot(color: Palette.ok)
                    StatusDot(color: Palette.warn)
                    StatusDot(color: Palette.danger)
                    IconTile(systemName: "lock")
                    IconTile(systemName: "trash", style: .danger)
                    IconTile(glyph: MoodGlyph(id: "happy", size: 18))
                    ProgressRing()
                }
                VStack(spacing: 0) {
                    SettingsRowLabel(title: "reminder", icon: "bell", value: "9:00 pm", dot: Palette.ok)
                    Divider().overlay(Palette.border)
                    SettingsRowLabel(title: "backup folder", icon: "folder", value: "be reyt")
                    Divider().overlay(Palette.border)
                    SettingsRowLabel(title: "delete everything", icon: "trash", tint: .danger)
                }
                .padding(.horizontal, 16)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.border))

                Text("card surface").brFont(.body).foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardSurface()

                SectionTitle("banner")
                NoteBanner(icon: "checkmark.circle", text: "restored. 12 days are back.", dismiss: {})
                NoteBanner(
                    icon: "exclamationmark.circle",
                    text: "be reyt needs reinstalling from your mac in 3 days. your entries stay on your phone.",
                    tint: Palette.warn, dismiss: {})
            }
        }
    }
#endif
