import CoreGraphics
import XCTest
@testable import NcduUI

final class SquarifyTests: XCTestCase {

    /// Mirrors TreemapView: scale byte weights to the drawable rect area.
    private func normalizedAreas(_ weights: [Double], in rect: CGRect) -> [Double] {
        let total = weights.reduce(0, +)
        guard total > 0 else { return weights }
        let area = Double(rect.width * rect.height)
        return weights.map { $0 / total * area }
    }

    func testEmptyAreasReturnsZeroRects() {
        let rects = Squarify.layout(areas: [], in: CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertTrue(rects.isEmpty)
    }

    func testSingleAreaFillsRect() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
        let areas = normalizedAreas([100], in: rect)
        let rects = Squarify.layout(areas: areas, in: rect)
        XCTAssertEqual(rects.count, 1)
        XCTAssertEqual(rects[0].width, 200, accuracy: 0.01)
        XCTAssertEqual(rects[0].height, 100, accuracy: 0.01)
    }

    func testRectsPreserveInputOrder() {
        let areas: [Double] = [50, 30, 20]
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let rects = Squarify.layout(areas: areas, in: rect)
        XCTAssertEqual(rects.count, 3)
        // Largest area should get the first (typically largest) rect by area.
        let sortedByArea = rects.enumerated().sorted { $0.element.width * $0.element.height > $1.element.width * $1.element.height }
        XCTAssertEqual(sortedByArea[0].offset, 0)
    }

    func testRectsFillContainer() {
        let areas: [Double] = [40, 30, 20, 10]
        let rect = CGRect(x: 10, y: 20, width: 300, height: 200)
        let normalized = normalizedAreas(areas, in: rect)
        let rects = Squarify.layout(areas: normalized, in: rect)
        let totalArea = rects.reduce(0.0) { $0 + $1.width * $1.height }
        XCTAssertEqual(totalArea, rect.width * rect.height, accuracy: 1.0)
    }

    func testRectsDoNotOverlap() {
        let areas: [Double] = [100, 80, 60, 40, 20, 10]
        let rect = CGRect(x: 0, y: 0, width: 400, height: 300)
        let rects = Squarify.layout(areas: areas, in: rect)
        for i in 0..<rects.count {
            for j in (i + 1)..<rects.count {
                XCTAssertFalse(rects[i].intersects(rects[j]), "Rects \(i) and \(j) overlap")
            }
        }
    }

    func testAllRectsWithinBounds() {
        let areas: [Double] = [50, 40, 30, 20, 10]
        let rect = CGRect(x: 5, y: 5, width: 250, height: 150)
        let rects = Squarify.layout(areas: areas, in: rect)
        for r in rects {
            XCTAssertGreaterThanOrEqual(r.minX, rect.minX - 0.01)
            XCTAssertGreaterThanOrEqual(r.minY, rect.minY - 0.01)
            XCTAssertLessThanOrEqual(r.maxX, rect.maxX + 0.01)
            XCTAssertLessThanOrEqual(r.maxY, rect.maxY + 0.01)
        }
    }
}
