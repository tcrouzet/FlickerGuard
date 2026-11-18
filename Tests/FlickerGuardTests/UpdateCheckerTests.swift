import Foundation
import Testing
@testable import FlickerGuard

@Test func updatesCompareNumericVersionComponents() throws {
    for (latest, current) in [("0.3.9", "0.3.8"), ("0.3.10", "0.3.9"), ("0.10.0", "0.9.99"), ("1.0.0", "0.99.99")] {
        #expect(try UpdateChecker.isNewer(latest, than: current))
        #expect(try !UpdateChecker.isNewer(current, than: latest))
        #expect(try !UpdateChecker.isNewer(latest, than: latest))
    }
}

@Test func invalidUpdateVersionsAreReportedInsteadOfClaimingTheAppIsCurrent() {
    for invalid in ["", "development", "1.2", "1.2.3.4", "1.2.-3", "01.2.3", "1.2.3-beta", "1.2.3\n", "1.2.999999999999999999999999999999999999999999"] {
        #expect(throws: URLError.self) { try UpdateChecker.isNewer(invalid, than: "0.3.8") }
        #expect(throws: URLError.self) { try UpdateChecker.isNewer("0.3.9", than: invalid) }
    }
}
