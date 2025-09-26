// Copyright 2025 Google LLC
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

import GoogleHomeSDK
import GoogleHomeTypes
import OSLog

/// Manages the WebRTC signaling logic (offer/answer, talkback) by wrapping the `WebRtcLiveViewTrait`.
public final class SignalingService: Sendable {

  private let liveViewTrait: Google.WebRtcLiveViewTrait

  public init(
    liveViewTrait: Google.WebRtcLiveViewTrait,
  ) {
    Logger().info("Initializing SignalingService")
    self.liveViewTrait = liveViewTrait
  }

  public func sendOffer(offerSdp: String) async throws -> WebRtcLiveViewResponse {
    do {
      Logger().info("Sending StartLiveView command...")
      let response = try await liveViewTrait.startLiveView(
        offerSdp: offerSdp
      )
      Logger().info("Received StartLiveView response: \(response.answerSdp)")
      return WebRtcLiveViewResponse(
        answerSdp: response.answerSdp,
        mediaSessionId: response.mediaSessionId
      )
    } catch {
      Logger().error("Failed to send StartLiveView command: \(error)")
      throw error
    }
  }

  public func stopLiveView(mediaSessionId: String) async throws {
    do {
      Logger().info("Stopping live view...")
      try await liveViewTrait.stopLiveView(mediaSessionId: mediaSessionId)
    } catch {
      Logger().error("Failed to stop live view: \(error)")
      throw error
    }
  }

  public func toggleTwoWayTalk(isOn: Bool, mediaSessionId: String) async throws {
    do {
      Logger().info("Toggling twoWayTalk to \(isOn ? "ON" : "OFF")...")
      if isOn {
        try await liveViewTrait.startTalkback(mediaSessionId: mediaSessionId)
      } else {
        try await liveViewTrait.stopTalkback(mediaSessionId: mediaSessionId)
      }
    } catch {
      throw HomeError.commandFailed("Failed to toggle twoWayTalk: \(error)")
    }
  }
}

public struct WebRtcLiveViewResponse {
  let answerSdp: String?
  let mediaSessionId: String?
}
