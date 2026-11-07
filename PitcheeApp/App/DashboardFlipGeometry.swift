import CoreGraphics

/// Shared geometry keeps both faces on the same surface throughout the flip.
struct DashboardFlipGeometry {
    let progress: Double
    let frame: CGRect

    init(progress: Double, source: CGRect, destination: CGRect) {
        let progress = min(max(progress, 0), 1)
        self.progress = progress
        let fraction = CGFloat(progress)
        frame = CGRect(
            x: source.minX + (destination.minX - source.minX) * fraction,
            y: source.minY + (destination.minY - source.minY) * fraction,
            width: source.width + (destination.width - source.width) * fraction,
            height: source.height + (destination.height - source.height) * fraction
        )
    }

    var frontAngle: Double { progress * 180 }
    var backAngle: Double { frontAngle - 180 }
    var showsFront: Bool { progress < 0.5 }
}
