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
import UIKit
import WebRTC

/// Orchestrates the RTCPeerConnection lifecycle, using SignalingService to manage the media session.
public class WebRtcPlayer: NSObject {

  private var onStreamDidDisconnect: (() -> Void)?
  private var peerConnection: RTCPeerConnection?
  private var mediaConstraints: RTCMediaConstraints
  private var dataChannel: RTCDataChannel?
  private var renderer: RTCVideoRenderer?
  private var signalingService: SignalingService
  private var videoTrack: RTCVideoTrack?
  private var audioTrack: RTCMediaStreamTrack?
  private var mediaSessionId: String?
  private var didEnterBackgroundObserver: NSObjectProtocol?

  public init(
    liveViewTrait: Google.WebRtcLiveViewTrait,
    renderer: RTCVideoRenderer,
    onStreamDidDisconnect: (() -> Void)?
  ) {

    self.renderer = renderer
    self.onStreamDidDisconnect = onStreamDidDisconnect

    let factory = RTCPeerConnectionFactory()

    let config = RTCConfiguration()
    config.sdpSemantics = .unifiedPlan

    self.mediaConstraints = RTCMediaConstraints(
      mandatoryConstraints: [
        kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueTrue,
        kRTCMediaConstraintsOfferToReceiveVideo: kRTCMediaConstraintsValueTrue,
      ],
      optionalConstraints: [:]
    )

    self.peerConnection = factory.peerConnection(
      with: config,
      constraints: self.mediaConstraints,
      delegate: nil
    )

    let audioSource = factory.audioSource(with: mediaConstraints)
    let localAudioTrack = factory.audioTrack(with: audioSource, trackId: "ARDAMSa0")
    self.audioTrack = localAudioTrack
    localAudioTrack.isEnabled = true
    localAudioTrack.source.volume = 10.0
    self.peerConnection?.add(localAudioTrack, streamIds: ["audio_stream"])

    self.signalingService = SignalingService(liveViewTrait: liveViewTrait)

    let dataChannelConfig = RTCDataChannelConfiguration()
    self.dataChannel = self.peerConnection?.dataChannel(
      forLabel: "data", configuration: dataChannelConfig)

    super.init()
    self.peerConnection?.delegate = self
    self.didEnterBackgroundObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
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

  public func dispose() {
    self.detachRenderer()
    self.peerConnection?.close()

    if let mediaSessionId = self.mediaSessionId {
      let signalingService = self.signalingService
      Task {
        do {
          try await signalingService.stopLiveView(mediaSessionId: mediaSessionId)
        } catch {
          Logger().debug("Failed to stop live view: \(error)")
        }
      }
    }

    self.peerConnection = nil
    self.dataChannel = nil
    self.videoTrack = nil
    self.audioTrack = nil
  }

  public func initialize() async {
    do {
      let offerSdp = try await self.createOffer()
      Logger().debug("WebRTC Offer SDP: \(offerSdp)")

      let response = try await self.signalingService.sendOffer(offerSdp: offerSdp)
      guard let answerSdp = response.answerSdp else {
        throw HomeError.commandFailed("Failed to get answer sdp from signaling service")
      }
      Logger().debug("WebRTC Answer SDP: \(answerSdp)")
      guard let mediaSessionId = response.mediaSessionId else {
        throw HomeError.commandFailed("Failed to get media session id from signaling service")
      }
      self.mediaSessionId = mediaSessionId
      try await self.setAnswer(answerSdp: answerSdp)
    } catch {
      Logger().debug("WebRTC Failed to create offer or set answer: \(error)")
    }
  }

  // MARK: Peer Connection Functions

  private func createOffer() async throws -> String {
    guard let peerConnection = self.peerConnection else {
      throw HomeError.failedPrecondition("Peer connection is nil")
    }
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
    guard let peerConnection = self.peerConnection else {
      throw HomeError.failedPrecondition("Peer connection is nil")
    }
    do {
      try await peerConnection.setRemoteDescription(
        RTCSessionDescription(type: .answer, sdp: answerSdp)
      )
    } catch {
      throw HomeError.commandFailed("Failed to set answer")
    }
  }

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

  public func toggleTwoWayTalk(isOn: Bool) async throws {
    guard let mediaSessionId = self.mediaSessionId else {
      throw HomeError.failedPrecondition("Media session id is nil")
    }
    try await self.signalingService.toggleTwoWayTalk(isOn: isOn, mediaSessionId: mediaSessionId)
  }
}

// MARK: - RTCPeerConnectionDelegate
extension WebRtcPlayer: RTCPeerConnectionDelegate {

  public func peerConnection(
    _ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState
  ) {
    Logger().debug("WebRTC Delegate: Signaling state changed: \(stateChanged.rawValue)")
  }

  public func peerConnection(
    _ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream
  ) {
    Logger().info("WebRTC Delegate: Did add stream: \(stream.streamId)")
    guard let videoTrack = stream.videoTracks.first else {
      Logger().debug("WebRTC Delegate: No video track found for stream: \(stream.streamId)")
      return
    }
    self.videoTrack = videoTrack
    guard let renderer = self.renderer else {
      Logger().debug("WebRTC Delegate: No renderer found for stream: \(stream.streamId)")
      return
    }
    self.videoTrack?.add(renderer)
  }

  public func peerConnection(
    _ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream
  ) {
    Logger().info("WebRTC Delegate: Did remove stream: \(stream.streamId)")
  }

  public func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
    Logger().debug("WebRTC Delegate: Should negotiate")
  }

  public func peerConnection(
    _ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState
  ) {
    Logger().debug("WebRTC Delegate: ICE connection state changed: \(newState.rawValue)")
    switch newState {
    case .disconnected, .failed, .closed:
      Logger().debug("WebRTC Delegate: Stream disconnected, calling onStreamDidDisconnect.")
      // Peer connection must be nil to avoid looping back into this delegate.
      self.peerConnection = nil
      self.onStreamDidDisconnect?()
    default:
      break
    }
  }

  public func peerConnection(
    _ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState
  ) {
    Logger().debug("WebRTC Delegate: ICE gathering state changed: \(newState.rawValue)")
  }

  public func peerConnection(
    _ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate
  ) {
    Logger().debug("WebRTC Delegate: Did generate ICE candidate: \(candidate.sdp)")
  }

  public func peerConnection(
    _ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]
  ) {
    Logger().debug("WebRTC Delegate: Did remove ICE candidates: \(candidates.count)")
  }

  public func peerConnection(
    _ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel
  ) {
    Logger().debug("WebRTC Delegate: Did open data channel")
  }

}
