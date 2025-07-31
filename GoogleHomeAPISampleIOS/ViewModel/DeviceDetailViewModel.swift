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
import GoogleHomeSDK
import OSLog

@MainActor
/// The viewModel handling device operations.
final class DeviceDetailViewModel: ObservableObject {
  @Published public private(set) var decommissionEligibility =
    HomeDevice.DecommissionEligibility.ineligible(reason: .other("Not loaded"))

  private var home: Home
  public private(set) var device: HomeDevice?
  private var cancellables: Set<AnyCancellable> = []

  /// Initializes the DeviceDetailViewModel.
  ///
  /// Sets up the view model to observe the specified device for changes.
  ///
  /// - Parameters:
  ///   - home: The home object that the device belongs to.
  ///   - deviceID: The ID of the device to observe.
  init(home: Home, device: HomeDevice) {
    self.home = home
    self.device = device
  }

  public func checkDecommissionEligibility() {
    Task { @MainActor in
      do {
        guard let device = self.device else { return }
        self.decommissionEligibility =
          try await device.decommissionEligibility
      } catch {
        Logger().error("Failed to get decommission eligibility: \(error)")
        self.decommissionEligibility =
          HomeDevice.DecommissionEligibility.ineligible(
            reason: .other(
              "Failed to get decommission eligibility: \(error.localizedDescription)"
            ))
      }
    }
  }

  public func decommissionDevice() async throws -> Set<String> {
    guard let device = self.device else {
      throw HomeError.internal("Device not found during decommissioning.")
    }
    return try await device.decommission()
  }
}
