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

import CoreFoundation
import Foundation
import GoogleHomeSDK
import OSLog
import SwiftUI

private let logger = Logger(
  subsystem: "com.google.HomePlatform", category: "WebPImageView")

/// A SwiftUI representable UIKit view that downloads, decodes, and animates WebP preview clips.
///
/// In Google Home Platform (GHP), camera `preview_url` endpoints deliver animated WebP media streams
/// requiring OAuth Bearer authorization (`Authorization: Bearer <accessToken>`).
///
/// **Implementation Note for Partners**:
/// - Image decoding is offloaded from the `@MainActor` via a `nonisolated async` helper to prevent
///   blocking the main UI thread during intensive multi-frame decompression while preserving cooperative cancellation.
/// - The `Coordinator` maintains `loadedURL` state to avoid redundant re-downloads during view re-renders.
/// - `dismantleUIView` cancels in-flight tasks and clears image buffers when views scroll off-screen.
struct WebPImageView: UIViewRepresentable {
  let url: URL
  let urlSession: URLSession
  let home: Home

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  /// Coordinator tracking task lifecycle and URL state to prevent duplicate downloads and resource leaks.
  class Coordinator {
    var loadedURL: URL?
    var task: Task<Void, Never>?

    deinit {
      task?.cancel()
    }
  }

  /// Creates the underlying UIKit `UIImageView`.
  func makeUIView(context: Context) -> UIImageView {
    let imageView = UIImageView()
    imageView.contentMode = .scaleAspectFill
    imageView.clipsToBounds = true

    imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
    imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
    imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return imageView
  }

  /// Function called by SwiftUI to update the UIKit view.
  func updateUIView(_ uiView: UIImageView, context: Context) {
    if context.coordinator.loadedURL == self.url {
      return
    }
    context.coordinator.loadedURL = self.url
    context.coordinator.task?.cancel()
    uiView.stopAnimating()
    uiView.animationImages = nil
    uiView.image = nil

    context.coordinator.task = Task {
      do {
        let auth = try await self.home.permissions.authorization()
        guard !Task.isCancelled else { return }

        var request = URLRequest(url: self.url)
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await self.urlSession.data(for: request)
        guard !Task.isCancelled else { return }

        guard let httpResponse = response as? HTTPURLResponse else {
          logger.error("WebPImageView: Non-HTTP response received for \(self.url.absoluteString, privacy: .public)")
          return
        }

        guard httpResponse.statusCode == 200 else {
          logger.error("WebPImageView: HTTP request failed with status \(httpResponse.statusCode) for \(self.url.absoluteString, privacy: .public)")
          return
        }

        let (decodedImages, totalDuration) = await Self.decodeWebP(from: data)
        guard let images = decodedImages else {
          if !Task.isCancelled {
            logger.error("WebPImageView: Failed to create image source for \(self.url.absoluteString, privacy: .public)")
          }
          return
        }

        guard !Task.isCancelled else { return }

        uiView.animationImages = images
        uiView.animationDuration = totalDuration
        uiView.startAnimating()
      } catch {
        if !Task.isCancelled {
          logger.error("WebPImageView: Failed to load WebP image from \(self.url.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
      }
    }
  }

  /// Decodes animated WebP image data into an array of frames and calculates total animation duration.
  /// This method is `nonisolated` to execute off the `@MainActor` without blocking the main UI thread,
  /// while maintaining cooperative cancellation inheritance from the calling `Task`.
  private static func decodeWebP(from data: Data) async -> ([UIImage]?, TimeInterval) {
    guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
      return (nil, 0)
    }

    let frameCount = CGImageSourceGetCount(imageSource)
    var images: [UIImage] = []
    var totalDuration: TimeInterval = 0

    // Iterate through each frame of the animated WebP to build the animation sequence.
    for frameIndex in 0..<frameCount {
      guard !Task.isCancelled else { return (nil, 0) }
      guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, frameIndex, nil) else {
        continue
      }
      images.append(UIImage(cgImage: cgImage))

      // Extract metadata properties to find the specific delay time for this frame.
      let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, frameIndex, nil) as? [CFString: Any]
      let webPProperties = properties?[kCGImagePropertyWebPDictionary] as? [CFString: Any]
      let unclampedDelayTime = webPProperties?[kCGImagePropertyWebPUnclampedDelayTime] as? TimeInterval

      // Add this frame's delay to the total animation duration (defaulting to 0.1s).
      totalDuration += unclampedDelayTime ?? 0.1
    }

    return (images, totalDuration)
  }

  static func dismantleUIView(_ uiView: UIImageView, coordinator: Coordinator) {
    coordinator.task?.cancel()
    uiView.stopAnimating()
    uiView.animationImages = nil
    uiView.image = nil
  }
}
