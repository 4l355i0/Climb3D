import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ContentView: View {
    @EnvironmentObject private var model: Climb3DModel
    @State private var showGPXImporter = false
    @State private var showShare = false
    @State private var exportedURL: URL?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(model.hasMesh ? .green : .orange)
                        .frame(width: 8, height: 8)

                    Text(model.status)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)

                    Spacer()

                    if model.hasGPX {
                        Text("GPX")
                            .font(.caption2.bold())
                            .foregroundStyle(.green)
                    }

                    if model.hasMesh {
                        Text("3D")
                            .font(.caption2.bold())
                            .foregroundStyle(.green)
                    }
                }

                Climb3DView(
                    sceneController: model.sceneController,
                    progress: model.progress
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(.secondary.opacity(0.18))
                )

                VStack(spacing: 6) {
                    HStack {
                        Text("Progress")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text("\(Int((model.progress * 100).rounded()))%")
                            .font(.headline.monospacedDigit())
                    }

                    Slider(value: $model.progress, in: 0...1)
                        .disabled(!model.hasMesh)
                }
                .padding(12)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))

                HStack(spacing: 10) {
                    Button {
                        showGPXImporter = true
                    } label: {
                        Label(
                            "Load GPX",
                            systemImage: "point.topleft.down.to.point.bottomright.curvepath"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        do {
                            exportedURL = try model.exportSTL()
                            showShare = true
                        } catch {
                            model.status = "STL export error: \(error.localizedDescription)"
                        }
                    } label: {
                        Label(
                            "Export STL",
                            systemImage: "square.and.arrow.up"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!model.hasMesh)
                }

                Button {
                    model.resetCamera()
                } label: {
                    Label("Reset 3D view", systemImage: "view.3d")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!model.hasMesh)
            }
            .padding(12)
            .navigationTitle("Climb3D")
            .navigationBarTitleDisplayMode(.inline)
        }
        .fileImporter(
            isPresented: $showGPXImporter,
            allowedContentTypes: [
                UTType(filenameExtension: "gpx") ?? .xml
            ],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result,
                  let url = urls.first else { return }

            do {
                try model.loadGPXAndBuild3D(url: url)
            } catch {
                model.status = "GPX error: \(error.localizedDescription)"
            }
        }
        .sheet(isPresented: $showShare) {
            if let exportedURL {
                ShareSheet(items: [exportedURL])
            }
        }
    }
}


// MARK: - iOS Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {
        // No update required
    }
}
