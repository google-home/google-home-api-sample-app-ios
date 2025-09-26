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

import Combine
import Dispatch
import GoogleHomeSDK
import GoogleHomeTypes
import OSLog
import Observation
import WebRTC

/// The viewModel handling camera livestreaming and control.
@Observable
@MainActor
class CameraLiveViewModel {
  private static let supportedDeviceTypes: [any DeviceType.Type] = [
    GoogleCameraDeviceType.self,
    GoogleDoorbellDeviceType.self,
  ]
  private let home: Home
  private var player: WebRtcPlayer?
  private var renderer: RTCVideoRenderer
  public private(set) var device: HomeDevice?
  private var liveViewTrait: Google.WebRtcLiveViewTrait?
  private var pushAvStreamTransportTrait: Google.PushAvStreamTransportTrait?

  var isTwoWayTalkOn: Bool = false

  var uiState: CameraUIState = .loading {
    didSet {
      if uiState != .live {
        self.isTwoWayTalkOn = false
      }
    }
  }

  private var cancellables = Set<AnyCancellable>()

  init(home: Home, deviceID: String, renderer: RTCVideoRenderer) {
    Logger().info("Init CameraLiveViewModel")

    self.home = home
    self.renderer = renderer

    Logger().info("Getting device from home...")
    self.home.device(id: deviceID)
      .receive(on: DispatchQueue.main)
      .removeDuplicates()
      .sink(
        receiveCompletion: { [weak self] completion in
          guard self != nil else { return }
          switch completion {
          case .finished:
            Logger().info("Received unexpected device finished unexpectedly")
          case .failure(let error):
            Logger().info(
              "Received unexpected device subscription completion: \(String(describing: error))"
            )
          }
        },
        receiveValue: { [weak self] device in
          guard let self = self else { return }
          Logger().info("Fetched device: \(device.name)")
          self.device = device

          Task {
            guard
              let deviceSupportedType =
                Self.supportedDeviceTypes.first(where: { device.types.contains($0) }),
              let deviceType = await device.types.get(deviceSupportedType)
            else {
              Logger().error("Device is not a supported device type.")
              return
            }
            guard let liveViewTrait = deviceType.traits[Google.WebRtcLiveViewTrait.self] else {
              Logger().error("Device does not have a WebRtcLiveViewTrait.")
              return
            }
            self.liveViewTrait = liveViewTrait
            guard
              let pushAvStreamTransportTrait =
                deviceType.traits[Google.PushAvStreamTransportTrait.self]
            else {
              Logger().error("Device does not have a PushAvStreamTransportTrait.")
              return
            }
            self.pushAvStreamTransportTrait = pushAvStreamTransportTrait
            await self.initializePlayer()
          }
        }
      )
      .store(in: &self.cancellables)
  }

  private func initializePlayer() async {
    self.uiState = .loading

    guard self.player == nil else {
      Logger().info("Player already initialized.")
      return
    }
    guard let liveViewTrait else {
      Logger().error("LiveViewTrait not found.")
      return
    }

    if self.isDeviceRecording() {
      self.player = WebRtcPlayer(
        liveViewTrait: liveViewTrait,
        renderer: self.renderer,
        onStreamDidDisconnect: { self.streamDidDisconnect() }
      )
      await self.player?.initialize()
      self.uiState = .live
    } else {
      self.uiState = .off
    }
  }

  /// To toggle the camera's recording state by setting the `PushAvStreamTransportTrait`.
  public func isDeviceRecording() -> Bool {
    guard let pushAvStreamTransportTrait else {
      Logger().error("PushAvStreamTransportTrait not found.")
      return false
    }
    guard
      let hasActiveConnection =
        pushAvStreamTransportTrait
        .attributes
        .currentConnections?
        .contains(where: { $0.transportStatus == .active })
    else {
      return false
    }
    return hasActiveConnection
  }

  public func toggleIsRecording(isOn: Bool) {
    self.uiState = .loading

    guard let pushAvStreamTransportTrait else {
      Logger().error("PushAvStreamTransportTrait not found.")
      return
    }
    Task {
      do {
        Logger().debug("Toggling onOff to \(isOn ? "ON" : "OFF")...")
        try await pushAvStreamTransportTrait.setTransportStatus(
          transportStatus: isOn ? .active : .inactive
        )
        if isOn {
          guard let liveViewTrait else {
            Logger().error("LiveViewTrait not found.")
            return
          }
          self.player = WebRtcPlayer(
            liveViewTrait: liveViewTrait,
            renderer: self.renderer,
            onStreamDidDisconnect: { self.streamDidDisconnect() }
          )
          await self.player?.initialize()
          self.uiState = .live
        } else {
          self.player = nil
          self.uiState = .off
        }
      } catch {
        Logger().error("Failed to toggle onOff: \(error)")
      }
    }
  }

  public func toggleTwoWayTalk(isOn: Bool) {
    Task { @MainActor in
      try await self.player?.toggleTwoWayTalk(isOn: isOn)
      self.isTwoWayTalkOn = isOn
    }
  }

  public func leaveStreamView() {
    cancellables.forEach { $0.cancel() }
    streamDidDisconnect()
  }

  private func streamDidDisconnect() {
    Logger().info("Stream disconnected.")
    self.uiState = .disconnected
    self.player = nil
  }

  public func reconnectStream() {
    self.uiState = .loading
    Task {
      if self.isDeviceRecording() {
        await self.initializePlayer()
        self.uiState = .live
      } else {
        self.uiState = .off
      }
    }
  }

}

enum CameraUIState {
  case loading
  case live
  case off
  case disconnected
}
