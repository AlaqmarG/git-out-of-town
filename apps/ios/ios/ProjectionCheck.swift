import ARKit
import SceneKit
import SwiftUI

/// Do `ARCamera.projectPoint` and SceneKit's renderer agree on where a world
/// point lands on screen?
///
/// The placement path decides where paint sticks with the former
/// (`ProjectedDecal`, `DepthDecal`) and draws it with the latter. A constant
/// disagreement would offset every piece and every composited still by the same
/// amount, and nothing else in the app would notice. Debug-only; see
/// `docs/projection-check.md`.
@MainActor
enum ProjectionCheck {
    struct Sample {
        let label: String
        /// Both in the ARSCNView's own coordinate space: points, origin top-left.
        let arkit: CGPoint
        let scenekit: CGPoint
        var delta: CGFloat { hypot(arkit.x - scenekit.x, arkit.y - scenekit.y) }
    }

    struct Report {
        let samples: [Sample]
        let note: String
    }

    private static let markerName = "projcheck"

    /// Shared by every marker: one geometry, drawn through anything.
    private static let dot: SCNSphere = {
        let sphere = SCNSphere(radius: 0.004)
        sphere.firstMaterial?.lightingModel = .constant
        sphere.firstMaterial?.diffuse.contents = UIColor.cyan
        sphere.firstMaterial?.readsFromDepthBuffer = false
        sphere.firstMaterial?.writesToDepthBuffer = false
        return sphere
    }()

    static func run(in view: ARSCNView) -> Report? {
        guard let frame = view.session.currentFrame, let pov = view.pointOfView else { return nil }
        // What the placement path passes as `viewportSize:`. If the renderer's
        // own drawable ever disagrees with it, the note below says so.
        let viewport = view.bounds.size
        let scale = view.traitCollection.displayScale
        guard viewport.width > 0, viewport.height > 0, scale > 0 else { return nil }

        let camera = frame.camera
        // ARSCNView drives `pointOfView` straight off the frame's camera, so
        // while the two are in step this is literally the same matrix. Any
        // difference means we are straddling two frames and the gap we would
        // measure is camera motion, not disagreement — the exact false positive
        // this harness exists to rule out. Report no number rather than a lie,
        // and before doing the work that would produce it.
        let skew = maxDifference(pov.simdWorldTransform, camera.transform)
        guard skew < 1e-4 else {
            return Report(samples: [], note: String(format: "proj hold still · pose skew %.0e", skew))
        }

        let camPos = simd_make_float3(camera.transform.columns.3)
        let forward = -simd_make_float3(camera.transform.columns.2)
        let orientation = view.window?.windowScene?.effectiveGeometry.interfaceOrientation ?? .portrait

        let points = targets(in: view, camera: camera.transform)
        syncMarkers(points.map(\.1), in: view, camPos: camPos)

        var samples: [Sample] = []
        for (label, point) in points {
            // Behind the near plane `projectPoint` is meaningless: dividing by a
            // negative w mirrors the result through the origin.
            guard simd_dot(point - camPos, forward) > 0.05 else { continue }
            let arkit = camera.projectPoint(point, orientation: orientation, viewportSize: viewport)
            let scenekit = view.projectPoint(SCNVector3(point))
            guard arkit.x.isFinite, arkit.y.isFinite, scenekit.x.isFinite, scenekit.y.isFinite else { continue }
            samples.append(Sample(
                label: label,
                arkit: arkit,
                scenekit: CGPoint(x: CGFloat(scenekit.x), y: CGFloat(scenekit.y))
            ))
        }

        guard !samples.isEmpty else { return Report(samples: [], note: "proj no points in front of the camera") }

        let deltas = samples.map(\.delta)
        // The same comparison done in device pixels. If SceneKit ever hands back
        // pixels rather than points this is the small figure, and the gap is
        // units — a harness bug — rather than geometry.
        let asPixels = samples
            .map { hypot($0.arkit.x * scale - $0.scenekit.x, $0.arkit.y * scale - $0.scenekit.y) / scale }
            .reduce(0, +) / CGFloat(samples.count)
        var note = String(
            format: "proj Δ %.2f/%.2f px mean/max · n%d · %@ %.0f×%.0f · as-px %.2f",
            deltas.reduce(0, +) / CGFloat(deltas.count), deltas.max() ?? 0, samples.count,
            // The app is locked to portrait; anything else is the bug.
            orientation == .portrait ? "portrait" : "ROTATED",
            viewport.width, viewport.height, asPixels
        )
        let drawable = view.currentViewport.size
        if drawable.width > 0,
           abs(drawable.width - viewport.width * scale) > 1 || abs(drawable.height - viewport.height * scale) > 1 {
            note += String(format: " · drawable %.0f×%.0f", drawable.width, drawable.height)
        }
        return Report(samples: samples, note: note)
    }

    static func clearMarkers(in view: ARSCNView?) {
        view?.scene.rootNode.childNode(withName: markerName, recursively: false)?.removeFromParentNode()
    }

    // MARK: - Points to test

