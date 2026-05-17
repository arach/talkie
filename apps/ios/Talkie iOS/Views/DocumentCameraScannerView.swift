//
//  DocumentCameraScannerView.swift
//  Talkie iOS
//
//  Shared Apple document camera scanner wrapper.
//

import SwiftUI
import UIKit
import VisionKit

struct DocumentCameraScannerView: UIViewControllerRepresentable {
    static var isSupported: Bool {
        VNDocumentCameraViewController.isSupported
    }

    let onPageScanned: (UIImage, [URL]) -> Void
    let onFailure: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onPageScanned: onPageScanned,
            onFailure: onFailure,
            dismiss: dismiss.callAsFunction
        )
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onPageScanned: (UIImage, [URL]) -> Void
        let onFailure: (String) -> Void
        let dismiss: () -> Void

        init(
            onPageScanned: @escaping (UIImage, [URL]) -> Void,
            onFailure: @escaping (String) -> Void,
            dismiss: @escaping () -> Void
        ) {
            self.onPageScanned = onPageScanned
            self.onFailure = onFailure
            self.dismiss = dismiss
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            dismiss()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            onFailure(error.localizedDescription)
            dismiss()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            guard scan.pageCount > 0 else {
                onFailure("No pages were captured")
                dismiss()
                return
            }

            let firstPage = scan.imageOfPage(at: 0)
            var deferredURLs: [URL] = []

            if scan.pageCount > 1 {
                let tempDir = FileManager.default.temporaryDirectory
                    .appending(path: "talkie-scan-\(UUID().uuidString)", directoryHint: .isDirectory)
                try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

                for index in 1..<scan.pageCount {
                    autoreleasepool {
                        let page = scan.imageOfPage(at: index)
                        if let data = page.pngData() {
                            let url = tempDir.appending(path: "page-\(index).png")
                            try? data.write(to: url)
                            deferredURLs.append(url)
                        }
                    }
                }
            }

            onPageScanned(firstPage, deferredURLs)
            dismiss()
        }
    }
}
