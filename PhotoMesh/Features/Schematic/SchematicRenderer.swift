import SwiftUI

/// Maps layout units to view points: view = layout × scale + offset.
struct SchematicCamera: Equatable, Animatable {
    var scale: CGFloat = 1
    var offset: CGSize = .zero

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(scale, AnimatablePair(offset.width, offset.height)) }
        set {
            scale = newValue.first
            offset = CGSize(width: newValue.second.first, height: newValue.second.second)
        }
    }

    var transform: CGAffineTransform {
        CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: offset.width, ty: offset.height)
    }

    func convert(_ p: SPoint) -> CGPoint {
        CGPoint(x: p.x * scale + offset.width, y: p.y * scale + offset.height)
    }

    func convertToLayout(_ p: CGPoint) -> SPoint {
        SPoint(x: (p.x - offset.width) / scale, y: (p.y - offset.height) / scale)
    }

    /// Camera that shows `rect` centred in `size`.
    static func fitting(_ rect: SRect, in size: CGSize, padding: CGFloat = 18) -> SchematicCamera {
        fitting(rect, in: size, insets: EdgeInsets(top: padding, leading: padding, bottom: padding, trailing: padding))
    }

    /// Camera that shows `rect` centred in the part of `size` left after `insets` (room for overlay controls).
    static func fitting(_ rect: SRect, in size: CGSize, insets: EdgeInsets) -> SchematicCamera {
        let available = CGSize(width: size.width - insets.leading - insets.trailing, height: size.height - insets.top - insets.bottom)
        guard !rect.isEmpty, available.width > 10, available.height > 10 else { return SchematicCamera() }
        let w = max(rect.width, 1), h = max(rect.height, 1)
        let scale = min(available.width / w, available.height / h)
        let centerX = insets.leading + available.width / 2
        let centerY = insets.top + available.height / 2
        return SchematicCamera(
            scale: scale,
            offset: CGSize(width: centerX - rect.center.x * scale, height: centerY - rect.center.y * scale)
        )
    }
}

/// What to emphasise while drawing.
struct SchematicStyle {
    var focus = StepFocus()
    var loops: [LoopPath] = []
    var selection: SchematicLayout.Hit?
    var showsNodeLabels = true
    var formatter = QuantityFormatter()
    /// Sketch mode: unfinished elements (no value yet) are drawn hollow.
    var pendingValueIds: Set<String> = []
    var askedIds: Set<String> = []
}

/// Draws a `SchematicLayout` into a `GraphicsContext`. Geometry is built in layout units and
/// transformed by the camera, so line widths and text stay crisp at any zoom.
enum SchematicRenderer {
    static let ink = Color(red: 0.12, green: 0.12, blue: 0.14)
    static let dim = Color(red: 0.12, green: 0.12, blue: 0.14).opacity(0.22)
    static let nodeLabelColor = Color(red: 0.33, green: 0.45, blue: 0.75)

