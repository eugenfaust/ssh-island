import Foundation
import CoreGraphics
import SSHIslandCore

final class NotchGeometryTests: XCTestCase {
    func testNotchedBuiltInWithExternalScreenOffset() throws {
        let frame = CGRect(x: -1512, y: 300, width: 1512, height: 982)
        let left = CGRect(x: -1512, y: 1250, width: 650, height: 32)
        let right = CGRect(x: -650, y: 1250, width: 650, height: 32)
        let notch = try XCTUnwrap(NotchGeometry.detect(frame: frame, builtIn: true, topInset: 32, left: left, right: right))
        XCTAssertEqual(notch.width, 212)
        let collapsed = notch.panelFrame(width: 224, contentHeight: 8)
        XCTAssertEqual(collapsed, CGRect(x: -868, y: 1242, width: 224, height: 40))
        XCTAssertEqual(collapsed.maxY, frame.maxY)
        XCTAssertEqual(collapsed.minY, 1242)
        XCTAssertEqual(notch.panelFrame(width: 420, contentHeight: 460), CGRect(x: -966, y: 790, width: 420, height: 492))
        XCTAssertNil(NotchGeometry.detect(frame: frame, builtIn: false, topInset: 32, left: left, right: right))
        XCTAssertNil(NotchGeometry.detect(frame: frame, builtIn: true, topInset: 0, left: left, right: right))
        XCTAssertNil(NotchGeometry.detect(frame: frame, builtIn: true, topInset: 32, left: nil, right: right))
    }
    func testRejectsUnreliableGap() {
        XCTAssertNil(NotchGeometry.detect(frame: CGRect(x: 0, y: 0, width: 1000, height: 800), builtIn: true, topInset: 30,
                                          left: CGRect(x: 0, y: 770, width: 100, height: 30), right: CGRect(x: 900, y: 770, width: 100, height: 30)))
    }
}
