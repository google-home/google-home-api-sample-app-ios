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

/// A ViewModel for the camera OOBE setup process (OTA -> Settings -> Done).
///
/// The OTA step is driven by `OtaUpdateViewModel`, so cameras get the same per-phase watchdogs
/// (300s checking, 1800s download, 900s install) as other Matter devices.
@MainActor
@Observable
public class CameraOOBEViewModel<T: DeviceType> {

  public enum Step {
    case ota
    case settings
    case done
  }

  private var cancellables = Set<AnyCancellable>()
  public let home: Home
  /// Shared OTA state machine backing the OTA step.
  public let otaViewModel: OtaUpdateViewModel
  private var device: HomeDevice
  /// The current step of the setup flow.
  public private(set) var step: Step = .ota
  /// The latest OTA update state mirrored from `otaViewModel`.
  public private(set) var otaUiState: OtaUiState = .loading
  public private(set) var isLoading = false

  /// Whether the device is reachable; the Done step waits for it.
  public var isOnline: Bool {
    let state = self.device.sourceConnectivity.connectivityState
    return state == .online || state == .partiallyOnline
  }

  /// Whether the user may leave the OTA step manually (the update failed or is delayed).
  public var canSkipOta: Bool {
    switch self.otaUiState {
    case .failed, .delayed:
      return true
    case .loading, .checking, .downloading, .installing, .upToDate:
      return false
    }
  }

  public init(home: Home, device: HomeDevice) {
    self.home = home
    self.device = device
    self.otaViewModel = OtaUpdateViewModel(home: home, device: device, isOobeFlow: true)

    // Reuse the OTA ViewModel's device subscription to keep connectivity fresh.
    self.otaViewModel.$currentDevice
      .compactMap { $0 }
      .receive(on: DispatchQueue.main)
      .sink { [weak self] updatedDevice in
        self?.device = updatedDevice
      }
      .store(in: &cancellables)

    self.otaViewModel.$otaUiState
      .receive(on: DispatchQueue.main)
      .sink { [weak self] state in
        self?.handleOtaState(state)
      }
      .store(in: &cancellables)
  }

  public func nextStep() {
    switch step {
    case .ota:
      guard canSkipOta else {
        Logger().debug("Cannot manually advance from OTA step while the update is in progress")
        return
      }
      step = .settings
    case .settings:
      step = .done
    case .done:
      Logger().debug("Already at the last step")
    }
  }

  /// Marks configuration complete.
  ///
  /// Falls back from `OtaRequestorDeviceType` to `RootNodeDeviceType` and skips (without throwing)
  /// when `ConfigurationDoneTrait` is missing.
  public func configurationDone() async {
    self.isLoading = true
    defer { self.isLoading = false }
    try? await self.otaViewModel.finishConfiguration()
  }

  private func handleOtaState(_ state: OtaUiState) {
    self.otaUiState = state
    guard case .ota = self.step else { return }
    if case .upToDate = state {
      Logger().debug("OTA update is complete, advancing to settings step")
      self.step = .settings
    }
  }
}
