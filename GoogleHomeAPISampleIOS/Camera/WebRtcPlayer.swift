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

import AVFAudio
import Combine
import Foundation
import GoogleHomeSDK
import GoogleHomeTypes
import OSLog
import UIKit
import WebRTC

/// Orchestrates the RTCPeerConnection lifecycle, using SignalingService to manage the media session.
public class WebRtcPlayer: NSObject {

  private var peerConnection: RTCPeerConnection
  private var mediaConstraints: RTCMediaConstraints
  private var signalingService: SignalingService

  private var onStreamDidDisconnect: (@MainActor @Sendable () -> Void)?
  private var dataChannel: RTCDataChannel?
  private var renderer: RTCVideoRenderer?
  private var videoTrack: RTCVideoTrack?
  // Local audio track refers to phone -> camera audio (two way talk)
  private var localAudioTrack: RTCAudioTrack?
  // Remote audio track refers to camera -> phone audio (camera microphone)
  private var remoteAudioTrack: RTCAudioTrack?
  private var mediaSessionId: String?
  private var didEnterBackgroundObserver: NSObjectProtocol?
  private var extendLiveViewTimer: AnyCancellable?
  private var initialized = false

  /// Initializes the WebRTC player, peer connection, and signaling service.
  ///
  /// - Parameters:
  ///   - liveViewTrait: The `WebRtcLiveViewTrait` to manage the WebRTC session.
  ///   - renderer: The `RTCVideoRenderer` to display the video stream.
  ///   - onStreamDidDisconnect: A closure to be called when the stream is disconnected.
  ///     This is typically `CameraLiveViewModel`'s `streamDidDisconnect` function, and it would automatically triggers a reconnect.
  public init(
    liveViewTrait: Google.WebRtcLiveViewTrait,
    renderer: RTCVideoRenderer,
    onStreamDidDisconnect: (@MainActor @Sendable () -> Void)?
  ) throws {

    self.renderer = renderer
    self.onStreamDidDisconnect = onStreamDidDisconnect
    self.signalingService = SignalingService(liveViewTrait: liveViewTrait)

    let factory = RTCPeerConnectionFactory()

    let config = RTCConfiguration()
    config.sdpSemantics = .unifiedPlan
    config.continualGatheringPolicy = .gatherOnce

    self.mediaConstraints = RTCMediaConstraints(
      mandatoryConstraints: [
        kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueTrue,
        kRTCMediaConstraintsOfferToReceiveVideo: kRTCMediaConstraintsValueTrue,
      ],
      optionalConstraints: [:]
    )

    guard let peerConnection = factory.peerConnection(
      with: config,
      constraints: self.mediaConstraints,
      delegate: nil
    ) else {
      throw HomeError.commandFailed("Failed to create peer connection")
    }
    self.peerConnection = peerConnection

    let audioSource = factory.audioSource(with: mediaConstraints)
    let localAudioTrack = factory.audioTrack(
      with: audioSource,
      trackId: "ARDAMSa0"
    )
    self.localAudioTrack = localAudioTrack
    localAudioTrack.isEnabled = true
    localAudioTrack.source.volume = 10.0
    self.peerConnection.add(localAudioTrack, streamIds: ["audio_stream"])

    let dataChannelConfig = RTCDataChannelConfiguration()
    self.dataChannel = self.peerConnection.dataChannel(
      forLabel: "data",
      configuration: dataChannelConfig
    )

    super.init()
    self.peerConnection.delegate = self
    self.didEnterBackgroundObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.didEnterBackgroundNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Logger().debug("App did enter background, closing WebRTC stream.")
      self?.dispose()
    }
  }

  deinit {
    self.dispose()
    if let didEnterBackgroundObserver = self.didEnterBackgroundObserver {
      NotificationCenter.default.removeObserver(didEnterBackgroundObserver)
      self.didEnterBackgroundObserver = nil
    }
  }

  /// Starts the WebRTC session by creating an offer and setting the remote answer.
  public func initialize() async -> Bool {

    guard !self.initialized else {
      Logger().info("WebRTC Player is already initialized.")
      return false
    }
    self.initialized = true

    do {
      let offerSdp = try await self.createOffer()
      Logger().debug("WebRTC Offer SDP: \(offerSdp)")

      let response = try await self.signalingService.sendOffer(offerSdp: offerSdp)
      guard let answerSdp = response.answerSdp else {
        throw HomeError.commandFailed(
          "Failed to get answer sdp from signaling service"
        )
      }
      Logger().debug("WebRTC Answer SDP: \(answerSdp)")
      guard let mediaSessionId = response.mediaSessionId else {
        throw HomeError.commandFailed(
          "Failed to get media session id from signaling service"
        )
      }
      self.mediaSessionId = mediaSessionId
      try await self.setAnswer(answerSdp: answerSdp)

      // If liveViewDuration is not provided in the response, use a default value.
      self.startExtendLiveViewTimer(
        liveViewDuration: response.liveViewDuration ?? 270.0
      )
      return true
    } catch {
      Logger().debug("WebRTC Failed to create offer or set answer: \(error)")
      return false
    }
  }

  /// Tears down the WebRTC connection and notifies the signaling service to stop the stream.
  public func dispose() {
    self.extendLiveViewTimer?.cancel()
    self.extendLiveViewTimer = nil
    self.detachRenderer()

    if let mediaSessionId = self.mediaSessionId {
      let signalingService = self.signalingService
      Task {
        do {
          Logger().debug("Stopping live view with media session id: \(mediaSessionId)")
          try await signalingService.stopLiveView(
            mediaSessionId: mediaSessionId
          )
        } catch {
          Logger().debug("Failed to stop live view: \(error)")
        }
      }
    } else {
      Logger().debug("Media session id is nil, not stopping live view.")
    }

    self.peerConnection.close()
    self.dataChannel?.close()
    self.dataChannel = nil
    self.videoTrack = nil
    self.localAudioTrack = nil
    self.remoteAudioTrack = nil
    self.dataChannel = nil
  }

  /// Attaches a video renderer to the video track.
  ///
  /// - Parameters:
  ///   - renderer: The `RTCVideoRenderer` instance to attach.
  public func attachRenderer(renderer: RTCVideoRenderer) {
    if let renderer = self.renderer {
      self.videoTrack?.remove(renderer)
    }
    self.renderer = renderer
    self.videoTrack?.add(renderer)
  }

  public func detachRenderer() {
    if let renderer = self.renderer, let videoTrack = self.videoTrack {
      videoTrack.remove(renderer)
    }
    self.renderer = nil
  }

  /// Toggles the two-way talk feature.
  ///
  /// - Parameters:
  ///   - isOn: A Boolean value indicating whether to enable (`true`) or disable (`false`) two-way talk.
  public func toggleTwoWayTalk(isOn: Bool) async throws {
    guard let mediaSessionId = self.mediaSessionId else {
      throw HomeError.failedPrecondition("Media session id is nil")
    }
    try await self.signalingService.toggleTwoWayTalk(
      isOn: isOn,
      mediaSessionId: mediaSessionId
    )
  }

  private func createOffer() async throws -> String {
    do {
      let sessionDescription = try await peerConnection.offer(for: mediaConstraints)
      try await peerConnection.setLocalDescription(sessionDescription)
      Logger().debug("WebRTC Offer SDP: \(sessionDescription.sdp)")
      return sessionDescription.sdp
    } catch {
      throw HomeError.commandFailed("Failed to create offer")
    }
  }

  private func setAnswer(answerSdp: String) async throws {
    do {
      try await peerConnection.setRemoteDescription(
        RTCSessionDescription(type: .answer, sdp: answerSdp)
      )
    } catch {
      throw HomeError.commandFailed("Failed to set answer")
    }
  }

  /// Sets up a recurring timer to extend the live view session before it expires.
  ///
  /// - Parameters:
  ///   - liveViewDuration: The duration of the live view session in seconds.
  private func startExtendLiveViewTimer(liveViewDuration: TimeInterval) {
    self.extendLiveViewTimer?.cancel()
    // Refresh 30 seconds before the live view expires to avoid any timing issues.
    let refreshInterval = liveViewDuration - 30.0
    guard refreshInterval > 0 else {
      Logger().error("Live view duration is too short to set up a refresh timer.")
      return
    }

    let mediaSessionId = self.mediaSessionId
    guard let mediaSessionId = mediaSessionId else {
      Logger().error("Cannot extend stream, media session id is nil.")
      return
    }

    let signalingService = self.signalingService

    self.extendLiveViewTimer = Timer.publish(every: refreshInterval, on: .main, in: .common)
      .autoconnect()
      .sink { _ in
        Task {
          do {
            try await signalingService.extendLiveView(mediaSessionId: mediaSessionId)
            Logger().debug("Successfully extended live view stream.")
          } catch {
            Logger().debug("Failed to extend live view stream: \(error)")
          }
        }
      }
  }
}

