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

/// A UIKit view that displays an animated WebP image.
///
/// This view will download the provided WebP image, decode it into individual frames, and display
/// them as a UIImageView animation.
struct WebPImageView: UIViewRepresentable {
  let url: URL
  let urlSession: URLSession

  /// Function called by SwiftUI to create the UIKit view.
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
    Task {
      let (data, _) = try await self.urlSession.data(from: self.url)

      guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
        return
      }

      let frameCount = CGImageSourceGetCount(imageSource)

      var images: [UIImage] = []
      var totalDuration: TimeInterval = 0

      // Iterate through each frame of the animated WebP to build the animation sequence.
      for frameIndex in 0..<frameCount {
        guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, frameIndex, nil) else {
          continue
        }
        images.append(UIImage(cgImage: cgImage))

        // Extract metadata properties to find the specific delay time for this frame.
        let properties =
          CGImageSourceCopyPropertiesAtIndex(imageSource, frameIndex, nil) as? [CFString: Any]
        let webPProperties = properties?[kCGImagePropertyWebPDictionary] as? [CFString: Any]
        let unclampedDelayTime =
          webPProperties?[kCGImagePropertyWebPUnclampedDelayTime] as? TimeInterval

        // Add this frame's delay to the total animation duration (defaulting to 0.1s).
        totalDuration += unclampedDelayTime ?? 0.1
      }

      Task { @MainActor in
        uiView.animationImages = images
        uiView.animationDuration = totalDuration
        uiView.startAnimating()
      }
    }
  }
}
