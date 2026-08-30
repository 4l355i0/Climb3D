import SwiftUI
import SceneKit

struct Climb3DView: UIViewRepresentable {
    let sceneController: Climb3DSceneController
    let progress: Double

    func makeCoordinator() -> Coordinator {
        Coordinator(sceneController: sceneController)
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()

        view.scene = sceneController.scene
        view.backgroundColor = .systemBackground
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X
        view.isPlaying = true

        view.defaultCameraController.inertiaEnabled = true
        view.defaultCameraController.interactionMode = .orbitTurntable

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap)
        )

        doubleTap.numberOfTapsRequired = 2

        view.addGestureRecognizer(doubleTap)

        sceneController.attach(to: view)
        sceneController.updateProgress(progress)

        return view
    }

    func updateUIView(
        _ uiView: SCNView,
        context: Context
    ) {
        if uiView.scene !== sceneController.scene {
            uiView.scene = sceneController.scene
        }

        sceneController.updateProgress(progress)
    }

    final class Coordinator: NSObject {
        let sceneController: Climb3DSceneController

        init(
            sceneController: Climb3DSceneController
        ) {
            self.sceneController = sceneController
        }

        @objc
        func handleDoubleTap() {
            Task { @MainActor in
                sceneController.resetCamera()
            }
        }
    }
}