// MARK: - RTCPeerConnectionDelegate
extension WebRtcPlayer: RTCPeerConnectionDelegate {

  public func peerConnection(
    _ peerConnection: RTCPeerConnection,
    didChange stateChanged: RTCSignalingState
  ) {
    Logger().debug("WebRTC Delegate: Signaling state changed: \(stateChanged.rawValue)")
  }

  /// Handles receiving and attaching the remote video and audio tracks.
  public func peerConnection(
    _ peerConnection: RTCPeerConnection,
    didAdd stream: RTCMediaStream
  ) {
    Logger().info("WebRTC Delegate: Did add stream: \(stream.streamId)")

    // Callback will receive two added streams, one that contains the video track and one that
    // contains the audio track.

    if let videoTrack = stream.videoTracks.first {
      self.videoTrack = videoTrack
      if let renderer = self.renderer {
        self.videoTrack?.add(renderer)
      } else {
        Logger().debug("WebRTC Delegate: No renderer found for stream: \(stream.streamId)")
      }
    } else {
      Logger().debug("WebRTC Delegate: No video track found for stream: \(stream.streamId)")
    }

    if let audioTrack = stream.audioTracks.first {
      self.remoteAudioTrack = audioTrack
      audioTrack.isEnabled = true
      audioTrack.source.volume = 10.0

      Task { @MainActor in
        let audioSession = RTCAudioSession.sharedInstance()
        audioSession.lockForConfiguration()
        do {
          try audioSession.overrideOutputAudioPort(.speaker)
          Logger().info("WebRTC Delegate: Successfully re-configured audio session to speaker.")
        } catch {
          Logger().error("WebRTC Delegate: Failed to re-configure audio session for speaker output with error: \(error).")
        }
        audioSession.unlockForConfiguration()
      }
    } else {
      Logger().debug("WebRTC Delegate: No audio track found for stream: \(stream.streamId)")
    }
  }

