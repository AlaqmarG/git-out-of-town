import ARKit

/// Apple's coaching overlay: localized, animated tracking guidance, plus the
/// "Start Over" button that is the only way out of a relocalization that never
/// matches. It owns the guidance while it is up — our own scanning copy is
/// suppressed via `ARController.isCoaching`.
final class CoachingOverlay: NSObject, ARCoachingOverlayViewDelegate {
    private let view = PassthroughCoachingOverlayView()
    private let onActive: (Bool) -> Void
    private let onReset: () -> Void

    /// `.tracking` while relocalizing against a downloaded world map — the only
    /// goal that coaches the user back to a viewpoint the scan can match — and
    /// `.anyPlane` otherwise, because paint lands on walls and floors alike and
    /// the session detects both.
    var goal: ARCoachingOverlayView.Goal {
        get { view.goal }
        set { if view.goal != newValue { view.goal = newValue } }
    }

    init(
        session: ARSession,
        in container: UIView,
        onActive: @escaping (Bool) -> Void,
        onReset: @escaping () -> Void
    ) {
        self.onActive = onActive
        self.onReset = onReset
        super.init()
        view.session = session
        view.delegate = self
        view.goal = .anyPlane
        view.activatesAutomatically = true
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    nonisolated func coachingOverlayViewWillActivate(_ coachingOverlayView: ARCoachingOverlayView) {
        Task { @MainActor [weak self] in self?.onActive(true) }
    }

    nonisolated func coachingOverlayViewDidDeactivate(_ coachingOverlayView: ARCoachingOverlayView) {
        Task { @MainActor [weak self] in self?.onActive(false) }
    }

    /// Implementing this replaces Apple's default reset, which reruns the
    /// session and nothing else — leaving our relocalization bookkeeping and
    /// every placed node pointing at a world origin that no longer exists.
    nonisolated func coachingOverlayViewDidRequestSessionReset(_ coachingOverlayView: ARCoachingOverlayView) {
        Task { @MainActor [weak self] in self?.onReset() }
    }
}

/// The overlay is a full-screen sibling of the camera for the whole session,
/// visible or not. Anything that isn't one of its own controls has to fall
/// through, or it quietly eats every touch aimed at what's underneath.
private final class PassthroughCoachingOverlayView: ARCoachingOverlayView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}
