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

  /// Initializes the camera live view model.
  ///
  /// - Parameters:
  ///   - home: The user's home to which the camera device belongs.
  ///   - deviceID: The device id of the camera device.
  ///   - renderer: The `RTCVideoRenderer` to display the video stream.
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
            Logger().info("Received unexpected device subscription completion: \(String(describing: error))")
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
            // Case where the player has been turned on by another controller.
            if self.uiState == .off && self.isDeviceRecording() {
              await self.initializePlayer()
            }
          }
        }
      )
      .store(in: &self.cancellables)
  }

  /// Checks for an active livestream connection.
  public func isDeviceRecording() -> Bool {
    guard let pushAvStreamTransportTrait else {
      Logger().error("PushAvStreamTransportTrait not found.")
      return false
    }
    let hasActiveConnection =
      pushAvStreamTransportTrait
      .attributes
      .currentConnections?
      .contains(where: { $0.transportStatus == .active }) ?? false
    return hasActiveConnection
  }

  /// Toggles the camera's recording state by setting the `PushAvStreamTransportTrait`.
  ///
  /// - Parameters:
  ///   - isOn: A Boolean value indicating whether to enable (`true`) or disable (`false`) recording.
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
          do {
            self.player = try self.createWebRtcPlayer()
          } catch {
            Logger().error("Failed to create WebRtcPlayer: \(error)")
            self.uiState = .disconnected
            return
          }
          if await self.player?.initialize() ?? false {
            self.uiState = .live
          } else {
            Logger().error("Failed to initialize WebRtcPlayer.")
            self.uiState = .disconnected
          }
        } else {
          self.player = nil
          self.uiState = .off
        }
      } catch {
        Logger().error("Failed to toggle onOff: \(error)")
      }
    }
  }

  /// Toggles the two-way talk feature.
  ///
  /// - Parameters:
  ///   - isOn: A Boolean value indicating whether to enable (`true`) or disable (`false`) two-way talk.
  public func toggleTwoWayTalk(isOn: Bool) {
    Task { @MainActor in
      try await self.player?.toggleTwoWayTalk(isOn: isOn)
      self.isTwoWayTalkOn = isOn
    }
  }

  /// Leaves the livestream view and disposes of the player.
  public func leaveStreamView() {
    Logger().info("Left livestream view.")
    self.player = nil
  }

  /// Reconnects to the livestream.
  public func reconnectStream() {
    self.uiState = .loading
    Task {
      await self.initializePlayer()
    }
  }

  private func initializePlayer() async {

    guard self.player == nil else {
      Logger().info("Player already initialized.")
      return
    }
    guard liveViewTrait != nil else {
      Logger().error("LiveViewTrait not found.")
      return
    }

    if self.isDeviceRecording() {
      self.uiState = .loading
      do {
        self.player = try self.createWebRtcPlayer()
      } catch {
        Logger().error("Failed to initialize WebRtcPlayer: \(error)")
        self.uiState = .disconnected
        return
      }
      await self.player?.initialize()
      self.uiState = .live
    } else {
      self.uiState = .off
    }
  }

  private func createWebRtcPlayer() throws -> WebRtcPlayer {
    guard let liveViewTrait else {
      throw HomeError.failedPrecondition("LiveViewTrait not found.")
    }
    do {
      return try WebRtcPlayer(
        liveViewTrait: liveViewTrait,
        renderer: self.renderer,
        onStreamDidDisconnect: { @MainActor @Sendable [weak self] in
          self?.streamDidDisconnect()
        }
      )
    } catch {
      self.uiState = .disconnected
      throw error
    }
  }

  private func streamDidDisconnect() {
    Logger().info("Stream disconnected.")
    self.player = nil
    self.reconnectStream()
  }

}

enum CameraUIState {
  case loading
  case live
  case off
  case disconnected
}
