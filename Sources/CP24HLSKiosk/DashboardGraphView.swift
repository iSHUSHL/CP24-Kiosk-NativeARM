import AppKit

final class DashboardGraphView: NSView {
    private var samples: [Double] = []
    private let maxSamples = 48
    private let strokeColor: NSColor
    private let fillColor: NSColor

    init(strokeColor: NSColor = .controlAccentColor) {
        self.strokeColor = strokeColor
        self.fillColor = strokeColor.withAlphaComponent(0.18)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.18).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func addSample(_ value: Double) {
        samples.append(min(max(value, 0), 1))
        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard samples.count > 1 else { return }

        let inset: CGFloat = 8
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let step = rect.width / CGFloat(max(samples.count - 1, 1))

        NSColor.white.withAlphaComponent(0.08).setStroke()
        for index in 1...2 {
            let y = rect.minY + rect.height * CGFloat(index) / 3
            let grid = NSBezierPath()
            grid.move(to: NSPoint(x: rect.minX, y: y))
            grid.line(to: NSPoint(x: rect.maxX, y: y))
            grid.lineWidth = 1
            grid.stroke()
        }

        let linePath = NSBezierPath()
        let fillPath = NSBezierPath()
        for (index, sample) in samples.enumerated() {
            let x = rect.minX + CGFloat(index) * step
            let y = rect.minY + CGFloat(sample) * rect.height
            let point = NSPoint(x: x, y: y)
            if index == 0 {
                linePath.move(to: point)
                fillPath.move(to: NSPoint(x: x, y: rect.minY))
                fillPath.line(to: point)
            } else {
                linePath.line(to: point)
                fillPath.line(to: point)
            }
        }

        if let last = samples.indices.last {
            let x = rect.minX + CGFloat(last) * step
            fillPath.line(to: NSPoint(x: x, y: rect.minY))
            fillPath.close()
            fillColor.setFill()
            fillPath.fill()
        }

        strokeColor.setStroke()
        linePath.lineWidth = 2
        linePath.lineJoinStyle = .round
        linePath.lineCapStyle = .round
        linePath.stroke()
    }
}
