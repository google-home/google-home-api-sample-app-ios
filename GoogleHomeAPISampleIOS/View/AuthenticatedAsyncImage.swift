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

import SwiftUI
import GoogleHomeSDK
import OSLog

private let logger = Logger(
  subsystem: "com.google.HomePlatform", category: "AuthenticatedAsyncImage")

/// Represents the loading phase of an `AuthenticatedAsyncImage`.
public enum AuthenticatedAsyncImagePhase {
  // No image is loaded.
  case empty
  // An image was successfully loaded and decoded.
  case success(Image)
  // An error occurred while loading or decoding the image.
  case failure(Error)
  // The loaded image, if any.
  public var image: Image? {
    if case .success(let image) = self {
      return image
    }
    return nil
  }
  // The error encountered while loading, if any.
  public var error: Error? {
    if case .failure(let error) = self {
      return error
    }
    return nil
  }
}

/// A view that asynchronously loads and displays an image requiring Google Home OAuth authorization.
///
/// Standard SwiftUI `AsyncImage` does not support custom HTTP headers. This view handles token retrieval
/// via the `Home` instance and constructs an authenticated `URLRequest` to access protected media assets
/// like camera thumbnails.
public struct AuthenticatedAsyncImage<Content: View>: View {
  private let url: URL
  private let home: Home?
  private let urlSession: URLSession
  private let content: (AuthenticatedAsyncImagePhase) -> Content
  @State private var phase: AuthenticatedAsyncImagePhase = .empty

  /// Initializes an `AuthenticatedAsyncImage`.
  /// - Parameters:
  ///   - url: The target image URL.
  ///   - home: The `Home` instance used to fetch the OAuth access token.
  ///   - urlSession: The `URLSession` used to fetch image data. Defaults to `.shared`.
  ///   - content: A closure that returns a view for the given loading phase.
  public init(
    url: URL,
    home: Home?,
    urlSession: URLSession = .shared,
    @ViewBuilder content: @escaping (AuthenticatedAsyncImagePhase) -> Content
  ) {
    self.url = url
    self.home = home
    self.urlSession = urlSession
    self.content = content
  }

  public var body: some View {
    content(phase)
      .task(id: url) {
        await loadImage()
      }
  }

  @MainActor
  private func loadImage() async {
    self.phase = .empty
    do {
      var request = URLRequest(url: url)
      if let home = home {
        let auth = try await home.permissions.authorization()
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
      }
      let (data, response) = try await self.urlSession.data(for: request)
      guard !Task.isCancelled else { return }

      guard let httpResponse = response as? HTTPURLResponse else {
        logger.error("Non-HTTP response received for \(self.url.absoluteString, privacy: .public)")
        throw URLError(.badServerResponse)
      }

      guard httpResponse.statusCode == 200 else {
        logger.error("HTTP request failed with status \(httpResponse.statusCode) for \(self.url.absoluteString, privacy: .public)")
        throw URLError(.badServerResponse)
      }
      if let uiImage = UIImage(data: data) {
        self.phase = .success(Image(uiImage: uiImage))
      } else {
        logger.error("Failed to decode image data (\(data.count) bytes) for \(self.url.absoluteString, privacy: .public)")
        throw URLError(.cannotDecodeRawData)
      }
    } catch {
      guard !Task.isCancelled, !(error is CancellationError), (error as? URLError)?.code != .cancelled else {
        return
      }
      logger.error("Error loading image from \(self.url.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
      self.phase = .failure(error)
    }
  }
}
