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

        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X
        view.isPlaying = true

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

        private var lastPanTranslation =
            CGPoint.zero

        private var lastPinchScale:
            CGFloat = 1

        init(
            sceneController:
                Climb3DSceneController
        ) {

            self.sceneController =
                sceneController
        }

        // MARK: - Pan

        @objc
        func handlePan(
            _ gesture:
                UIPanGestureRecognizer
        ) {

            let translation =
                gesture.translation(
                    in: gesture.view
                )

            switch gesture.state {

            case .began:

                lastPanTranslation =
                    translation

                Task { @MainActor in
                    sceneController
                        .disableFollowMode()
                }

            case .changed:

                /*
                 Manual camera interaction is currently
                 disabled once Follow is released.

                 We leave the camera where it is instead
                 of fighting with the automatic controller.
                */

                lastPanTranslation =
                    translation

            case .ended,
                 .cancelled,
                 .failed:

                lastPanTranslation =
                    .zero

            default:
                break
            }
        }

        // MARK: - Pinch

        @objc
        func handlePinch(
            _ gesture:
                UIPinchGestureRecognizer
        ) {

            switch gesture.state {

            case .began:

                lastPinchScale =
                    gesture.scale

                Task { @MainActor in
                    sceneController
                        .disableFollowMode()
                }

            case .changed:

                /*
                 Follow mode is paused.
                 We don't alter the follow camera here.
                 Manual zoom can be added separately later.
                */

                lastPinchScale =
                    gesture.scale

            case .ended,
                 .cancelled,
                 .failed:

                lastPinchScale = 1

            default:
                break
            }
        }

        // MARK: - Double tap

        @objc
        func handleDoubleTap(
            _ gesture:
                UITapGestureRecognizer
        ) {

            Task { @MainActor in

                sceneController
                    .enableFollowMode()
            }
        }
    }
}
