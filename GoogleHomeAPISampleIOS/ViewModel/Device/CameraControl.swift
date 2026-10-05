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

private enum Constants {
  static let deviceNotSupportedMessage = "Device does not support GoogleCameraDeviceType"
  static let loadingImageName = "camera_symbol"
  static let activeImageName = "videocam_fill1_symbol"
  static let inactiveImageName = "videocam_symbol"
  static let onStatusLabel = "On"
  static let offStatusLabel = "Off"
  static let typeName = "Camera"
  static let lightLabel = "Light"
  static let outletLabel = "Outlet"
  static let identitySeparator = "|"
}

/// A `DeviceControl` instance representing a camera that has video streaming capabilities.
final class CameraControl: DeviceControl {
  private struct SubEndpointTraits {
    let identity: String
    let label: String
    let onOffTrait: Matter.OnOffTrait
    let levelControlTrait: Matter.LevelControlTrait?
  }

  private static let subEndpointTypes: [(type: any DeviceType.Type, label: String)] = [
    (DimmableLightDeviceType.self, Constants.lightLabel),
    (OnOffLightDeviceType.self, Constants.lightLabel),
    (ColorTemperatureLightDeviceType.self, Constants.lightLabel),
    (ExtendedColorLightDeviceType.self, Constants.lightLabel),
    (OnOffPluginUnitDeviceType.self, Constants.outletLabel),
  ]

  private var cameraDeviceType: GoogleCameraDeviceType?
  private var onOffTrait: Matter.OnOffTrait?
  private var levelControlTrait: Matter.LevelControlTrait?
  private var rangeCancellable: AnyCancellable?
  // Identity of the secondary endpoint the current controls were built for.
  private var boundSubEndpointIdentity: String?
  // Last level sent by the slider, used to suppress duplicate commands.
  private var lastSentLevel: UInt8?
  // Suppresses the slider sink while applying a device-reported level update.
  private var isApplyingReportedLevel = false
  private var cancellables: Set<AnyCancellable> = []

  // MARK: - Initialization

  public override init(device: HomeDevice) throws {
    guard device.types.contains(GoogleCameraDeviceType.self) else {
      throw HomeError.notFound(Constants.deviceNotSupportedMessage)
    }
    try super.init(device: device)

    self.tileInfo = .makeLoading(title: device.name, imageName: Constants.loadingImageName)

    self.device.types.subscribeAll()
      .receive(on: DispatchQueue.main)
      .catch { error in
        Logger().error("Error getting DeviceTypeCollection: \(error)")
        return Empty<DeviceTypeCollection, Never>().eraseToAnyPublisher()
      }
      .sink { [weak self] collection in
        guard let self = self else { return }
        if let cameraDeviceType = collection.getAll(of: GoogleCameraDeviceType.self).first {
          self.cameraDeviceType = cameraDeviceType
          self.updateTileInfo()
        }
        let subEndpointTraits = self.resolveSubEndpointTraits(from: collection)
        self.bindSubEndpointControls(traits: subEndpointTraits)
      }
      .store(in: &self.cancellables)
  }

  // MARK: - Private

  // Resolves the first controllable secondary Matter endpoint in the collection.
  private func resolveSubEndpointTraits(
    from collection: DeviceTypeCollection
  ) -> SubEndpointTraits? {
    for (subEndpointType, label) in Self.subEndpointTypes {
      guard
        let endpoint = collection.getAll(of: subEndpointType).first,
        let onOffTrait = endpoint.traits[Matter.OnOffTrait.self]
      else {
        continue
      }
      let levelControlTrait = endpoint.traits[Matter.LevelControlTrait.self]
      let identity = [
        endpoint.identifier,
        endpoint.metadata.objectID,
        String(levelControlTrait != nil),
      ].joined(separator: Constants.identitySeparator)
      return SubEndpointTraits(
        identity: identity,
        label: label,
        onOffTrait: onOffTrait,
        levelControlTrait: levelControlTrait
      )
    }
    return nil
  }

