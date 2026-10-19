import XCTest
import Foundation
import CoreGraphics
@testable import CleanRKit

final class SquarifiedTreemapTests: XCTestCase {

    private func node(_ name: String, size: UInt64) -> TreemapNode {
        TreemapNode(name: name, size: size, url: URL(filePath: "/\(name)"),
                    isDirectory: true, children: [])
    }

    private let canvas = CGRect(x: 0, y: 0, width: 100, height: 100)

    // MARK: - Boundary conditions

    func testEmptyInputReturnsEmpty() {
        XCTAssertTrue(SquarifiedTreemap.layout(nodes: [], in: canvas).isEmpty)
    }

    func testZeroAreaCanvasReturnsEmpty() {
        let zero = CGRect(x: 0, y: 0, width: 0, height: 0)
        XCTAssertTrue(SquarifiedTreemap.layout(nodes: [node("a", size: 100)], in: zero).isEmpty)
    }

    func testZeroSizeNodesReturnEmpty() {
        let rects = SquarifiedTreemap.layout(
            nodes: [node("a", size: 0), node("b", size: 0)], in: canvas
        )
        XCTAssertTrue(rects.isEmpty)
    }

    // MARK: - Single node

    func testSingleNodeFillsCanvas() {
        let rects = SquarifiedTreemap.layout(nodes: [node("solo", size: 1000)], in: canvas)
        XCTAssertEqual(rects.count, 1)
        XCTAssertEqual(rects[0].rect.width, canvas.width, accuracy: 0.001)
        XCTAssertEqual(rects[0].rect.height, canvas.height, accuracy: 0.001)
    }

    // MARK: - Multiple nodes

    func testMultipleNodesProduceCorrectCount() {
        let nodes = [
            node("a", size: 500), node("b", size: 300),
            node("c", size: 200), node("d", size: 100), node("e", size: 50),
        ]
        let rects = SquarifiedTreemap.layout(nodes: nodes, in: canvas)
        XCTAssertEqual(rects.count, nodes.count)
    }

    func testTotalAreaApproximatelyMatchesCanvas() {
        let nodes = [
            node("a", size: 500), node("b", size: 300), node("c", size: 200),
        ]
        let rects = SquarifiedTreemap.layout(nodes: nodes, in: canvas)
        let totalArea = rects.reduce(0.0) { $0 + Double($1.rect.width * $1.rect.height) }
        let canvasArea = Double(canvas.width * canvas.height)
        XCTAssertEqual(totalArea, canvasArea, accuracy: 0.5,
                       "Sum of laid-out rect areas should approximately fill the canvas")
    }

    func testLargerNodeGetsLargerRect() {
        let big = node("big", size: 800)
        let small = node("small", size: 200)
        let rects = SquarifiedTreemap.layout(nodes: [big, small], in: canvas)
        XCTAssertEqual(rects.count, 2)
        let bigRect = rects.first { $0.node.name == "big" }!
        let smallRect = rects.first { $0.node.name == "small" }!
        XCTAssertGreaterThan(bigRect.rect.width * bigRect.rect.height,
                             smallRect.rect.width * smallRect.rect.height)
    }

    func testRectsStayWithinCanvas() {
        let nodes = (0..<10).map { node("n\($0)", size: UInt64(10 - $0) * 100 + 1) }
        let rects = SquarifiedTreemap.layout(nodes: nodes, in: canvas)
        for rect in rects {
            XCTAssertGreaterThanOrEqual(rect.rect.minX, canvas.minX - 0.001)
            XCTAssertGreaterThanOrEqual(rect.rect.minY, canvas.minY - 0.001)
            XCTAssertLessThanOrEqual(rect.rect.maxX, canvas.maxX + 0.001)
            XCTAssertLessThanOrEqual(rect.rect.maxY, canvas.maxY + 0.001)
        }
    }

    // MARK: - worstAspectRatio

    func testWorstAspectRatioWithEmptyAreas() {
        XCTAssertEqual(SquarifiedTreemap.worstAspectRatio(
            areas: [], totalArea: 100, sideLength: 10
        ), .infinity)
    }

    func testWorstAspectRatioWithZeroSide() {
        XCTAssertEqual(SquarifiedTreemap.worstAspectRatio(
            areas: [10], totalArea: 10, sideLength: 0
        ), .infinity)
    }

    func testWorstAspectRatioReasonable() {
        // Single area filling a square section: aspect ratio = 1
        let ratio = SquarifiedTreemap.worstAspectRatio(
            areas: [100], totalArea: 100, sideLength: 10
        )
        XCTAssertEqual(ratio, 1.0, accuracy: 0.001)
    }
}
