import Foundation
import FoundationModels
import ReytKit

/// Writes the reflection with Apple's on-device model and nothing else (A7): only `SystemLanguageModel.default`,
/// a fresh session per pass, no tools, no network, no other model. Journal text never leaves this phone.
struct OnDeviceReflectionGenerator: ReflectionGenerating {
    /// Overall limit for one attempt, digests included.
    static let timeout: Duration = .seconds(60)

    static var osBuild: String { ProcessInfo.processInfo.operatingSystemVersionString }

    func unavailability() async -> ReflectionFailure? {
        Self.unavailability(of: SystemLanguageModel.default)
    }

    static func unavailability(of model: SystemLanguageModel) -> ReflectionFailure? {
        switch model.availability {
        case .available:
            return model.supportsLocale() ? nil : .unsupportedLanguage
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return .deviceNotEligible
            case .appleIntelligenceNotEnabled: return .appleIntelligenceNotEnabled
            case .modelNotReady: return .modelNotReady
            @unknown default: return .modelError
            }
        }
    }

    func generate(input: ReflectionInput, facts: WeeklyStats, retryReasons: [String]) async throws
        -> WeeklyReflectionContent
    {
        #if DEBUG
            let started = ContinuousClock.now
            ReflectionLog.note("generate begin retry=\(!retryReasons.isEmpty)")
        #endif
        do {
            return try await withThrowingTaskGroup(of: WeeklyReflectionContent.self) { group in
                group.addTask { try await Self.write(input: input, facts: facts, retryReasons: retryReasons) }
                group.addTask {
                    try await Task.sleep(for: Self.timeout)
                    throw ReflectionFailure.timedOut
                }
                defer { group.cancelAll() }
                guard let first = try await group.next() else { throw ReflectionFailure.modelError }
                return first
            }
        } catch {
            #if DEBUG
                ReflectionLog.note(
                    "generate failed \(ReflectionLog.label(error)) after \(ContinuousClock.now - started)")
            #endif
            throw Self.map(error)
        }
    }

    // MARK: Passes

    private static func write(input: ReflectionInput, facts: WeeklyStats, retryReasons: [String]) async throws
        -> WeeklyReflectionContent
    {
        let model = SystemLanguageModel.default
        let counter: ContextBudget.TokenCounter = {
            let n = try await model.tokenCount(for: $0)
            #if DEBUG
                ReflectionLog.note("tokenCount chars=\($0.count) tokens=\(n)")
            #endif
            return n
        }
        #if DEBUG
            ReflectionLog.note("contextSize before warm-up = \(model.contextSize)")
        #endif
        let mainFixed =
            try await model.tokenCount(for: Instructions(ReflectionPrompt.instructions))
            + model.tokenCount(for: WeeklyReflection.generationSchema)
        let digestFixed =
            try await model.tokenCount(for: Instructions(ReflectionPrompt.digestInstructions))
            + model.tokenCount(for: DayDigest.generationSchema)

        // Read after the token counts above have loaded the model: before that, `contextSize` can report a smaller
        // number, which made a one-pass week look too long about half the time.
        let budget = ContextBudget(contextSize: model.contextSize, countTokens: counter)
        let single = ReflectionPrompt.singlePass(input: input, stats: facts, retryReasons: retryReasons)
        let plan = try await budget.plan(
            singlePassFixedTokens: mainFixed, singlePassPrompt: single, digestFixedTokens: digestFixed,
            composeFixedTokens: mainFixed + (try await counter(ReflectionPrompt.factsBlock(facts))),
            segments: ReflectionPrompt.segments(for: input))

        #if DEBUG
            let kind: String
            switch plan {
            case .singlePass: kind = "singlePass"
            case .tooLong: kind = "tooLong"
            case .digests(let parts): kind = "digests(\(parts.count))"
            }
            ReflectionLog.note(
                "plan ctx=\(model.contextSize) fixed=\(mainFixed) digestFixed=\(digestFixed) prompt=\(try await counter(single)) plan=\(kind)"
            )
        #endif
        switch plan {
        case .singlePass:
            return try await compose(prompt: single, model: model)
        case .tooLong:
            throw ReflectionFailure.tooLong
        case .digests(let parts):
            var digests: [DayDigest] = []
            for part in parts {
                try Task.checkCancellation()
                let session = LanguageModelSession(model: model, instructions: ReflectionPrompt.digestInstructions)
                let response = try await session.respond(
                    to: ReflectionPrompt.digestPrompt(part, weekStart: input.weekStart), generating: DayDigest.self)
                digests.append(response.content)
            }
            let composed = ReflectionPrompt.compose(
                parts: parts, digests: digests, stats: facts, weekStart: input.weekStart,
                retryReasons: retryReasons)
            guard try await budget.composeFits(fixedTokens: mainFixed, prompt: composed) else {
                throw ReflectionFailure.tooLong
            }
            return try await compose(prompt: composed, model: model)
        }
    }

    private static func compose(prompt: String, model: SystemLanguageModel) async throws -> WeeklyReflectionContent {
        let session = LanguageModelSession(model: model, instructions: ReflectionPrompt.instructions)
        let response = try await session.respond(to: prompt, generating: WeeklyReflection.self)
        return response.content.content
    }

    // MARK: Errors

    static func map(_ error: Error) -> ReflectionFailure {
        switch error {
        case let failure as ReflectionFailure:
            return failure
        case is CancellationError:
            return .cancelled
        case let e as LanguageModelError:
            switch e {
            case .contextSizeExceeded: return .tooLong
            case .rateLimited: return .rateLimited
            case .guardrailViolation: return .guardrail
            case .refusal: return .refused
            case .unsupportedLanguageOrLocale: return .unsupportedLanguage
            case .timeout: return .timedOut
            case .unsupportedCapability, .unsupportedTranscriptContent, .unsupportedGenerationGuide:
                return .modelError
            @unknown default: return .modelError
            }
        case let e as SystemLanguageModel.Error:
            switch e {
            case .assetsUnavailable: return .modelNotReady
            @unknown default: return .modelError
            }
        case let e as LanguageModelSession.Error:
            switch e {
            case .concurrentRequests, .transcriptMutationWhileResponding: return .busy
            @unknown default: return .modelError
            }
        case is GeneratedContent.ParsingError:
            return .unreadableAnswer
        default:
            return .modelError
        }
    }
}
