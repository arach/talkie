import XCTest
@testable import NotchCanonicalTest

final class NotchCornerGeometryTests: XCTestCase {
    func testSignDrivesCornerKind() {
        XCTAssertEqual(NotchCornerGeometry.rightCornerKind(anchorX: 12), .external)
        XCTAssertEqual(NotchCornerGeometry.rightCornerKind(anchorX: 0), .external)
        XCTAssertEqual(NotchCornerGeometry.rightCornerKind(anchorX: -12), .inward)

        XCTAssertEqual(NotchCornerGeometry.leftCornerKind(anchorX: 8), .external)
        XCTAssertEqual(NotchCornerGeometry.leftCornerKind(anchorX: -8), .inward)
    }

    func testRightAnchorsKeepYFixedWhenXChanges() {
        let topY: CGFloat = 10
        let drop: CGFloat = 6
        let edgeX: CGFloat = 120

        let external = NotchCornerGeometry.rightAnchors(edgeX: edgeX, topY: topY, drop: drop, anchorX: 14)
        let internalCorner = NotchCornerGeometry.rightAnchors(edgeX: edgeX, topY: topY, drop: drop, anchorX: -14)

        XCTAssertEqual(external.shoulder.y, topY)
        XCTAssertEqual(internalCorner.shoulder.y, topY)
        XCTAssertEqual(external.edge.y, topY + drop)
        XCTAssertEqual(internalCorner.edge.y, topY + drop)

        XCTAssertEqual(external.shoulder.x, edgeX + 14)
        XCTAssertEqual(internalCorner.shoulder.x, edgeX - 14)
        XCTAssertEqual(external.edge.x, edgeX)
        XCTAssertEqual(internalCorner.edge.x, edgeX)
    }
}