  public func peerConnection(
    _ peerConnection: RTCPeerConnection,
    didRemove stream: RTCMediaStream
  ) {
    Logger().info("WebRTC Delegate: Did remove stream: \(stream.streamId)")
  }

  public func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
    Logger().debug("WebRTC Delegate: Should negotiate")
  }

  /// Monitors the ICE connection state to detect disconnections and trigger callbacks.
  public func peerConnection(
    _ peerConnection: RTCPeerConnection,
    didChange newState: RTCIceConnectionState
  ) {
    Logger().debug("WebRTC Delegate: ICE connection state changed: \(newState.rawValue)")
    switch newState {
    case .disconnected, .failed, .closed:
      Logger().debug("WebRTC Delegate: Stream disconnected, calling onStreamDidDisconnect.")
      // We must check to make sure we don't have an active stream, to avoid a loop
      if self.mediaSessionId != nil {
        self.mediaSessionId = nil
        if let onStreamDidDisconnect = self.onStreamDidDisconnect {
          Task(operation: onStreamDidDisconnect)
        }
      }
    default:
      break
    }
  }

  public func peerConnection(
    _ peerConnection: RTCPeerConnection,
    didChange newState: RTCIceGatheringState
  ) {
    Logger().debug("WebRTC Delegate: ICE gathering state changed: \(newState.rawValue)")
  }

  public func peerConnection(
    _ peerConnection: RTCPeerConnection,
    didGenerate candidate: RTCIceCandidate
  ) {
    Logger().debug("WebRTC Delegate: Did generate ICE candidate: \(candidate.sdp)")
  }

  public func peerConnection(
    _ peerConnection: RTCPeerConnection,
    didRemove candidates: [RTCIceCandidate]
  ) {
    Logger().debug("WebRTC Delegate: Did remove ICE candidates: \(candidates.count)")
  }

  public func peerConnection(
    _ peerConnection: RTCPeerConnection,
    didOpen dataChannel: RTCDataChannel
  ) {
    Logger().debug("WebRTC Delegate: Did open data channel")
  }

}
