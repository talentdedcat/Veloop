import AppKit
import QuartzCore

struct DepthPushAnimationSpecification: Equatable {
    let duration: TimeInterval
    let incomingOffset: CGFloat
    let outgoingOffset: CGFloat
    let incomingScale: CGFloat
    let tabRevealDelay: TimeInterval
}

final class DepthPushAnimator {
    private weak var container: NSView?
    private weak var currentView: NSView?
    private weak var outgoingView: NSView?
    private var generation: UInt64 = 0

    init(container: NSView) {
        self.container = container
        container.wantsLayer = true
    }

    static func specification(
        direction: PasteCycleDirection,
        reduceMotion: Bool
    ) -> DepthPushAnimationSpecification {
        guard !reduceMotion else {
            return DepthPushAnimationSpecification(
                duration: 0.10,
                incomingOffset: 0,
                outgoingOffset: 0,
                incomingScale: 1,
                tabRevealDelay: 0
            )
        }
        let sign: CGFloat = direction == .older ? 1 : -1
        return DepthPushAnimationSpecification(
            duration: 0.18,
            incomingOffset: 20 * sign,
            outgoingOffset: -12 * sign,
            incomingScale: 0.97,
            tabRevealDelay: 0.13
        )
    }

    func install(_ view: NSView) {
        cancel()
        guard let container else { return }
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        view.wantsLayer = true
        container.addSubview(view)
        currentView = view
    }

    func transition(
        to incoming: NSView,
        direction: PasteCycleDirection,
        reduceMotion: Bool
    ) {
        guard let container else { return }
        guard let currentView else {
            install(incoming)
            return
        }

        generation &+= 1
        let currentGeneration = generation
        outgoingView?.removeFromSuperview()
        freezePresentation(of: currentView)
        outgoingView = currentView

        incoming.frame = container.bounds
        incoming.autoresizingMask = [.width, .height]
        incoming.wantsLayer = true
        container.addSubview(incoming, positioned: .above, relativeTo: currentView)
        self.currentView = incoming

        guard let incomingLayer = incoming.layer, let outgoingLayer = currentView.layer else {
            currentView.removeFromSuperview()
            return
        }
        let spec = Self.specification(direction: direction, reduceMotion: reduceMotion)
        let incomingStart = Self.transform(offset: spec.incomingOffset, scale: spec.incomingScale)
        let outgoingEnd = Self.transform(offset: spec.outgoingOffset, scale: reduceMotion ? 1 : 1.015)
        let outgoingStartTransform = outgoingLayer.transform
        let outgoingStartOpacity = outgoingLayer.opacity

        incomingLayer.transform = CATransform3DIdentity
        incomingLayer.opacity = 1
        outgoingLayer.transform = outgoingEnd
        outgoingLayer.opacity = 0

        let timing = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
        incomingLayer.add(group(
            duration: spec.duration,
            timing: timing,
            opacityFrom: 0,
            opacityTo: 1,
            transformFrom: incomingStart,
            transformTo: CATransform3DIdentity
        ), forKey: "veloop.incoming")
        (incoming as? FocusStackFrameView)?.animateTabsIn(
            after: spec.tabRevealDelay,
            duration: min(0.05, spec.duration)
        )
        outgoingLayer.add(group(
            duration: spec.duration,
            timing: timing,
            opacityFrom: outgoingStartOpacity,
            opacityTo: 0,
            transformFrom: outgoingStartTransform,
            transformTo: outgoingEnd
        ), forKey: "veloop.outgoing")

        DispatchQueue.main.asyncAfter(deadline: .now() + spec.duration) { [weak self, weak currentView] in
            guard let self, self.generation == currentGeneration else { return }
            currentView?.removeFromSuperview()
            self.outgoingView = nil
        }
    }

    func cancel() {
        generation &+= 1
        outgoingView?.removeFromSuperview()
        outgoingView = nil
        currentView?.layer?.removeAllAnimations()
        currentView?.removeFromSuperview()
        currentView = nil
    }

    private func freezePresentation(of view: NSView) {
        guard let layer = view.layer else { return }
        if let presentation = layer.presentation() {
            layer.transform = presentation.transform
            layer.opacity = presentation.opacity
        }
        layer.removeAllAnimations()
    }

    static func transform(offset: CGFloat, scale: CGFloat) -> CATransform3D {
        CATransform3DScale(CATransform3DMakeTranslation(0, offset, 0), scale, scale, 1)
    }

    private func group(
        duration: TimeInterval,
        timing: CAMediaTimingFunction,
        opacityFrom: Float,
        opacityTo: Float,
        transformFrom: CATransform3D,
        transformTo: CATransform3D
    ) -> CAAnimationGroup {
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = opacityFrom
        opacity.toValue = opacityTo
        let transform = CABasicAnimation(keyPath: "transform")
        transform.fromValue = NSValue(caTransform3D: transformFrom)
        transform.toValue = NSValue(caTransform3D: transformTo)
        let animation = CAAnimationGroup()
        animation.animations = [opacity, transform]
        animation.duration = duration
        animation.timingFunction = timing
        return animation
    }
}
