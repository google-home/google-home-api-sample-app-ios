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
import Foundation
import GoogleHomeSDK
import GoogleHomeTypes
import OSLog

/// A ViewModel handling device details, decommission eligibility, and live Matter OTA status.
///
/// In multi-endpoint devices, only endpoints with OTA support (Endpoint 0 Root Node or devices with
/// `OtaRequestorDeviceType` and a valid firmware version) will expose `hasOtaSupport == true`.
@MainActor
final class DeviceDetailViewModel: ObservableObject {
  private enum Constants {
    static let notLoadedReason = "Not loaded"
    static let notSupportedReason = "Not supported for this device entity"
    static let deviceNotFoundError = "Device not found during decommissioning."
  }

  @Published public private(set) var decommissionEligibility =
    HomeDevice.DecommissionEligibility.ineligible(reason: .other(Constants.notLoadedReason))
  @Published public private(set) var otaUiState: OtaUiState = .loading
  @Published public private(set) var softwareVersion: String?

  /// Whether this device has a Root Node or OTA Requestor type and reports a software version.
  public var hasOtaSupport: Bool {
    guard let device = self.device else { return false }
    // Only Root Node (Endpoint 0) or devices with OTA Requestor and a valid software version
    // support OTA display
    return (device.types.contains(OtaRequestorDeviceType.self) || device.types.contains(RootNodeDeviceType.self))
      && self.softwareVersion != nil
  }

  private var home: Home
  public private(set) var device: HomeDevice?
  private var cancellables: Set<AnyCancellable> = []

  /// Initializes the DeviceDetailViewModel.
  ///
  /// Sets up the view model to observe the specified device for changes.
  ///
  /// - Parameters:
  ///   - home: The home object that the device belongs to.
  ///   - device: The device to observe.
  init(home: Home, device: HomeDevice) {
    self.home = home
    self.device = device
    self.observeOtaUpdates()
  }

  private func observeOtaUpdates() {
    guard let initialDevice = device else { return }

    home.device(id: initialDevice.id, enableMultipartDevices: initialDevice.enableMultipartDevices)
      .removeDuplicates()
      .receive(on: DispatchQueue.main)
      .handleEvents(receiveOutput: { [weak self] device in
        self?.device = device
      })
      .map { device -> AnyPublisher<(OtaUiState, String?), Never> in
        OtaUpdateViewModel.otaStatePublisher(
          for: device,
          treatMissingRequestorAsUpToDate: true
        )
      }
      .switchToLatest()
      .receive(on: DispatchQueue.main)
      .sink(
        receiveCompletion: { [weak self] completion in
          if case .failure(let error) = completion {
            Logger().error("Device detail OTA subscription failed: \(error)")
            self?.otaUiState = OtaUiState.failed(
              error: error.localizedDescription,
              currentVersionString: self?.softwareVersion
            )
          }
        },
        receiveValue: { [weak self] state, version in
          guard let self else { return }
          if let version, !version.isEmpty {
            self.softwareVersion = version
          }
          self.otaUiState = state
        }
      )
      .store(in: &cancellables)
  }

  public func checkDecommissionEligibility() {
    Task { @MainActor [weak self] in
      guard let self = self, let device = self.device else { return }
      do {
        self.decommissionEligibility =
          try await device.decommissionEligibility
      } catch {
        Logger().warning("Decommission eligibility not available for this endpoint/device: \(error)")
        self.decommissionEligibility =
          HomeDevice.DecommissionEligibility.ineligible(
            reason: .other(
              Constants.notSupportedReason
            ))
      }
    }
  }

  public func decommissionDevice() async throws -> Set<String> {
    guard let device = self.device else {
      throw HomeError.internal(Constants.deviceNotFoundError)
    }
    return try await device.decommission()
  }
}