    private static func targets(in view: ARSCNView, camera: simd_float4x4) -> [(String, SIMD3<Float>)] {
        let pos = simd_make_float3(camera.columns.3)
        let right = simd_make_float3(camera.columns.0)
        let up = simd_make_float3(camera.columns.1)
        let forward = -simd_make_float3(camera.columns.2)
        // Spread across the frame as well as in depth: an error that is radial,
        // or shaped like a wrong orientation, only shows up away from the centre.
        let spread: [(Float, Float, Float)] = [(0.4, 0, 0), (1, 0.3, 0.2), (2.5, -0.3, -0.25), (6, 0.25, -0.3)]
        return spread.map { depth, x, y in
            (String(format: "%.1fm", depth), pos + forward * depth + right * (x * depth) + up * (y * depth))
        } + pieceCorners(in: view)
    }

    /// Corners and centre of the most recent piece in the scene — the points
    /// that actually carry the art, not just synthetic ones. Top-level children
    /// only: the recursive walk would drag in every LiDAR mesh node.
    private static func pieceCorners(in view: ARSCNView) -> [(String, SIMD3<Float>)] {
        guard let piece = view.scene.rootNode.childNodes.last(where: {
            $0.geometry != nil && $0.name != "occlusion"
        }) else { return [] }
        let (lo, hi) = piece.boundingBox
        let z = (lo.z + hi.z) / 2
        let corners: [(String, Float, Float)] = [
            ("tl", lo.x, hi.y), ("tr", hi.x, hi.y), ("bl", lo.x, lo.y), ("br", hi.x, lo.y),
            ("mid", (lo.x + hi.x) / 2, (lo.y + hi.y) / 2),
        ]
        return corners.map { label, x, y in
            (label, piece.simdConvertPosition(SIMD3<Float>(x, y, z), to: nil))
        }
    }

    /// A dot in the scene at every sampled point: whatever the renderer does
    /// with a world position it does to this node too, so it is the ground truth
    /// both crosshairs are read against.
    private static func syncMarkers(_ points: [SIMD3<Float>], in view: ARSCNView, camPos: SIMD3<Float>) {
        let container: SCNNode
        if let existing = view.scene.rootNode.childNode(withName: markerName, recursively: false) {
            container = existing
        } else {
            container = SCNNode()
            container.name = markerName
            view.scene.rootNode.addChildNode(container)
        }
        var markers = container.childNodes
        while markers.count > points.count { markers.removeLast().removeFromParentNode() }
        while markers.count < points.count {
            let node = SCNNode(geometry: dot)
            node.renderingOrder = 100
            container.addChildNode(node)
            markers.append(node)
        }
        for (node, point) in zip(markers, points) {
            node.simdPosition = point
            // Constant apparent size, so the 6 m marker is still findable.
            node.simdScale = SIMD3(repeating: max(simd_distance(point, camPos), 0.25))
        }
    }

    // MARK: -

    private static func maxDifference(_ a: simd_float4x4, _ b: simd_float4x4) -> Float {
        let d = a - b
        return (0..<4).reduce(Float(0)) { max($0, simd_abs(d[$1]).max()) }
    }

}

extension ARController {
    var projectionCheckView: ARSCNView? { coordinator?.scnView }
}

/// Crosshairs at both computed positions, so a disagreement is obvious and not
/// merely numeric: green is `ARCamera.projectPoint`, pink is SceneKit, and the
/// cyan dot they should both sit on is a real node at that world point.
struct ProjectionCheckOverlay: View {
    let controller: ARController

    @State private var samples: [ProjectionCheck.Sample] = []
    @State private var note = "proj warming up"

    var body: some View {
        Canvas { context, _ in
            for sample in samples {
                context.stroke(
                    Path { $0.move(to: sample.arkit); $0.addLine(to: sample.scenekit) },
                    with: .color(.yellow),
                    lineWidth: 1
                )
                cross(context, at: sample.arkit, color: .green)
                cross(context, at: sample.scenekit, color: .pink)
                context.draw(
                    Text(String(format: "%@ %.2f", sample.label, sample.delta))
                        .font(.system(size: 9, weight: .bold).monospaced())
                        .foregroundStyle(.yellow),
                    at: CGPoint(x: sample.arkit.x, y: sample.arkit.y - 17)
                )
            }
        }
        // The reading lives here rather than in the parent's debug pill: at
        // 4 Hz, writing it into ContentView's state would re-run the whole
        // camera screen — ARPaintView.updateUIView included — four times a
        // second, for one line of text.
        .overlay(alignment: .bottomLeading) {
            Text(note)
                .font(.caption2.monospaced())
                .foregroundStyle(.yellow)
                .padding(.horizontal, 10)
                .padding(.bottom, 210)
        }
        .task {
            while !Task.isCancelled {
                if let view = controller.projectionCheckView, let report = ProjectionCheck.run(in: view) {
                    // "hold still" carries no samples; leave the last crosshairs
                    // up rather than blinking them out every time you move.
                    if !report.samples.isEmpty { samples = report.samples }
                    note = report.note
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        .onDisappear {
            ProjectionCheck.clearMarkers(in: controller.projectionCheckView)
        }
    }

    private func cross(_ context: GraphicsContext, at point: CGPoint, color: Color) {
        let arm: CGFloat = 11
        context.stroke(
            Path {
                $0.move(to: CGPoint(x: point.x - arm, y: point.y))
                $0.addLine(to: CGPoint(x: point.x + arm, y: point.y))
                $0.move(to: CGPoint(x: point.x, y: point.y - arm))
                $0.addLine(to: CGPoint(x: point.x, y: point.y + arm))
            },
            with: .color(color),
            lineWidth: 1.5
        )
    }
}
