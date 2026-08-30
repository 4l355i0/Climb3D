import SwiftUI
import SceneKit

struct Climb3DView: UIViewRepresentable {
    let sceneController: Climb3DSceneController
    let progress: Double

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = sceneController.scene
        view.backgroundColor = .systemBackground
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X
        view.isPlaying = true

        sceneController.attach(to: view)
        sceneController.updateProgress(progress)

        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        if uiView.scene !== sceneController.scene {
            uiView.scene = sceneController.scene
        }

        sceneController.updateProgress(progress)
    }
}
