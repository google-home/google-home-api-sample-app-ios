// Copyright 2026 Google LLC
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

/// An instance of `DeviceControl` representing a Matter Speaker endpoint (Device Type 0x0076).
final class SpeakerControl: DeviceControl {
  private enum Constants {
    static let controlIdentifier = "SpeakerControl"
    static let speakerTypeName = "Speaker"
    static let defaultImageName = "devices_other_symbol"
    static let onStatus = "On"
    static let offStatus = "Off"
    static let readyStatus = "Ready"
    static let powerLabel = "Speaker Power"
    static let powerAttributeKey = "Power"
    static let volumeAttributeKey = "Volume"
    static let bulletSeparator = " • "
  }

  private var speakerDeviceType: SpeakerDeviceType?
  private var cancellables: Set<AnyCancellable> = []
  private var rangeCancellable: AnyCancellable?
  private var volumeTask: Task<Void, Never>?

  // MARK: - Initialization

  override init(device: HomeDevice) throws {
    guard device.types.contains(SpeakerDeviceType.self) else {
      throw HomeSampleError.unableToCreateControlForDeviceType(
        deviceType: Constants.controlIdentifier)
    }
    try super.init(device: device)

    self.tileInfo = DeviceTileInfo.makeLoading(
      title: device.name, imageName: Constants.defaultImageName)

    self.device.types.subscribe(SpeakerDeviceType.self)
      .receive(on: DispatchQueue.main)
      .catch { [weak self] error in
        Logger().error("Error subscribing to SpeakerDeviceType: \(error)")
        self?.updateTileInfo()
        return Empty<SpeakerDeviceType, Never>().eraseToAnyPublisher()
      }
      .sink { [weak self] speakerDeviceType in
        guard let self = self else { return }
        self.speakerDeviceType = speakerDeviceType
        // A Matter Speaker endpoint (0x0076) exposes LevelControlTrait for output volume
        // and OnOffTrait for mute / power state.
        if let levelControlTrait = speakerDeviceType.matterTraits.levelControlTrait {
          if let existingRange = self.rangeControl {
            if self.volumeTask == nil {
              existingRange.rangeValue = levelControlTrait.makeRangeControl().rangeValue
            }
          } else {
            self.rangeControl = levelControlTrait.makeRangeControl()
            self.startRangeSubscription()
          }
        } else {
          self.rangeControl = nil
        }

        if let onOffTrait = speakerDeviceType.matterTraits.onOffTrait {
          let isOn = onOffTrait.attributes.onOff ?? true
          self.toggleControl = ToggleControl(
            isOn: isOn,
            label: Constants.powerLabel,
            description: isOn ? Constants.onStatus : Constants.offStatus
          ) { [weak self] in
            self?.toggleAction()
          }
        } else {
          self.toggleControl = nil
        }
        self.updateTileInfo()
      }
      .store(in: &self.cancellables)
  }

  deinit {
    volumeTask?.cancel()
  }

  // MARK: - Private

  /// Toggles the speaker power / mute state.
  private func toggleAction() {
    self.updateTileInfo(isBusy: true)
    Task { @MainActor [weak self] in
      guard
        let self = self,
        let onOffTrait = self.speakerDeviceType?.matterTraits.onOffTrait
      else {
        return
      }
      defer {
        self.updateTileInfo(isBusy: false)
      }
      do {
        try await onOffTrait.toggle()
      } catch {
        Logger().error("Failed to toggle Speaker on/off trait: \(error)")
      }
    }
  }

  /// Observes slider adjustments and updates the LevelControlTrait volume attribute.
  private func startRangeSubscription() {
    guard let rangeControl = self.rangeControl else { return }
    self.rangeCancellable?.cancel()
    self.rangeCancellable = rangeControl.$rangeValue.sink { [weak self] value in
      guard let levelControlTrait = self?.speakerDeviceType?.matterTraits.levelControlTrait else {
        return
      }

      let level = levelControlTrait.currentLevelFromPercentage(value)
      guard level != levelControlTrait.attributes.currentLevel else { return }

      self?.volumeTask?.cancel()
      self?.updateTileInfo(isBusy: true)
      self?.volumeTask = Task { @MainActor [weak self] in
        guard let self = self else { return }
        defer {
          if !Task.isCancelled {
            self.volumeTask = nil
          }
          self.updateTileInfo(isBusy: false)
        }
        do {
          try await levelControlTrait.moveToLevelWithOnOff(
            level: level,
            transitionTime: nil,
            optionsMask: [],
            optionsOverride: []
          )
        } catch {
          if !Task.isCancelled {
            Logger().error("Failed to adjust speaker volume: \(error)")
          }
        }
      }
    }
  }

  /// Updates the status card metadata displayed in the room grid.
  ///
  /// - Parameter isBusy: Whether an asynchronous trait operation is currently in progress.
  private func updateTileInfo(isBusy: Bool = false) {
    let onOffTrait = self.speakerDeviceType?.matterTraits.onOffTrait

    let hasOnOff = onOffTrait != nil
    let isOn = onOffTrait?.attributes.onOff ?? true

    var statusLabel = Constants.readyStatus
    var attributes: [[String: String]] = []

    if hasOnOff {
      attributes.append([Constants.powerAttributeKey: isOn ? Constants.onStatus : Constants.offStatus])
    }

    if let rangeControl = self.rangeControl {
      let percent = NSNumber(value: rangeControl.rangeValue).percentFormatted() ?? ""
      if hasOnOff {
        statusLabel = isOn ? "\(Constants.onStatus)\(Constants.bulletSeparator)\(percent)" : Constants.offStatus
      } else {
        statusLabel = "\(Constants.readyStatus)\(Constants.bulletSeparator)\(percent)"
      }
      attributes.append([Constants.volumeAttributeKey: percent])
    } else if hasOnOff {
      statusLabel = isOn ? Constants.onStatus : Constants.offStatus
    }

    self.tileInfo = DeviceTileInfo(
      title: self.device.name,
      typeName: Constants.speakerTypeName,
      imageName: Constants.defaultImageName,
      isActive: isOn,
      isBusy: isBusy,
      statusLabel: statusLabel,
      attributes: attributes,
      error: nil
    )
  }
}
