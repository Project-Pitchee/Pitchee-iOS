import CoreGraphics

@main
enum DashboardFlipTests {
    static func main() {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            precondition(condition(), message)
        }
        let source = CGRect(x: 20, y: 180, width: 164, height: 174)
        let destination = CGRect(x: 8, y: 12, width: 392, height: 820)
        let closed = DashboardFlipGeometry(progress: 0, source: source, destination: destination)
        check(closed.frame == source, "A closed flip occupies the original card's exact bounds")
        check(closed.frontAngle == 0 && closed.backAngle == -180 && closed.showsFront,
              "Only the unrotated card face is visible at the start")

        let opened = DashboardFlipGeometry(progress: 1, source: source, destination: destination)
        check(opened.frame == destination, "An open flip reaches the destination including its nonzero origin")
        check(opened.frontAngle == 180 && opened.backAngle == 0 && !opened.showsFront,
              "Only the unrotated detail face is visible at the end")

        let midpoint = DashboardFlipGeometry(progress: 0.5, source: source, destination: destination)
        check(midpoint.frame == CGRect(x: 14, y: 96, width: 278, height: 497),
              "Both faces share the halfway position and dimensions")
        check(midpoint.frontAngle == 90 && midpoint.backAngle == -90 && !midpoint.showsFront,
              "The detail face takes over exactly when both faces are edge-on")
        let beforeMidpoint = DashboardFlipGeometry(progress: 0.499, source: source, destination: destination)
        check(beforeMidpoint.showsFront, "The card remains visible until the halfway point")

        let closingFrames = [1.0, 0.75, 0.5, 0.25, 0.0].map {
            DashboardFlipGeometry(progress: $0, source: source, destination: destination)
        }
        check(closingFrames.map(\.frame) == [
            destination,
            CGRect(x: 11, y: 54, width: 335, height: 658.5),
            midpoint.frame,
            CGRect(x: 17, y: 138, width: 221, height: 335.5),
            source
        ], "Closing retraces the opening geometry back to the source")
        check(closingFrames.map(\.showsFront) == [false, false, false, true, true],
              "The source face reappears at the matching point during closing")
        check(closingFrames.map(\.backAngle) == [0, -45, -90, -135, -180],
              "The detail face rotates away continuously during closing")

        let belowStart = DashboardFlipGeometry(progress: -0.2, source: source, destination: destination)
        check(belowStart.progress == 0 && belowStart.frame == source && belowStart.frontAngle == 0,
              "Animation undershoot cannot shrink or rotate past the original card")
        let pastEnd = DashboardFlipGeometry(progress: 1.2, source: source, destination: destination)
        check(pastEnd.progress == 1 && pastEnd.frame == destination && pastEnd.backAngle == 0,
              "Animation overshoot cannot extend beyond the full detail page")
        print("Dashboard flip geometry: \(checks) checks passed")
    }
}
