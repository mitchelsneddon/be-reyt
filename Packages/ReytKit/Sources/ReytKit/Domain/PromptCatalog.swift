import Foundation

/// The curated rotating reflection prompts. IDs are stable forever (they are stored with assignments and
/// archived); wording may change in an app update, but a stored assignment keeps the wording it was given.
/// Voice: ordinary self-recognition, gentle, nothing that assumes the day went well.
public enum PromptCatalog {
    public static let all: [PromptChoice] = [
        PromptChoice(id: "handled-well", text: "what’s one thing you handled well today?"),
        PromptChoice(id: "appreciated", text: "who or what did you appreciate today?"),
        PromptChoice(id: "give-credit", text: "what would you like to give yourself credit for?"),
        PromptChoice(id: "looking-forward", text: "what are you looking forward to?"),
        PromptChoice(id: "got-through", text: "what helped you get through today?"),
        PromptChoice(id: "noticed", text: "what did you notice today?"),
        PromptChoice(id: "stayed-with-you", text: "what stayed with you from today?"),
        PromptChoice(id: "felt-ordinary", text: "what felt ordinary today, in a good or neutral way?"),
        PromptChoice(id: "needed-today", text: "what did you need today?"),
        PromptChoice(id: "was-hard", text: "what was hard today, and how did you meet it?"),
        PromptChoice(id: "small-kindness", text: "was there a small kindness, given or received?"),
        PromptChoice(id: "took-care", text: "how did you look after yourself today?"),
        PromptChoice(id: "let-go", text: "is there anything you could let go of tonight?"),
        PromptChoice(id: "carried", text: "what have you been carrying lately?"),
        PromptChoice(id: "surprised", text: "did anything surprise you today?"),
        PromptChoice(id: "learned", text: "what did you learn today, even a little thing?"),
        PromptChoice(id: "energy", text: "what gave you energy, and what took it?"),
        PromptChoice(id: "pace", text: "how was the pace of today for you?"),
        PromptChoice(id: "body", text: "how did your body feel today?"),
        PromptChoice(id: "tomorrow-easier", text: "what might make tomorrow a little easier?"),
        PromptChoice(id: "conversation", text: "was there a conversation worth remembering?"),
        PromptChoice(id: "showed-up", text: "where did you show up today, even imperfectly?"),
        PromptChoice(id: "said-no", text: "was there something you said no to, or wish you had?"),
        PromptChoice(id: "moment-quiet", text: "when did you have a moment to yourself?"),
        PromptChoice(id: "comfort", text: "what felt comforting today?"),
        PromptChoice(id: "unfinished", text: "what’s still unfinished, and is that okay for now?"),
        PromptChoice(id: "proud-small", text: "what’s something small you got done?"),
        PromptChoice(id: "different", text: "what would you do differently, if anything?"),
        PromptChoice(id: "one-word", text: "what’s one word for how today felt?"),
        PromptChoice(id: "grateful-plain", text: "what’s something you’re glad to have, just as it is?"),
        PromptChoice(id: "patience", text: "where did you find some patience today?"),
        PromptChoice(id: "time-for", text: "what did you make time for today?"),
        PromptChoice(id: "rest", text: "when did you get to rest, or when did you wish you could?"),
        PromptChoice(id: "people", text: "who was on your mind today?"),
        PromptChoice(id: "place", text: "where did you spend most of your day, and how was it?"),
        PromptChoice(id: "wish-known", text: "what do you wish someone knew about today?"),
    ]
}
