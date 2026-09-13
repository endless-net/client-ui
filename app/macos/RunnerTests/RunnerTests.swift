import Cocoa
import FlutterMacOS
import XCTest

class RunnerTests: XCTestCase {

  func testApplicationIdentity() {
    XCTAssertEqual(Bundle.main.bundleIdentifier, "endlessnet.app")
    XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String, "EndlessNet")
  }

}
