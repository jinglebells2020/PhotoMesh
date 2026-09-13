import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// UIKit gesture layer for the drawing canvas: one finger draws immediately, two fingers pan,
/// pinch zooms, single tap selects, double tap rotates.
struct SketchGestureHost: UIViewRepresentable {
    var onStrokeBegan: (CGPoint) -> Void
    var onStrokeMoved: (CGPoint) -> Void
    var onStrokeEnded: (_ cancelled: Bool) -> Void
    var onTap: (CGPoint) -> Void
    var onDoubleTap: (CGPoint) -> Void
    var onPan: (_ translation: CGSize, _ state: UIGestureRecognizer.State) -> Void
    var onPinch: (_ scale: CGFloat, _ location: CGPoint, _ state: UIGestureRecognizer.State) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true

        let draw = DrawGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDraw(_:)))
        draw.delegate = context.coordinator

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        pan.delegate = context.coordinator

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinch.delegate = context.coordinator

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = context.coordinator

        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)
        singleTap.delegate = context.coordinator

        for recognizer in [draw, pan, pinch, doubleTap, singleTap] { view.addGestureRecognizer(recognizer) }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: SketchGestureHost

        init(parent: SketchGestureHost) { self.parent = parent }

        @objc func handleDraw(_ recognizer: DrawGestureRecognizer) {
            let point = recognizer.location(in: recognizer.view)
            switch recognizer.state {
            case .began:
                parent.onStrokeBegan(recognizer.startPoint)
                parent.onStrokeMoved(point)
            case .changed:
                parent.onStrokeMoved(point)
            case .ended:
                parent.onStrokeMoved(point)
                parent.onStrokeEnded(false)
            case .cancelled, .failed:
                parent.onStrokeEnded(true)
            default:
                break
            }
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            let translation = recognizer.translation(in: recognizer.view)
            parent.onPan(CGSize(width: translation.x, height: translation.y), recognizer.state)
        }

        @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            parent.onPinch(recognizer.scale, recognizer.location(in: recognizer.view), recognizer.state)
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            parent.onTap(recognizer.location(in: recognizer.view))
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            parent.onDoubleTap(recognizer.location(in: recognizer.view))
        }

        /// Our own recognizers cooperate (draw cancels itself when a second finger lands; pan and
        /// pinch run together). Anything attached elsewhere, above all the sheet's swipe-to-dismiss
        /// pan, must not run alongside a drawing stroke.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            otherGestureRecognizer.view === gestureRecognizer.view
        }

        /// Outside pans (the sheet dismissal, ancestor scroll views) wait until our drawing, panning
        /// or pinching has failed. Drawing begins after 4 pt of movement, so the sheet never moves
        /// while a stroke is in progress.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            guard otherGestureRecognizer.view !== gestureRecognizer.view else { return false }
            return otherGestureRecognizer is UIPanGestureRecognizer || otherGestureRecognizer is UIScreenEdgePanGestureRecognizer
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            false
        }
    }
}

/// Pan that begins after a few points of movement with a single finger and gives up as soon
/// as a second finger lands, so pinch and two-finger pan can take over.
final class DrawGestureRecognizer: UIGestureRecognizer {
    private(set) var startPoint: CGPoint = .zero
    private let slop: CGFloat = 4

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        if (event.allTouches?.count ?? touches.count) > 1 {
            state = state == .possible ? .failed : .cancelled
            return
        }
        if let touch = touches.first, let view { startPoint = touch.location(in: view) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        if (event.allTouches?.count ?? touches.count) > 1 {
            state = state == .possible ? .failed : .cancelled
            return
        }
        guard let touch = touches.first, let view else { return }
        let point = touch.location(in: view)
        if state == .possible {
            if hypot(point.x - startPoint.x, point.y - startPoint.y) >= slop { state = .began }
        } else {
            state = .changed
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        state = state == .possible ? .failed : .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        state = state == .possible ? .failed : .cancelled
    }
}
