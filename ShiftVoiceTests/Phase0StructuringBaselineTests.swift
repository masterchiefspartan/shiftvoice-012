import Foundation
import Testing
@testable import ShiftVoice

struct Phase0StructuringBaselineTests {
    
    @Test func structuringValidatorHappyPathFixture() {
        let transcript = "Fryer in line 2 is down and we are out of oat milk at the espresso bar. Please call maintenance and restock before opening."
        let items = [
            CategorizedItem(
                category: .equipment,
                content: "Fryer in line 2 is down",
                urgency: .immediate,
                sourceQuote: "Fryer in line 2 is down"
            ),
            CategorizedItem(
                category: .inventory,
                content: "Out of oat milk at the espresso bar",
                urgency: .nextShift,
                sourceQuote: "we are out of oat milk at the espresso bar"
            )
        ]

        let result = StructuringValidator.validate(
            transcript: transcript,
            items: items,
            estimatedTopicCount: 2,
            transcriptCoverage: "complete"
        )

        #expect(result.warnings.isEmpty)
        #expect(result.needsUserReview == false)
        #expect(result.confidenceScore >= 0.80)
    }

    @Test func structuringValidatorMalformedFixtureTriggersWarnings() {
        let transcript = "The freezer alarm keeps chirping and front sink is leaking near prep station."
        let items = [
            CategorizedItem(
                category: .equipment,
                content: "Everything in the kitchen is probably failing soon",
                urgency: .fyi,
                sourceQuote: "boiler room explosion"
            )
        ]

        let result = StructuringValidator.validate(
            transcript: transcript,
            items: items,
            estimatedTopicCount: 2,
            transcriptCoverage: "partial"
        )

        #expect(result.warnings.contains(.sourceQuoteMismatch))
        #expect(result.warnings.contains(.aiPartialCoverage))
        #expect(result.needsUserReview)
        #expect(result.confidenceScore < 0.70)
    }

    @Test func structuringTelemetryLoggerRecordsPhase0Signals() {
        let logger = StructuringTelemetryLogger()

        logger.log(.aiStructuringSucceeded(itemCount: 3))
        logger.log(.validationEvaluated(warningCount: 1, confidenceScore: 0.62, needsUserReview: true))
        logger.log(.aiFallbackUsed(reason: "Failed to parse AI response."))

        let events = logger.recentEvents(limit: 5)

        #expect(events.count == 3)
        #expect(events.first?.kind == .aiFallbackUsed)
        #expect(logger.fallbackEventCount == 1)
    }
}
