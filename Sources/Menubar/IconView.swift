import MenubarCore
import SwiftUI

/// Draws one of the app's icons at any size, in the current foreground style.
struct IconView: View {
    let icon: Icon
    let size: CGFloat

    init(_ icon: Icon, size: CGFloat = 18) {
        self.icon = icon
        self.size = size
    }

    var body: some View {
        IconShape(icon: icon)
            .stroke(style: StrokeStyle(
                lineWidth: Icon.strokeWidth * size / Icon.gridSize,
                lineCap: .round, lineJoin: .round
            ))
            .frame(width: size, height: size)
    }
}

private struct IconShape: Shape {
    let icon: Icon

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for command in icon.commands.joined() {
            switch command {
            case .move(let x, let y):
                path.move(to: CGPoint(x: x, y: y))
            case .line(let x, let y):
                path.addLine(to: CGPoint(x: x, y: y))
            case .curve(let c1x, let c1y, let c2x, let c2y, let x, let y):
                path.addCurve(
                    to: CGPoint(x: x, y: y),
                    control1: CGPoint(x: c1x, y: c1y), control2: CGPoint(x: c2x, y: c2y)
                )
            case .close:
                path.closeSubpath()
            }
        }
        let scale = min(rect.width, rect.height) / Icon.gridSize
        return path.applying(CGAffineTransform(scaleX: scale, y: scale))
    }
}
