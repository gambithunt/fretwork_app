import Foundation
import XCTest
@testable import Fretwork

final class UsageTelemetryTests: XCTestCase {
    func testDailyTokenIsStableWithinADayAndRotatesTheNextDay() {
        let first = UsageTelemetry.tokens(for: date("2026-09-02T08:00:00Z"), installationSecret: "test-secret")
        let later = UsageTelemetry.tokens(for: date("2026-09-02T22:00:00Z"), installationSecret: "test-secret")
        let tomorrow = UsageTelemetry.tokens(for: date("2026-09-03T08:00:00Z"), installationSecret: "test-secret")

        XCTAssertEqual(first.dayToken, later.dayToken)
        XCTAssertNotEqual(first.dayToken, tomorrow.dayToken)
    }

    func testWeeklyAndMonthlyTokensOnlyRotateAtTheirOwnBoundaries() {
        let start = UsageTelemetry.tokens(for: date("2026-09-02T08:00:00Z"), installationSecret: "test-secret")
        let sameWeek = UsageTelemetry.tokens(for: date("2026-09-04T08:00:00Z"), installationSecret: "test-secret")
        let nextWeek = UsageTelemetry.tokens(for: date("2026-09-07T08:00:00Z"), installationSecret: "test-secret")
        let nextMonth = UsageTelemetry.tokens(for: date("2026-10-01T08:00:00Z"), installationSecret: "test-secret")

        XCTAssertEqual(start.weekToken, sameWeek.weekToken)
        XCTAssertNotEqual(start.weekToken, nextWeek.weekToken)
        XCTAssertNotEqual(start.monthToken, nextMonth.monthToken)
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
