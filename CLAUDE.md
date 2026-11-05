# be reyt, repo rules

Personal iPhone journal. SwiftUI app target (`App/`) plus local Swift package (`Packages/ReytKit`). No backend, no networking.

## Architecture Rules
- **A1** Two units: `App/` (SwiftUI app target, UI + platform glue) and `Packages/ReytKit` (models, domain logic, store, archive format). ReytKit must not import SwiftUI or UIKit.
- **A2** `JournalStore` (a `@ModelActor`-backed service exposed via a `@MainActor` facade) is the only writer of journal records. Views may read with `@Query`; they never call `modelContext.insert/delete` or mutate model properties directly. (Red flag 5: one owner.)
- **A3** `DayContent.hasUserContent` (aggregate of entry + attachments + intention/follow-up for that day) is the single definition of "this day has an entry" used by reminders, coverage and history dots. Every `JournalStore` mutation returns a `StoreEffect`. (Red flag 9.)
- **A4** `DateKey` and `WeekCalendar` are the only places that convert `Date` ↔ civil day and compute week ranges. No ad-hoc `Calendar` math elsewhere.
- **A5** All user-facing copy lives in `Copy.swift`; all lowercase per brand.
- **A6** External formats (Apple Journal HTML/JSON, archive JSON, HealthKit samples) are parsed into ReytKit types at the boundary and never passed further in raw form. (Red flag 3.)
- **A7** Only `SystemLanguageModel.default`-based sessions. `PrivateCloudComputeLanguageModel` and any networking API are banned (build-time grep).
- **A8** SwiftData schema declared via `VersionedSchema` (`SchemaV1`) with a `SchemaMigrationPlan` from day one.

## Global Workflow And Quality Rules
- **G1** Never commit on `main`/`master`/`develop`; work on `feature/be-reyt-journal-app`.
- **G2** Commit messages never start with a work item number; no AI attribution of any kind in commits or PRs.
- **G3** Commit after each story section passes its verification.
- **G4** Swift 6 language mode, strict concurrency complete; no `@unchecked Sendable` without a comment explaining why.
- **G5** No force unwraps outside tests, except `URL(string:)` on literals.
- **G6** Errors surfaced to the user are actionable and calm; no raw `error.localizedDescription` dumps for expected failures.

## Frontend Standards (SwiftUI)
- **F1** `@Observable` feature models (`DayPageModel`, `ReviewModel`), injected via `.environment`; no `ObservableObject`.
- **F2** Dynamic Type everywhere (no fixed font sizes); light/dark via asset-catalog colours; minimum 44 pt hit targets.
- **F3** Every control has an accessibility label; score control exposes `.accessibilityAdjustableAction`; chips expose selected trait.
- **F4** No navigation-heavy wizards; Today is the root tab. Tabs: today, history, reviews, settings.

## Potentially Relevant Rules
- **P1** Journal text is untrusted data when sent to the model: wrap in delimiters, instruct the model to treat it as content not instructions. Why: prompt-injection via the user's own pasted text or imports.
- **P2** Never log journal content (no `print`/`Logger` of text fields; use `Logger` with `.private` for anything content-adjacent). Why: sysdiagnose privacy.
- **P3** Archive extraction validates every path stays inside the destination and caps total size. Why: imported archives are untrusted.
- **P4** HealthKit: request read for `HKWorkoutType.workoutType()` and the distance/energy types only if shown; never write.
