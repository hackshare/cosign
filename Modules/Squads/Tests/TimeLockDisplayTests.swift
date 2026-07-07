import XCTest
@testable import Squads

final class TimeLockDisplayTests: XCTestCase {
    func testMatchesRule() {
        XCTAssertEqual(cosignTimeLockDisplay(seconds: 0), "None")
        XCTAssertEqual(cosignTimeLockDisplay(seconds: 30), "30 seconds")
        XCTAssertEqual(cosignTimeLockDisplay(seconds: 60), "1 minute")
        XCTAssertEqual(cosignTimeLockDisplay(seconds: 3600), "1 hour")
        XCTAssertEqual(cosignTimeLockDisplay(seconds: 21600), "6 hours")
        XCTAssertEqual(cosignTimeLockDisplay(seconds: 86400), "24 hours")
        XCTAssertEqual(cosignTimeLockDisplay(seconds: 129_600), "36 hours")
        XCTAssertEqual(cosignTimeLockDisplay(seconds: 259_200), "3 days")
        XCTAssertEqual(cosignTimeLockDisplay(seconds: 7_776_000), "90 days")
    }
}