    static func draw(_ layout: SchematicLayout, camera: SchematicCamera, style: SchematicStyle, in context: inout GraphicsContext, size: CGSize) {
        let t = camera.transform
        let hasFocus = !style.focus.isEmpty
        let focusedElements = focusedElementIds(style)
        let focusedNodes = focusedNodeIds(style, layout: layout)

        // Wires
        for wire in layout.wires {
            let focused = focusedNodes.contains(wire.node)
            let selected = style.selection == .node(wire.node)
            var path = Path()
            path.move(to: cg(wire.from))
            path.addLine(to: cg(wire.to))
            path = path.applying(t)
            if selected {
                context.stroke(path, with: .color(PMTheme.accent.opacity(0.25)), lineWidth: 10)
            }
            let color: Color = (focused || selected) ? PMTheme.accent : (hasFocus ? dim : ink)
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: focused || selected ? 3 : 2, lineCap: .round))
        }

        // Junction dots
        for junction in layout.junctions {
            let focused = focusedNodes.contains(junction.node) || style.selection == .node(junction.node)
            let p = camera.convert(junction.point)
            let r: CGFloat = focused ? 5 : 4
            context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(focused ? PMTheme.accent : (hasFocus ? dim : ink)))
        }

        // Ground
        if let ground = layout.groundPoint {
            let focused = focusedNodes.contains(layout.groundNode)
            var path = Path()
            let x = ground.x, y = ground.y
            path.move(to: CGPoint(x: x, y: y)); path.addLine(to: CGPoint(x: x, y: y + 16))
            for (i, half) in [18.0, 12.0, 6.0].enumerated() {
                let yy = y + 16 + Double(i) * 7
                path.move(to: CGPoint(x: x - half, y: yy)); path.addLine(to: CGPoint(x: x + half, y: yy))
            }
            context.stroke(path.applying(t), with: .color(focused ? PMTheme.accent : (hasFocus ? dim : ink)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }

        // Symbols
        for symbol in layout.symbols {
            let focused = focusedElements.contains(symbol.id)
            let selected = style.selection == .element(symbol.id)
            let color: Color = (focused || selected) ? PMTheme.accent : (hasFocus ? dim : ink)
            let width: CGFloat = (focused || selected) ? 3 : 2
            let body = symbolPath(symbol)
            if selected {
                context.stroke(body.applying(t), with: .color(PMTheme.accent.opacity(0.22)), style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))
            }
            context.stroke(body.applying(t), with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            drawSymbolDecorations(symbol, camera: camera, color: color, in: &context)
            drawSymbolLabel(symbol, camera: camera, color: color, style: style, in: &context)
        }

        // Node labels and voltages
        if style.showsNodeLabels {
            for label in layout.nodeLabels {
                let focused = focusedNodes.contains(label.node) || style.selection == .node(label.node)
                let p = camera.convert(label.point)
                let anchorPoint = CGPoint(x: p.x + 7, y: p.y - 9)
                let color: Color = focused ? PMTheme.accent : (hasFocus ? nodeLabelColor.opacity(0.4) : nodeLabelColor)
                var text = label.node
                if let v = style.focus.nodeVoltages[label.node], label.node != layout.groundNode {
                    text += "  " + style.formatter.format(v, "V")
                }
                context.draw(
                    Text(text).font(.system(size: focused ? 12 : 11, weight: focused ? .semibold : .medium, design: .rounded)).foregroundStyle(color),
                    at: anchorPoint, anchor: .bottomLeading
                )
            }
        }

        // Currents
        for (id, current) in style.focus.elementCurrents {
            guard let symbol = layout.symbol(id) else { continue }
            drawCurrentArrow(symbol, current: current, camera: camera, style: style, in: &context)
        }

        // Mesh arrows
        if style.focus.showMeshArrows {
            let indices = style.focus.loops.isEmpty ? Array(style.loops.indices) : style.focus.loops
            for k in indices where k < style.loops.count {
                drawMeshArrow(index: k, loop: style.loops[k], layout: layout, camera: camera, style: style, in: &context)
            }
        }
    }

    // MARK: Focus resolution

    static func focusedElementIds(_ style: SchematicStyle) -> Set<String> {
        var ids = Set(style.focus.elements)
        for k in style.focus.loops where k < style.loops.count { ids.formUnion(style.loops[k].elementIds) }
        return ids
    }

    static func focusedNodeIds(_ style: SchematicStyle, layout: SchematicLayout) -> Set<String> {
        var ids = Set(style.focus.nodes)
        for k in style.focus.loops where k < style.loops.count { ids.formUnion(style.loops[k].nodeSequence) }
        return ids
    }

    /// Bounding rectangle of everything a focus refers to, in layout units.
    static func focusBounds(_ focus: StepFocus, loops: [LoopPath], layout: SchematicLayout) -> SRect {
        var r = SRect.empty
        for node in focus.nodes { r.include(layout.bounds(ofNode: node)) }
        r.include(layout.bounds(ofElements: focus.elements))
        for k in focus.loops where k < loops.count {
            r.include(layout.bounds(ofElements: loops[k].elementIds))
            r.include(SRect.around(layout.polygon(forLoopElements: loops[k].elementIds)))
        }
        return r
    }

    // MARK: Symbol geometry (layout units)

    static func cg(_ p: SPoint) -> CGPoint { CGPoint(x: p.x, y: p.y) }

    static func sourceRadius(_ symbol: SchematicLayout.Symbol) -> Double {
        min(max(symbol.length * 0.28, 12), 30)
    }

    static func symbolPath(_ symbol: SchematicLayout.Symbol) -> Path {
        var path = Path()
        let a = symbol.a, b = symbol.b
        let length = max(symbol.length, 1)
        let u = SPoint(x: (b.x - a.x) / length, y: (b.y - a.y) / length)
        let n = SPoint(x: -u.y, y: u.x)

        switch symbol.kind {
        case .resistor:
            let lead = length * 0.2
            let start = a + u * lead
            let end = b - u * lead
            path.move(to: cg(a)); path.addLine(to: cg(start))
            let style = UserDefaults.standard.string(forKey: SettingsKeys.resistorStyle) == ResistorStyle.iec.rawValue ? ResistorStyle.iec : .ansi
            let amp = min(max(length * 0.11, 6), 14)
            switch style {
            case .ansi:
                let peaks = 6
                let segment = (length - 2 * lead) / Double(peaks + 1)
                for i in 1...peaks {
                    let side: Double = i % 2 == 1 ? 1 : -1
                    path.addLine(to: cg(start + u * (segment * Double(i)) + n * (amp * side)))
                }
                path.addLine(to: cg(end))
            case .iec:
                path.addLine(to: cg(start + n * amp))
                path.addLine(to: cg(end + n * amp))
                path.addLine(to: cg(end - n * amp))
                path.addLine(to: cg(start - n * amp))
                path.addLine(to: cg(start + n * amp))
                path.move(to: cg(end))
            }
            path.addLine(to: cg(b))
        case .voltageSource, .currentSource:
            let r = sourceRadius(symbol)
            let c = symbol.center
            path.move(to: cg(a)); path.addLine(to: cg(c - u * r))
            path.move(to: cg(c + u * r)); path.addLine(to: cg(b))
            path.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            if symbol.kind == .currentSource {
                // Arrow inside the circle pointing from a to b (direction of the source current).
                let tail = c - u * (r * 0.6), tip = c + u * (r * 0.62)
                path.move(to: cg(tail)); path.addLine(to: cg(tip))
                let head = r * 0.38
                path.move(to: cg(tip - u * head + n * (head * 0.6)))
                path.addLine(to: cg(tip))
                path.addLine(to: cg(tip - u * head - n * (head * 0.6)))
            }
        }
        return path
    }

    private static func drawSymbolDecorations(_ symbol: SchematicLayout.Symbol, camera: SchematicCamera, color: Color, in context: inout GraphicsContext) {
        guard symbol.kind == .voltageSource else { return }
        let r = sourceRadius(symbol)
        let length = max(symbol.length, 1)
        let u = SPoint(x: (symbol.b.x - symbol.a.x) / length, y: (symbol.b.y - symbol.a.y) / length)
        let plus = camera.convert(symbol.center - u * (r * 0.45))
        let minus = camera.convert(symbol.center + u * (r * 0.45))
        let fontSize = min(max(r * camera.scale * 0.9, 7), 15)
        context.draw(Text("+").font(.system(size: fontSize, weight: .bold)).foregroundStyle(color), at: plus, anchor: .center)
        context.draw(Text("−").font(.system(size: fontSize, weight: .bold)).foregroundStyle(color), at: minus, anchor: .center)
    }

    private static func drawSymbolLabel(_ symbol: SchematicLayout.Symbol, camera: SchematicCamera, color: Color, style: SchematicStyle, in context: inout GraphicsContext) {
        guard camera.scale > 0.1 else { return }
        let side = symbol.labelSide
        let clearance: Double = symbol.kind == .resistor ? 20 : sourceRadius(symbol) + 10
        let anchorLayout = symbol.center + side * clearance
        var p = camera.convert(anchorLayout)
        let anchor: UnitPoint
        if abs(side.x) > abs(side.y) {
            anchor = side.x > 0 ? .leading : .trailing
            p.x += side.x > 0 ? 4 : -4
        } else {
            anchor = side.y > 0 ? .top : .bottom
            p.y += side.y > 0 ? 4 : -4
        }
        let idText = Text(symbol.id).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(color)
        let valueString = style.pendingValueIds.contains(symbol.id) ? "?" : style.formatter.format(symbol.value, symbol.kind.unitSymbol)
        let valueText = Text(valueString).font(.system(size: 11, design: .rounded)).foregroundStyle(style.pendingValueIds.contains(symbol.id) ? PMTheme.whyOrange : color.opacity(0.85))
        let asked = style.askedIds.contains(symbol.id) ? Text("  ?").font(.system(size: 11, weight: .bold)).foregroundStyle(PMTheme.whyOrange) : nil

        switch anchor {
        case .leading, .trailing:
            context.draw(idText, at: CGPoint(x: p.x, y: p.y - 7), anchor: anchor)
            context.draw(valueText, at: CGPoint(x: p.x, y: p.y + 8), anchor: anchor)
            if let asked { context.draw(asked, at: CGPoint(x: p.x, y: p.y + 22), anchor: anchor) }
        case .top:
            context.draw(idText, at: p, anchor: .top)
            context.draw(valueText, at: CGPoint(x: p.x, y: p.y + 15), anchor: .top)
            if let asked { context.draw(asked, at: CGPoint(x: p.x, y: p.y + 29), anchor: .top) }
        default:
            context.draw(valueText, at: p, anchor: .bottom)
            context.draw(idText, at: CGPoint(x: p.x, y: p.y - 14), anchor: .bottom)
            if let asked { context.draw(asked, at: CGPoint(x: p.x, y: p.y - 28), anchor: .bottom) }
        }
    }

    private static func drawCurrentArrow(_ symbol: SchematicLayout.Symbol, current: Double, camera: SchematicCamera, style: SchematicStyle, in context: inout GraphicsContext) {
        guard abs(current) > 1e-12 else { return }
        let length = max(symbol.length, 1)
        var u = SPoint(x: (symbol.b.x - symbol.a.x) / length, y: (symbol.b.y - symbol.a.y) / length)
        var tipLayout = symbol.a + u * (length * 0.9)
        if current < 0 {
            u = u * -1
            tipLayout = symbol.b + u * (length * 0.9)
        }
        let tip = camera.convert(tipLayout)
        let dir = CGPoint(x: u.x, y: u.y)
        let normal = CGPoint(x: -dir.y, y: dir.x)
        let size: CGFloat = 8
        var head = Path()
        head.move(to: tip)
        head.addLine(to: CGPoint(x: tip.x - dir.x * size + normal.x * size * 0.55, y: tip.y - dir.y * size + normal.y * size * 0.55))
        head.addLine(to: CGPoint(x: tip.x - dir.x * size - normal.x * size * 0.55, y: tip.y - dir.y * size - normal.y * size * 0.55))
        head.closeSubpath()
        context.fill(head, with: .color(PMTheme.accent))

        // Value on the side opposite to the component label.
        let side = symbol.labelSide * -1
        let anchorLayout = symbol.center + side * (symbol.kind == .resistor ? 18 : sourceRadius(symbol) + 8)
        var p = camera.convert(anchorLayout)
        let anchor: UnitPoint
        if abs(side.x) > abs(side.y) {
            anchor = side.x > 0 ? .leading : .trailing
            p.x += side.x > 0 ? 4 : -4
        } else {
            anchor = side.y > 0 ? .top : .bottom
            p.y += side.y > 0 ? 4 : -4
        }
        let label = style.formatter.format(abs(current), "A")
        context.draw(Text("I = \(label)").font(.system(size: 10.5, weight: .semibold, design: .rounded)).foregroundStyle(PMTheme.accent), at: p, anchor: anchor)
    }

    private static func drawMeshArrow(index: Int, loop: LoopPath, layout: SchematicLayout, camera: SchematicCamera, style: SchematicStyle, in context: inout GraphicsContext) {
        let polygon = layout.polygon(forLoopElements: loop.elementIds)
        guard polygon.count >= 3 else { return }
        let n = Double(polygon.count)
        let centroid = SPoint(x: polygon.map(\.x).reduce(0, +) / n, y: polygon.map(\.y).reduce(0, +) / n)
        var area = 0.0
        for i in polygon.indices {
            let p = polygon[i], q = polygon[(i + 1) % polygon.count]
            area += p.x * q.y - q.x * p.y
        }
        let clockwise = area > 0   // y grows downward, so positive shoelace area means clockwise on screen
        let bounds = SRect.around(polygon)
        let radius = min(max(min(bounds.width, bounds.height) * 0.16 * camera.scale, 10), 26)
        let center = camera.convert(centroid)
        let focused = style.focus.loops.isEmpty || style.focus.loops.contains(index)
        let color = focused ? PMTheme.accent : PMTheme.accent.opacity(0.35)

        var path = Path()
        let startAngle = -150.0 * .pi / 180
        let sweep = 300.0 * .pi / 180
        let steps = 40
        var last = CGPoint.zero
        var previous = CGPoint.zero
        for i in 0...steps {
            let fraction = Double(i) / Double(steps)
            let angle = CGFloat(clockwise ? startAngle + sweep * fraction : -startAngle - sweep * fraction)
            let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            previous = last
            last = point
        }
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        // Arrowhead along the tangent at the end of the arc.
        let dx = last.x - previous.x, dy = last.y - previous.y
        let len = max((dx * dx + dy * dy).squareRoot(), 0.001)
        let dir = CGPoint(x: dx / len, y: dy / len)
        let normal = CGPoint(x: -dir.y, y: dir.x)
        var head = Path()
        head.move(to: CGPoint(x: last.x + dir.x * 3, y: last.y + dir.y * 3))
        head.addLine(to: CGPoint(x: last.x - dir.x * 6 + normal.x * 5, y: last.y - dir.y * 6 + normal.y * 5))
        head.addLine(to: CGPoint(x: last.x - dir.x * 6 - normal.x * 5, y: last.y - dir.y * 6 - normal.y * 5))
        head.closeSubpath()
        context.fill(head, with: .color(color))

        var label = "I" + QuantityFormatter.subscriptDigits(String(index + 1))
        if let value = style.focus.meshCurrents[index] {
            label += " = " + style.formatter.format(value, "A")
        }
        context.draw(Text(label).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(color), at: center, anchor: .center)
    }
}
