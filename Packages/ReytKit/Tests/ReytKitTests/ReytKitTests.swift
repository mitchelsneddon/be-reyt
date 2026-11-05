import Testing

@testable import ReytKit

@Test("tagline is the lowercase brand line")
func tagline() {
    #expect(ReytKit.tagline == "a little space for your day.")
}
