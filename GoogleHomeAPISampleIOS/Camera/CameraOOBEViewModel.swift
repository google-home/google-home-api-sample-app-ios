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
    case otaDownload
    case settings
    case done
  }

  public let home: Home
  private var device: HomeDevice
  public private(set) var step: Step = .otaDownload
  public private(set) var isLoading = false


  public init(home: Home, device: HomeDevice) {
    self.home = home
    self.device = device
  }

  public func nextStep() {
    switch step {
    case .otaDownload:
      step = .settings
    case .settings:
      step = .done
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
