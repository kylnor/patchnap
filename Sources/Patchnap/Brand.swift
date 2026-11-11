import SwiftUI

extension Color {
    static let patchnapGrape = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.773, green: 0.682, blue: 0.914, alpha: 1)
            : NSColor(red: 0.357, green: 0.278, blue: 0.498, alpha: 1)
    })
    static let patchnapMint = Color(red: 0.663, green: 0.859, blue: 0.773)
}
struct PatchMascot: View {
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 180, size.height / 160)
            context.scaleBy(x: scale, y: scale)
            let shape = Path(roundedRect: CGRect(x: 26, y: 21, width: 128, height: 120), cornerRadius: 39)
            context.fill(shape, with: .color(.patchnapMint))
            let stitches = Path(roundedRect: CGRect(x: 35, y: 30, width: 110, height: 102), cornerRadius: 31)
            context.stroke(stitches, with: .color(Color(red: 0.22, green: 0.19, blue: 0.30).opacity(0.45)), style: StrokeStyle(lineWidth: 2, dash: [4,7]))
            var face = Path()
            face.move(to: CGPoint(x: 53, y: 74)); face.addQuadCurve(to: CGPoint(x: 75, y: 74), control: CGPoint(x: 64, y: 94))
            face.move(to: CGPoint(x: 103, y: 74)); face.addQuadCurve(to: CGPoint(x: 125, y: 74), control: CGPoint(x: 114, y: 94))
            face.move(to: CGPoint(x: 85, y: 96)); face.addQuadCurve(to: CGPoint(x: 95, y: 96), control: CGPoint(x: 90, y: 105))
            context.stroke(face, with: .color(Color(red: 0.22, green: 0.19, blue: 0.30)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            for x in [43.0, 117.0] { context.fill(Path(ellipseIn: CGRect(x: x, y: 87, width: 20, height: 10)), with: .color(Color(red: 0.914, green: 0.678, blue: 0.729))) }
        }
        .rotationEffect(.degrees(-9))
        .accessibilityLabel("Patchnap's sleepy stitched patch")
    }
}
