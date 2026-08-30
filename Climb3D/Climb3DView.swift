import SwiftUI
import SceneKit

struct Climb3DView: UIViewRepresentable {

    let sceneController: Climb3DSceneController
    let progress: Double

    func makeCoordinator() -> Coordinator {
        Coordinator(
            sceneController: sceneController
        )
    }

    func makeUIView(
        context: Context
    ) -> SCNView {

        let view = SCNView()

        view.scene =
            sceneController.scene

        view.backgroundColor =
            .systemBackground

        /*
         We manage gestures ourselves.
        */
        view.allowsCameraControl = false

        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X
        view.isPlaying = true

        // One finger = orbit
        let pan =
            UIPanGestureRecognizer(
                target: context.coordinator,
                action:
                    #selector(
                        Coordinator.handlePan(_:)
                    )
            )

        pan.maximumNumberOfTouches = 1

        view.addGestureRecognizer(
            pan
        )

        // Pinch = zoom
        let pinch =
            UIPinchGestureRecognizer(
                target: context.coordinator,
                action:
                    #selector(
                        Coordinator.handlePinch(_:)
                    )
            )

        view.addGestureRecognizer(
            pinch
        )

        /*
         Double tap = centre / zoom on rider.
         Reset button remains the full-route view.
        */
        let doubleTap =
            UITapGestureRecognizer(
                target: context.coordinator,
                action:
                    #selector(
                        Coordinator.handleDoubleTap(_:)
                    )
            )

        doubleTap.numberOfTapsRequired = 2

        view.addGestureRecognizer(
            doubleTap
        )

        sceneController.attach(
            to: view
        )

        sceneController.updateProgress(
            progress
        )

        return view
    }

    func updateUIView(
        _ uiView: SCNView,
        context: Context
    ) {

        if uiView.scene !==
            sceneController.scene {

            uiView.scene =
                sceneController.scene
        }

        sceneController.updateProgress(
            progress
        )
    }

    final class Coordinator: NSObject {

        let sceneController:
            Climb3DSceneController

        init(
            sceneController:
                Climb3DSceneController
        ) {
            self.sceneController =
                sceneController
        }

        @objc
        func handlePan(
            _ gesture:
                UIPanGestureRecognizer
        ) {

            let translation =
                gesture.translation(
                    in: gesture.view
                )

            Task { @MainActor in

                sceneController.orbit(
                    deltaX:
                        translation.x,
                    deltaY:
                        translation.y
                )
            }

            gesture.setTranslation(
                .zero,
                in: gesture.view
            )
        }

        @objc
        func handlePinch(
            _ gesture:
                UIPinchGestureRecognizer
        ) {

            let scale =
                gesture.scale

            guard scale > 0 else {
                return
            }

            Task { @MainActor in

                sceneController.zoom(
                    scale: scale
                )
            }

            gesture.scale = 1
        }

        @objc
        func handleDoubleTap(
            _ gesture:
                UITapGestureRecognizer
        ) {

            Task { @MainActor in

                sceneController
                    .focusOnMarker()
            }
        }
    }
}
