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

import Foundation
import GoogleHomeSDK
import GoogleHomeTypes
import OSLog

/// Manages the WebRTC signaling logic (offer/answer, talkback) by wrapping the `WebRtcLiveViewTrait`.
public final class SignalingService: Sendable {

  private let liveViewTrait: Google.WebRtcLiveViewTrait

  /// Initializes the signaling service.
  ///
  /// - Parameters:
  ///   - liveViewTrait: The `WebRtcLiveViewTrait` to manage the WebRTC session.
  public init(
    liveViewTrait: Google.WebRtcLiveViewTrait
  ) {
    Logger().info("Initializing SignalingService")
    self.liveViewTrait = liveViewTrait
  }

  /// Sends a WebRTC offer SDP to start a live view session.
  ///
  /// - Parameters:
  ///   - offerSdp: The WebRTC offer SDP string to initiate the connection.
  /// - Returns: The `WebRtcLiveViewResponse` with the answer SDP, media session ID, and live view duration.
  public func sendOffer(offerSdp: String) async throws -> WebRtcLiveViewResponse {
    do {
      Logger().info("Sending StartLiveView command...")
      let response = try await liveViewTrait.startLiveView(
        offerSdp: offerSdp
      )
      Logger().info("Received StartLiveView response: \(response.answerSdp)")
      return WebRtcLiveViewResponse(
        answerSdp: response.answerSdp,
        mediaSessionId: response.mediaSessionId,
        liveViewDuration: TimeInterval(response.liveSessionDurationSeconds),
      )
    } catch {
      Logger().error("Failed to send StartLiveView command: \(error)")
      throw error
    }
  }

  /// Stops the live view session associated with the media session ID.
  ///
  /// - Parameters:
  ///   - mediaSessionId: The id for the media session to be stopped.
  public func stopLiveView(mediaSessionId: String) async throws {
    do {
      Logger().info("Stopping live view...")
      try await liveViewTrait.stopLiveView(mediaSessionId: mediaSessionId)
    } catch {
      Logger().error("Failed to stop live view: \(error)")
      throw error
    }
  }

  /// Toggles the two-way talk feature for the given media session.
  ///
  /// - Parameters:
  ///   - isOn: A Boolean value indicating whether to enable (`true`) or disable (`false`) two-way talk.
  ///   - mediaSessionId: The id for the media session.
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

  /// Extends the duration of the active live view session.
  ///
  /// - Parameters:
  ///   - mediaSessionId: The id for the media session to be extended.
  public func extendLiveView(mediaSessionId: String) async throws {
    do {
      Logger().info("Extending live view...")
      let extendedDuration = try await liveViewTrait.extendLiveView(
        mediaSessionId: mediaSessionId
      )
      Logger().info("Extended live view for \(extendedDuration.liveSessionDurationSeconds) seconds.")
    } catch {
      Logger().error("Failed to extend live view: \(error)")
      throw error
    }
  }
}

public struct WebRtcLiveViewResponse {
  let answerSdp: String?
  let mediaSessionId: String?
  let liveViewDuration: TimeInterval?
}
