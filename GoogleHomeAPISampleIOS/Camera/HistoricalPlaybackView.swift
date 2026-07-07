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

import AVFoundation
import AVKit
import Combine
import Foundation
import SwiftUI
import OSLog
import GoogleHomeSDK

public struct HistoricalPlaybackView: View {

  private let url: URL
  private let home: Home?
  private let headers: [String: String]?
  private let onTimeChanged: ((TimeInterval) -> Void)?
  @State private var player: AVPlayer
  @State private var aspectRatio: CGFloat
  @State private var assetHandler: HistoricalPlaybackAsset?
  @State private var timeObserverToken: Any?

  private static let playbackUpdateInterval: TimeInterval = 0.5

  public init(
    url: URL, home: Home? = nil, headers: [String: String]? = nil, aspectRatio: CGFloat = 1.77,
    onTimeChanged: ((TimeInterval) -> Void)? = nil
  ) {
    Logger().info(">>> HistoricalPlaybackView init with url: \(url)")
    self.url = url
    self.home = home
    self.headers = headers
    self.onTimeChanged = onTimeChanged
    self._player = State(initialValue: AVPlayer())
    self._aspectRatio = State(initialValue: aspectRatio)
  }

  public var body: some View {
    VideoPlayer(player: player)
      .aspectRatio(aspectRatio, contentMode: .fit)
      .onReceive(player.publisher(for: \.currentItem?.presentationSize)) { size in
        guard let size, size.width > 0 && size.height > 0 else { return }
        let newAspectRatio = size.width / size.height
        if abs(self.aspectRatio - newAspectRatio) > 0.01 {
          self.aspectRatio = newAspectRatio
          Logger().info(">>> HistoricalPlaybackView updated aspect ratio to: \(newAspectRatio)")
        }
      }
      .onAppear {
        Logger().info(">>> VideoPlayer onAppear")
        player.play()
        addTimeObserver()
      }
      .onDisappear {
        Logger().info(">>> VideoPlayer onDisappear")
        player.pause()
        player.replaceCurrentItem(with: nil)
        self.assetHandler = nil
        removeTimeObserver()
      }
      .task(id: url) {
        await setupPlayer()
      }
      .onReceive(player.publisher(for: \.status)) { status in
        Logger().info(">>> Player status: \(status.rawValue)")
        if status == .failed {
          Logger().error(
            ">>> Player failed with error: \(player.error?.localizedDescription ?? "nil")")
        }
      }
      .onReceive(player.publisher(for: \.currentItem?.status)) { status in
        Logger().info(">>> Current item status: \(status?.rawValue ?? -1)")
        if status == .failed {
          Logger().error(
            ">>> Item failed with error: \(player.currentItem?.error?.localizedDescription ?? "nil")"
          )
        }
      }
  }

  private func addTimeObserver() {
    guard timeObserverToken == nil else { return }
    let interval = CMTime(
      seconds: Self.playbackUpdateInterval, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
    timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) {
      time in
      onTimeChanged?(time.seconds)
    }
  }

  private func removeTimeObserver() {
    if let token = timeObserverToken {
      player.removeTimeObserver(token)
      timeObserverToken = nil
    }
  }

  private func setupPlayer() async {
    Logger().info(">>> setupPlayer for url: \(url)")

    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
      try AVAudioSession.sharedInstance().setActive(true)
      Logger().info(">>> Successfully configured AVAudioSession to .playback")
    } catch {
      Logger().error(">>> Failed to set AVAudioSession category: \(error.localizedDescription)")
    }

    player.pause()
    player.replaceCurrentItem(with: nil)
    self.assetHandler = nil

    var finalHeaders = self.headers
    if (finalHeaders == nil || finalHeaders!.isEmpty), let home = self.home {
      do {
        let (accessToken, _) = try await home.permissions.authorization()
        finalHeaders = ["Authorization": "Bearer \(accessToken)"]
        Logger().info(">>> Fetched auth token for playback URL")
      } catch {
        Logger().error(">>> Failed to fetch auth token: \(error.localizedDescription)")
      }
    }

    guard let headers = finalHeaders, !headers.isEmpty else {
      let item = AVPlayerItem(url: self.url)
      player.replaceCurrentItem(with: item)
      player.play()
      return
    }

