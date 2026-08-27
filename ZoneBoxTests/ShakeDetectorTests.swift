import XCTest
@testable import ZoneBoxCore

final class ShakeDetectorTests: XCTestCase {
    func testOscillatingTraceIsShake() {
        XCTAssertTrue(ShakeDetector.isShake(Self.shakeTrace()))
    }

    func testLinearTraceOfSimilarLengthIsNotShake() {
        XCTAssertFalse(ShakeDetector.isShake(Self.linearTrace(length: 640)))
        XCTAssertFalse(ShakeDetector.isShake(Self.linearTrace(length: 200)))
    }

    func testShortJitterIsNotShake() {
        let points = (0..<12).map { i -> CGPoint in
            CGPoint(x: CGFloat(i % 2), y: 0)
        }
        XCTAssertFalse(ShakeDetector.isShake(points))
    }

    func testTooFewSamplesIsNotShake() {
        XCTAssertFalse(ShakeDetector.isShake([
            CGPoint(x: 0, y: 0),
            CGPoint(x: 80, y: 0),
            CGPoint(x: 0, y: 0),
        ]))
    }

    static func shakeTrace() -> [CGPoint] {
        var points: [CGPoint] = []
        let y: CGFloat = 200
        for cycle in 0..<4 {
            _ = cycle
            points.append(CGPoint(x: 200, y: y))
            points.append(CGPoint(x: 280, y: y))
            points.append(CGPoint(x: 200, y: y))
            points.append(CGPoint(x: 120, y: y))
        }
        points.append(CGPoint(x: 200, y: y))
        return points
    }

    static func linearTrace(length: CGFloat) -> [CGPoint] {
        let steps = 16
        let delta = length / CGFloat(steps)
        return (0...steps).map { CGPoint(x: 40 + CGFloat($0) * delta, y: 200) }
    }
}
