// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation
import SwiftUI
import Vision
import VisionKit

/// A QR scanner for reading custom device pairing codes.
@MainActor
public struct CodeScannerView: UIViewControllerRepresentable {
  @Binding public var isPresented: Bool
  public var completion: (String) -> Void

  /// Initializes a `CodeScannerView`.
  ///
  /// - Parameters:
  ///   - isPresented: A Boolean value that indicates whether the scanner is currently presented.
  ///   - completion: A closure to execute when a QR code is successfully scanned. The scanned
  ///     payload string is passed as a parameter.
  public init(isPresented: Binding<Bool>, completion: @escaping (String) -> Void) {
    _isPresented = isPresented
    self.completion = completion
  }

  /// Creates and returns a `DataScannerViewController`.
  ///
  /// - Parameters:
  ///   - context: The context for the view controller.
  public func makeUIViewController(context: Context) -> DataScannerViewController {
    let viewController = DataScannerViewController(
      recognizedDataTypes: [.barcode(symbologies: [.qr])],
      qualityLevel: .balanced,
      recognizesMultipleItems: false,
      isGuidanceEnabled: true,
      isHighlightingEnabled: true
    )
    viewController.delegate = context.coordinator
    return viewController
  }

  /// Updates the presented `DataScannerViewController`.
  ///
  /// - Parameters:
  ///   - uiViewController: The `DataScannerViewController` to update.
  ///   - context: The context for the view controller.
  public func updateUIViewController(
    _ uiViewController: DataScannerViewController, context: Context
  ) {
    if isPresented {
      try? uiViewController.startScanning()
    } else {
      uiViewController.stopScanning()
    }
  }

  /// Creates a `Coordinator` for the `DataScannerViewController`.
  public func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  public class Coordinator: NSObject, DataScannerViewControllerDelegate {
    private var parent: CodeScannerView

    init(_ parent: CodeScannerView) {
      self.parent = parent
    }

    // MARK: - DataScannerViewControllerDelegate

    /// Tells the delegate that the scanner added new recognized items.
    ///
    /// - Parameters:
    ///   - dataScanner: The data scanner view controller.
    ///   - addedItems: An array of `RecognizedItem` objects that were added.
    ///   - allItems: An array of all currently recognized `RecognizedItem` objects.
    public func dataScanner(
      _ dataScanner: DataScannerViewController,
      didAdd addedItems: [RecognizedItem],
      allItems: [RecognizedItem]
    ) {
      guard let item = allItems.first, case .barcode(let barcode) = item else { return }
      if let payload = barcode.payloadStringValue {
        // Call the completion handler with the scanned QR code payload.
        parent.completion(payload)
        // Dismiss the scanner view.
        parent.isPresented = false
      }
    }
  }
}