  // Binds toggle and range controls for the resolved secondary endpoint traits.
  private func bindSubEndpointControls(traits: SubEndpointTraits?) {
    guard let traits = traits else {
      self.clearSubEndpointControls()
      return
    }

    // Keep the latest trait snapshot so commands run against current state.
    self.onOffTrait = traits.onOffTrait
    self.levelControlTrait = traits.levelControlTrait

    let isEndpointUnchanged = traits.identity == self.boundSubEndpointIdentity
    let isOn = traits.onOffTrait.attributes.onOff ?? false
    let statusDescription = isOn ? Constants.onStatusLabel : Constants.offStatusLabel
    if !isEndpointUnchanged
      || self.toggleControl?.isOn != isOn
      || self.toggleControl?.description != statusDescription
    {
      self.toggleControl = ToggleControl(
        isOn: isOn,
        label: traits.label,
        description: statusDescription
      ) { [weak self] in
        self?.toggleSubEndpointAction()
      }
    }

    // Rebuild the slider only when the resolved endpoint identity changes.
    guard !isEndpointUnchanged else {
      self.refreshRangeControlFromReportedLevel()
      return
    }
    self.boundSubEndpointIdentity = traits.identity

    if let levelControlTrait = self.levelControlTrait {
      self.rangeControl = levelControlTrait.makeRangeControl()
      self.startSubEndpointRangeSubscription()
    } else {
      self.rangeCancellable?.cancel()
      self.rangeCancellable = nil
      self.rangeControl = nil
      self.lastSentLevel = nil
    }
  }

  // Resets all secondary endpoint state and UI controls when no sub-endpoint is present.
  private func clearSubEndpointControls() {
    self.onOffTrait = nil
    self.levelControlTrait = nil
    self.boundSubEndpointIdentity = nil
    self.lastSentLevel = nil
    self.rangeCancellable?.cancel()
    self.rangeCancellable = nil
    self.toggleControl = nil
    self.rangeControl = nil
  }

  // Updates the existing slider to match a device-reported level without rebuilding it.
  private func refreshRangeControlFromReportedLevel() {
    guard
      let levelControlTrait = self.levelControlTrait,
      let rangeControl = self.rangeControl,
      let reportedLevel = levelControlTrait.attributes.currentLevel,
      reportedLevel != self.lastSentLevel
    else { return }

    self.lastSentLevel = reportedLevel
    self.isApplyingReportedLevel = true
    rangeControl.rangeValue = levelControlTrait.makeRangeControl().rangeValue
    self.isApplyingReportedLevel = false
  }

  // Toggles the secondary endpoint's on/off state.
  private func toggleSubEndpointAction() {
    self.toggleControl?.isOn.toggle()
    self.updateTileInfo(isBusy: true)
    Task { @MainActor [weak self] in
      guard let self = self, let onOffTrait = self.onOffTrait else { return }
      do {
        try await onOffTrait.toggle()
      } catch {
        self.toggleControl?.isOn = onOffTrait.attributes.onOff ?? false
        self.updateTileInfo(isBusy: false)
        Logger().error("Failed to toggle sub-endpoint: \(error)")
      }
    }
  }

  // Subscribes to slider changes and sends level updates to `levelControlTrait`.
  private func startSubEndpointRangeSubscription() {
    guard
      let rangeControl = self.rangeControl,
      let initialLevelTrait = self.levelControlTrait
    else { return }
    self.rangeCancellable?.cancel()
    self.lastSentLevel = initialLevelTrait.attributes.currentLevel
    self.rangeCancellable = rangeControl.$rangeValue
      .dropFirst()
      .sink { [weak self] value in
        guard
          let self = self,
          !self.isApplyingReportedLevel,
          let levelControlTrait = self.levelControlTrait
        else { return }
        let level = levelControlTrait.currentLevelFromPercentage(value)
        guard level != self.lastSentLevel else { return }
        self.lastSentLevel = level
        self.updateTileInfo(isBusy: true)

        Task { @MainActor [weak self] in
          guard let self = self, let levelControlTrait = self.levelControlTrait else { return }
          do {
            try await levelControlTrait.moveToLevelWithOnOff(
              level: level,
              transitionTime: nil,
              optionsMask: [],
              optionsOverride: []
            )
          } catch {
            self.lastSentLevel = nil
            self.refreshRangeControlFromReportedLevel()
            self.updateTileInfo(isBusy: false)
            Logger().error("Failed to adjust sub-endpoint level: \(error)")
          }
        }
      }
  }

  // Updates the camera dashboard tile information based on active traits.
  private func updateTileInfo(isBusy: Bool = false) {
    guard let cameraDeviceType = self.cameraDeviceType else { return }

    let isOn =
      cameraDeviceType.googleTraits.pushAvStreamTransportTrait?
      .attributes.currentConnections?.contains(where: { $0.transportStatus == .active }) ?? false
    let imageName = isOn ? Constants.activeImageName : Constants.inactiveImageName
    let statusLabel = isOn ? Constants.onStatusLabel : Constants.offStatusLabel

    self.tileInfo = DeviceTileInfo(
      title: self.device.name,
      typeName: Constants.typeName,
      imageName: imageName,
      isActive: isOn,
      isBusy: isBusy,
      statusLabel: statusLabel,
      attributes: [],
      error: nil
    )
  }
}
