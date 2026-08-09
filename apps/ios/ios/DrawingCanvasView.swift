import PencilKit
import SwiftUI

struct DrawingCanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var clearToken: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawing = drawing
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.delegate = context.coordinator
        // Near-black ink disappears against most walls; open on a colour that
        // always reads, and let the tool picker take it from there.
        canvas.tool = PKInkingTool(.marker, color: UIColor(red: 1, green: 0, blue: 0.45, alpha: 1), width: 18)

        let toolPicker = PKToolPicker()
        context.coordinator.toolPicker = toolPicker
        context.coordinator.lastClearToken = clearToken
        toolPicker.addObserver(canvas)
        DispatchQueue.main.async {
            canvas.becomeFirstResponder()
            toolPicker.setVisible(true, forFirstResponder: canvas)
        }

        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        if clearToken != context.coordinator.lastClearToken {
            context.coordinator.lastClearToken = clearToken
            uiView.drawing = PKDrawing()
            drawing = PKDrawing()
        }
    }

    static func dismantleUIView(_ uiView: PKCanvasView, coordinator: Coordinator) {
        coordinator.toolPicker?.setVisible(false, forFirstResponder: uiView)
        coordinator.toolPicker?.removeObserver(uiView)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: DrawingCanvasView
        var toolPicker: PKToolPicker?
        var lastClearToken = 0

        init(_ parent: DrawingCanvasView) {
            self.parent = parent
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
        }
    }
}