    let handler = HistoricalPlaybackAsset(url: self.url, headers: headers)
    self.assetHandler = handler
    if let item = await handler.makePlayerItem() {
      Logger().info(">>> Replacing player item with intercepted asset")
      player.replaceCurrentItem(with: item)
      player.play()
    }
  }

}

@MainActor
private class HistoricalPlaybackAsset: NSObject, AVAssetResourceLoaderDelegate {
  private let url: URL
  private let headers: [String: String]
  private var masterPlaylistData: Data?
  private var masterPlaylistURL: URL?
  private var masterPlaylistMIMEType: String?

  private var cookies: [HTTPCookie] = []
  private let session: URLSession

  init(url: URL, headers: [String: String]) {
    self.url = url
    self.headers = headers
    let configuration = URLSessionConfiguration.ephemeral
    self.session = URLSession(configuration: configuration)
  }

  fileprivate func makePlayerItem() async -> AVPlayerItem? {
    var request = URLRequest(url: self.url)
    headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

    do {
      Logger().info(">>> Fetching master playlist: \(self.url.lastPathComponent)")
      let (data, response) = try await session.data(for: request)
      guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
        Logger().error(">>> Master playlist fetch failed: \(String(describing: response))")
        return nil
      }

      self.masterPlaylistData = data
      self.masterPlaylistURL = self.url
      self.masterPlaylistMIMEType = response.mimeType

      if let httpResponse = response as? HTTPURLResponse,
        let fields = httpResponse.allHeaderFields as? [String: String]
      {
        let extracted = HTTPCookie.cookies(withResponseHeaderFields: fields, for: self.url)
        self.cookies.append(contentsOf: extracted)
        Logger().info(">>> Extracted and set \(extracted.count) cookies to session array")
      }

      Logger().info(">>> Master playlist fetched, total session cookies: \(self.cookies.count)")

      guard let customURL = self.url.customNestSchemeURL else {
        Logger().error(">>> Failed to create custom nest scheme URL")
        return nil
      }
      Logger().info(">>> Intercepting with custom URL: \(customURL)")

      let asset = AVURLAsset(
        url: customURL,
        options: [
          AVURLAssetHTTPCookiesKey: self.cookies,
          AVURLAssetPreferPreciseDurationAndTimingKey: true,
        ])
      asset.resourceLoader.setDelegate(self, queue: .main)
      return AVPlayerItem(asset: asset)
    } catch {
      Logger().error(">>> Error making asset: \(error.localizedDescription)")
      return nil
    }
  }

  nonisolated func resourceLoader(
    _ resourceLoader: AVAssetResourceLoader,
    shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
  ) -> Bool {
    guard let url = loadingRequest.request.url else { return false }
    let redirectURL = url.httpsSchemeURL ?? url
    guard redirectURL.scheme == "https" else {
      Logger().error(
        ">>> Unexpected resource URL: \(loadingRequest.request.url?.absoluteString ?? "nil")")
      return false
    }

    Task { @MainActor [weak self] in
      guard let self else { return }

      if redirectURL == self.masterPlaylistURL {
        if let data = self.masterPlaylistData {
          loadingRequest.dataRequest?.respond(with: data)
          loadingRequest.finishLoading()
        } else {
          Logger().error(">>> Master playlist data missing in delegate")
          loadingRequest.finishLoading(
            with: NSError(domain: "HistoricalPlayback", code: -1, userInfo: nil))
        }
      } else {
        loadingRequest.redirect = loadingRequest.request.replacingToURL(redirectURL)
        loadingRequest.response = HTTPURLResponse(
          url: redirectURL, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: nil)
        loadingRequest.finishLoading()
      }
    }
    return true
  }
}

// MARK: - URL
extension URL {
  fileprivate static let customNestScheme = "https-nest"

  var customNestSchemeURL: URL? {
    let s = absoluteString
    if s.hasPrefix("https://") {
      return URL(string: Self.customNestScheme + s.dropFirst("https".count))
    }
    return nil
  }

  var httpsSchemeURL: URL? {
    let s = absoluteString
    if s.hasPrefix(Self.customNestScheme + "://") {
      return URL(string: "https" + s.dropFirst(Self.customNestScheme.count))
    }
    return nil
  }
}

// MARK: - URLRequest
extension URLRequest {
  func replacingToURL(_ toURL: URL) -> URLRequest {
    var newRequest = self
    newRequest.url = toURL
    return newRequest
  }
}
