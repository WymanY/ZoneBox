import XCTest
@testable import ZoneBoxCore

final class ShakeDetectorTests: XCTestCase {
    func testOscillatingTraceIsShake() {
        XCTAssertTrue(ShakeDetector.isShake(Self.shakeTrace()))
    }

    func testLinearTraceOfSimilarLengthIsNotShake() {
        XCTAssertFalse(ShakeDetector.isShake(Self.linearTrace(length: 640)))
        XCTAssertFalse(ShakeDetector.isShake(Self.linearTrace(length: 200)))
        XCTAssertFalse(ShakeDetector.isShake(Self.linearTrace(length: 400), intensity: 1))
        XCTAssertFalse(ShakeDetector.isShake(Self.linearTrace(length: 400), intensity: 10))
    }

    func testLinearDragThenWiggleIsShake() {
        let points = Self.appendingShake(Self.linearTrace(length: 400), amplitude: 28, cycles: 3)
        XCTAssertTrue(ShakeDetector.isShake(points, intensity: ShakeProfile.defaultIntensity))
        XCTAssertFalse(ShakeDetector.isShake(Self.linearTrace(length: 400), intensity: ShakeProfile.defaultIntensity))
    }

    func testIntensityMakesGentleShakeHarder() {
        let gentle = Self.appendingShake([CGPoint(x: 200, y: 200)], amplitude: 12, cycles: 3)
        XCTAssertTrue(ShakeDetector.isShake(gentle, intensity: 1))
        XCTAssertFalse(ShakeDetector.isShake(gentle, intensity: 10))
    }

    func testShortJitterIsNotShake() {
        let points = (0..<12).map { i -> CGPoint in
            CGPoint(x: CGFloat(i % 2), y: 0)
        }
        XCTAssertFalse(ShakeDetector.isShake(points))
        XCTAssertFalse(ShakeDetector.isShake(points, intensity: 1))
    }

    func testTooFewSamplesIsNotShake() {
        XCTAssertFalse(ShakeDetector.isShake([
            CGPoint(x: 0, y: 0),
            CGPoint(x: 80, y: 0),
            CGPoint(x: 0, y: 0),
        ]))
    }

    func testSparseFourPointWiggleTriggersAtIntensityOne() {
        let points = [
            CGPoint(x: 100, y: 80),
            CGPoint(x: 130, y: 80),
            CGPoint(x: 100, y: 80),
            CGPoint(x: 130, y: 80),
        ]
        XCTAssertTrue(ShakeDetector.isShake(points, intensity: 1))
        XCTAssertFalse(ShakeDetector.isShake(points, intensity: 10))
    }

    func testProfileClampsIntensity() {
        XCTAssertEqual(ShakeProfile.clampedIntensity(0), 1)
        XCTAssertEqual(ShakeProfile.clampedIntensity(11), 10)
        XCTAssertEqual(ShakeProfile.profile(intensity: 1).minimumReversals, 2)
        XCTAssertGreaterThan(
            ShakeProfile.profile(intensity: 10).minimumReversals,
            ShakeProfile.profile(intensity: 1).minimumReversals
        )
    }

    static func shakeTrace() -> [CGPoint] {
        appendingShake([CGPoint(x: 200, y: 200)], amplitude: 80, cycles: 4)
    }

    static func linearTrace(length: CGFloat) -> [CGPoint] {
        let steps = 16
        let delta = length / CGFloat(steps)
        return (0...steps).map { CGPoint(x: 40 + CGFloat($0) * delta, y: 200) }
    }

    static func appendingShake(_ base: [CGPoint], amplitude: CGFloat, cycles: Int) -> [CGPoint] {
        guard var cursor = base.last else { return base }
        var points = base
        for _ in 0..<cycles {
            cursor.x += amplitude
            points.append(cursor)
            cursor.x -= amplitude
            points.append(cursor)
            cursor.x -= amplitude
            points.append(cursor)
            cursor.x += amplitude
            points.append(cursor)
        }
        return points
    }
}
