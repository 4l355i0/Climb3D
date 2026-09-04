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
                        .showOverview()
                }

            case .changed:

                let dx =
                    translation.x -
                    lastPanTranslation.x

                let dy =
                    translation.y -
                    lastPanTranslation.y

                lastPanTranslation =
                    translation

                Task { @MainActor in
                    sceneController.rotateOverview(
                        deltaX: dx,
                        deltaY: dy
                    )
                }

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
                        .showOverview()
                }

            case .changed:

                let incrementalScale =
                    gesture.scale /
                    max(lastPinchScale, 0.001)

                lastPinchScale =
                    gesture.scale

                Task { @MainActor in
                    sceneController.zoomOverview(
                        scale: incrementalScale
                    )
                }

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
