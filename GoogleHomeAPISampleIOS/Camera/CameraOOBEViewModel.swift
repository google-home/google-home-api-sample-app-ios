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

/// A ViewModel for the OOBE setup process, handling the transition for each step.
@MainActor
@Observable
public class CameraOOBEViewModel<T: DeviceType> {

  public enum Step {
    case otaDownload(
      state: Matter.OtaSoftwareUpdateRequestorTrait.UpdateStateEnum, progress: Double)
    case settings
    case done
  }

  private var cancellables = Set<AnyCancellable>()
  public let home: Home
  private var device: HomeDevice
  public private(set) var step: Step = .otaDownload(state: .querying, progress: 0)
  public private(set) var isLoading = false

  private var otaTrait: Matter.OtaSoftwareUpdateRequestorTrait? {
    didSet {
      dispatchPrecondition(condition: .onQueue(.main))

      guard case .otaDownload = step else {
        Logger().debug("Not in OTA download step, ignoring OTA trait update")
        return
      }

      guard let otaTrait else {
        Logger().debug("OTA trait is nil, skipping OTA download step")
        step = .settings
        return
      }

      if otaTrait.attributes.updateState == .idle {
        Logger().debug("OTA update is complete, advancing to settings step")
        step = .settings
        return
      }

      Logger().debug(
        "OTA update is in progress, state: \(String(describing: otaTrait.attributes.updateState)), progress: \(otaTrait.attributes.updateStateProgress ?? 0)"
      )

      step = .otaDownload(
        state: otaTrait.attributes.updateState ?? .querying,
        progress: Double(otaTrait.attributes.updateStateProgress ?? 0) / 100.0)
    }
  }

  public init(home: Home, device: HomeDevice) {
    self.home = home
    self.device = device

    home.device(id: device.id)
      .receive(on: DispatchQueue.main)
      .flatMap { [weak self] device in
        self?.device = device
        return device.types.subscribe(OtaRequestorDeviceType.self).receive(on: DispatchQueue.main)
      }
      .compactMap { $0.traits[Matter.OtaSoftwareUpdateRequestorTrait.self] }
      .removeDuplicates()
      .timeout(.seconds(60), scheduler: DispatchQueue.main) {
        HomeError.deadlineExceeded("OTA trait timed out waiting for updates")
      }
      .sink { [weak self] completion in
        guard let self else { return }
        Logger().debug("OTA trait subscription completed unexpectedly: \(String(describing: completion)).")
        if case .otaDownload = self.step {
          Logger().debug("Advancing to settings step due to OTA trait subscription completion")
          self.step = .settings
        }
      } receiveValue: { [weak self] (otaTrait: Matter.OtaSoftwareUpdateRequestorTrait) in
        guard let self else { return }
        self.otaTrait = otaTrait
      }
      .store(in: &cancellables)
  }

  public func nextStep() {
    switch step {
    case .settings:
      step = .done
    case .otaDownload:
      Logger().debug("Cannot manually advance from OTA download step")
    case .done:
      Logger().debug("Already at the last step")
    }
  }

  public func configurationDone() async throws {
    guard
      let configDoneTrait = await device.types.get(OtaRequestorDeviceType.self)?
        .traits[Google.ConfigurationDoneTrait.self]
    else {
      Logger().error("Failed to get configuration done trait")
      throw HomeError.notFound("Configuration done trait not found")
    }

    self.isLoading = true
    _ = try await configDoneTrait.update {
      $0.setAppConfigurationComplete(true)
    }
    self.isLoading = false
  }
}
