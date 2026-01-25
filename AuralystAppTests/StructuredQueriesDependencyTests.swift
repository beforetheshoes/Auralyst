import XCTest
import IssueReporting
import StructuredQueries
import StructuredQueriesCore
import StructuredQueriesSQLite
import StructuredQueriesSQLiteCore

final class StructuredQueriesDependencyTests: XCTestCase {
  func testStructuredQueriesIssueReportingSupportIsPresent() {
    // Accessing IssueReporting APIs through StructuredQueries should not require manual wiring.
    let reporters = IssueReporters.current
    XCTAssertFalse(reporters.isEmpty, "StructuredQueries should link IssueReporting's defaults")
  }
}
