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

/// An instance of `DeviceControl` for managing Matter Chime devices (Device Type 0x010B).
final class ChimeControl: DeviceControl {
  private enum Constants {
    static let controlIdentifier = "ChimeControl"
    static let chimeTypeName = "Chime"
    static let defaultImageName = "devices_other_symbol"
    static let readyStatus = "Ready"
    static let installedSoundsKey = "Installed Sounds"
    static let selectedSoundKey = "Selected Sound"
    static let powerLabel = "Power"
    static let powerAttributeKey = "Power"
    static let onStatus = "On"
    static let offStatus = "Off"
    static let chimeSoundDropdownLabel = "Chime sound"
    static let defaultPlaySoundLabel = "Play Sound"
    static let defaultSoundOption = "Default Sound"
    static let volumeAttributeKey = "Volume"
    static let retryDelayNanoseconds: UInt64 = 1_200_000_000
    static let noRouteSubcode = 14
    static let noRouteErrorMessage = "No route found"
    static let playSoundDescription = "play the chime sound"
    static let adjustVolumeDescription = "adjust the chime volume"
  }

  private var chimeDeviceType: ChimeDeviceType?
  private var cancellables: Set<AnyCancellable> = []
  private var rangeCancellable: AnyCancellable?
  private var dropdownCancellable: AnyCancellable?

  private var soundOptionToIDMap: [String: UInt8] = [:]
  private var selectedSoundID: UInt8?
  private var volumeTask: Task<Void, Never>?
  private var dropdownTask: Task<Void, Never>?

  // MARK: - Initialization

  override init(device: HomeDevice) throws {
    guard device.types.contains(ChimeDeviceType.self) else {
      throw HomeSampleError.unableToCreateControlForDeviceType(
        deviceType: Constants.controlIdentifier)
    }
    try super.init(device: device)

    self.tileInfo = DeviceTileInfo.makeLoading(
      title: device.name, imageName: Constants.defaultImageName)

    // Subscribe to live trait changes on the ChimeDeviceType
    self.device.types.subscribe(ChimeDeviceType.self)
      .receive(on: DispatchQueue.main)
      .catch { [weak self] error in
        Logger().error("Error subscribing to ChimeDeviceType: \(error)")
        self?.updateTileInfo()
        return Empty<ChimeDeviceType, Never>().eraseToAnyPublisher()
      }
      .sink { [weak self] chimeDeviceType in
        guard let self = self else { return }
        self.chimeDeviceType = chimeDeviceType
        self.setupControls(for: chimeDeviceType)
        self.updateTileInfo()
      }
      .store(in: &self.cancellables)
  }

  deinit {
    volumeTask?.cancel()
    dropdownTask?.cancel()
  }

  // MARK: - Private

  /// Configures UI controls based on traits present on this Chime endpoint.
  ///
  /// - Parameter chimeDeviceType: The Matter Chime device type instance containing traits.
  private func setupControls(for chimeDeviceType: ChimeDeviceType) {
    // A Matter Chime endpoint (0x010B) combines up to three traits:
    // - Matter.ChimeTrait: lists installed sounds (installedChimeSounds), selects the active
    //   chime (setSelectedChime), and triggers chime playback (playChimeSound()).
    // - Matter.LevelControlTrait: adjusts chime output volume.
    // - Matter.OnOffTrait: toggles chime operational power / mute state.
    // ChimeMatterTraits only exposes chimeTrait directly; OnOffTrait and LevelControlTrait
    // are non-standard on Chime endpoints and must be queried via the traits dictionary.
    let chimeTrait = chimeDeviceType.matterTraits.chimeTrait
    let onOffTrait = chimeDeviceType.traits[Matter.OnOffTrait.self]
    let levelControlTrait = chimeDeviceType.traits[Matter.LevelControlTrait.self]

    // 1. Volume slider (LevelControlTrait)
    if let levelControlTrait = levelControlTrait {
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

    // 2. Power / Mute toggle (OnOffTrait)
    if let onOffTrait = onOffTrait {
      let isOn = onOffTrait.attributes.onOff ?? true
      self.toggleControl = ToggleControl(
        isOn: isOn,
        label: Constants.powerLabel,
        description: isOn ? Constants.onStatus : Constants.offStatus
      ) { [weak self] in
        self?.togglePowerAction(onOffTrait: onOffTrait)
      }
    } else {
      self.toggleControl = nil
    }

    // 3. Chime sound dropdown picker and Play button (Matter.ChimeTrait)
    if let chimeTrait = chimeTrait {
      let installedSounds = chimeTrait.attributes.installedChimeSounds ?? []
      var options: [String] = []
      var optionMap: [String: UInt8] = [:]

      if installedSounds.isEmpty {
        options.append(Constants.defaultSoundOption)
      } else {
        for sound in installedSounds {
          let soundID = sound.chimeID
          let label = sound.name.isEmpty ? "Sound \(soundID)" : "\(soundID): \(sound.name)"
          options.append(label)
          optionMap[label] = soundID
        }
      }

      self.soundOptionToIDMap = optionMap

      // Resolve the device-reported selectedChime ID to its picker label, falling back
      // to the first installed sound option when selectedChime is unset or unrecognized.
      let currentSelectedID = chimeTrait.attributes.selectedChime
      let initialSelection: String
      if let currentSelectedID = currentSelectedID,
         let matchingOption = optionMap.first(where: { $0.value == currentSelectedID })?.key {
        initialSelection = matchingOption
        self.selectedSoundID = currentSelectedID
      } else if let firstOption = options.first {
        initialSelection = firstOption
        self.selectedSoundID = optionMap[firstOption]
      } else {
        initialSelection = Constants.defaultSoundOption
        self.selectedSoundID = nil
      }

      if let existingDropdown = self.dropdownControl, existingDropdown.options == options {
        // Update the existing picker selection in place when no selection write is in flight.
        if self.dropdownTask == nil && existingDropdown.selection != initialSelection {
          existingDropdown.selection = initialSelection
        }
      } else {
        self.dropdownControl = DropdownControl(
          label: Constants.chimeSoundDropdownLabel,
          options: options,
          selection: initialSelection
        )
        self.startDropdownSubscription()
      }

      // Play Sound action button
      self.buttonGroupControl = ButtonGroupControl(buttons: [
        ButtonGroupItem(
          label: Constants.defaultPlaySoundLabel,
          isDisplayed: true,
          disabled: false
        ) { [weak self] in
          self?.playCurrentSelectedSoundAction(chimeTrait: chimeTrait)
        }
      ])
    } else {
      self.dropdownControl = nil
      self.buttonGroupControl = nil
    }
  }

  /// Sends commands to set the selected chime sound ID and trigger playback.
  ///
  /// - Parameter chimeTrait: The Matter Chime trait used to select and play the sound.
  private func playCurrentSelectedSoundAction(chimeTrait: Matter.ChimeTrait) {
    let soundID = self.selectedSoundID
    self.updateTileInfo(isBusy: true)
    Task { @MainActor [weak self] in
      guard let self = self else { return }
      defer {
        self.updateTileInfo(isBusy: false)
      }
      await self.performWithNoRouteRetry(Constants.playSoundDescription) {
        if let soundID = soundID {
          _ = try? await chimeTrait.update {
            $0.setSelectedChime(soundID)
          }
        }
        try await chimeTrait.playChimeSound()
        Logger().info("Played chime sound ID: \(soundID ?? 0)")
      }
    }
  }

  /// Runs `operation`, retrying it once after a short delay on a transient "No route found" error.
  ///
  /// - Parameters:
  ///   - description: Lower-case verb phrase naming the operation, used in the log messages.
  ///   - operation: The trait command to run.
  private func performWithNoRouteRetry(
    _ description: String,
    operation: () async throws -> Void
  ) async {
    do {
      try await operation()
      return
    } catch {
      guard self.isNoRouteFoundError(error) else {
        if !Task.isCancelled {
          Logger().error("Failed to \(description): \(error)")
        }
        return
      }
      Logger().warning("Hit 'No route found' trying to \(description), retrying once: \(error)")
    }

    // A Matter local command can transiently fail with "No route found" while Darwin's
    // mDNS resolution is still settling; wait briefly and retry the command once.
    try? await Task.sleep(nanoseconds: Constants.retryDelayNanoseconds)
    guard !Task.isCancelled else { return }
    do {
      try await operation()
    } catch {
      if !Task.isCancelled {
        Logger().error("Failed to \(description) on retry: \(error)")
      }
    }
  }

  /// Toggles the on/off power state of the chime device.
  ///
  /// - Parameter onOffTrait: The Matter On/Off trait to toggle.
  private func togglePowerAction(onOffTrait: Matter.OnOffTrait) {
    self.updateTileInfo(isBusy: true)
    Task { @MainActor [weak self] in
      guard let self = self else { return }
      defer {
        self.updateTileInfo(isBusy: false)
      }
      do {
        try await onOffTrait.toggle()
      } catch {
        Logger().error("Failed to toggle OnOffTrait for chime: \(error)")
      }
    }
  }

  /// Observes changes from the sound dropdown menu.
  private func startDropdownSubscription() {
    guard let dropdownControl = self.dropdownControl else { return }
    self.dropdownCancellable?.cancel()
    // dropFirst: creating the dropdown must not write to the device.
    self.dropdownCancellable = dropdownControl.$selection
      .dropFirst()
      .removeDuplicates()
      .sink { [weak self] selectedLabel in
        guard let self = self, let soundID = self.soundOptionToIDMap[selectedLabel] else { return }
        self.selectedSoundID = soundID
        // Skip echoes of device reports; write only when the device holds a different sound.
        guard let chimeTrait = self.chimeDeviceType?.matterTraits.chimeTrait,
          chimeTrait.attributes.selectedChime != soundID
        else { return }
        Logger().info("Selected chime sound: '\(selectedLabel)' (ID: \(soundID))")
        self.dropdownTask?.cancel()
        self.dropdownTask = Task { @MainActor [weak self] in
          guard let self = self, !Task.isCancelled else { return }
          defer {
            if !Task.isCancelled {
              self.dropdownTask = nil
            }
          }
          do {
            _ = try await chimeTrait.update {
              $0.setSelectedChime(soundID)
            }
            guard !Task.isCancelled else { return }
            self.updateTileInfo()
          } catch {
            guard !Task.isCancelled else { return }
            Logger().warning("Failed to persist selected chime sound \(soundID): \(error)")
          }
        }
      }
  }

  /// Observes volume slider interactions and updates the Matter LevelControlTrait.
  private func startRangeSubscription() {
    guard let rangeControl = self.rangeControl else { return }
    self.rangeCancellable?.cancel()
    self.rangeCancellable = rangeControl.$rangeValue.sink { [weak self] value in
      // Read the trait on every value; a captured snapshot would compare against a stale level.
      guard
        let levelControlTrait = self?.chimeDeviceType?.traits[Matter.LevelControlTrait.self]
      else {
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
        await self.performWithNoRouteRetry(Constants.adjustVolumeDescription) {
          try await levelControlTrait.moveToLevelWithOnOff(
            level: level,
            transitionTime: nil,
            optionsMask: [],
            optionsOverride: []
          )
        }
      }
    }
  }

  /// Determines whether the given error is a transient "No route found" error.
  ///
  /// - Parameter error: The error thrown by a trait command.
  /// - Returns: `true` if the error indicates a missing Matter route; otherwise, `false`.
  private func isNoRouteFoundError(_ error: Error) -> Bool {
    if let homeError = error as? HomeError {
      if homeError.subcodes.contains(Constants.noRouteSubcode)
        || homeError.message.contains(Constants.noRouteErrorMessage) {
        return true
      }
    }
    let nsError = error as NSError
    if nsError.code == Constants.noRouteSubcode
      || nsError.localizedDescription.contains(Constants.noRouteErrorMessage) {
      return true
    }
    return false
  }

  /// Updates the status card metadata displayed in the room grid.
  ///
  /// - Parameter isBusy: Whether an asynchronous trait operation is currently in progress.
  private func updateTileInfo(isBusy: Bool = false) {
    var statusLabel = Constants.readyStatus
    var attributes: [[String: String]] = []
    var isActive = true

    if let onOffTrait = self.chimeDeviceType?.traits[Matter.OnOffTrait.self],
       let isOn = onOffTrait.attributes.onOff {
      isActive = isOn
      attributes.append([Constants.powerAttributeKey: isOn ? Constants.onStatus : Constants.offStatus])
      if !isOn {
        statusLabel = Constants.offStatus
      }
    }

    let chimeTrait = self.chimeDeviceType?.matterTraits.chimeTrait
    if let chimeTrait = chimeTrait {
      if let sounds = chimeTrait.attributes.installedChimeSounds, !sounds.isEmpty {
        if isActive {
          statusLabel = "\(Constants.installedSoundsKey): \(sounds.count)"
        }
        attributes.append([Constants.installedSoundsKey: "\(sounds.count)"])

        if let selected = self.selectedSoundID ?? chimeTrait.attributes.selectedChime {
          let soundName = sounds.first(where: { $0.chimeID == selected })?.name ?? ""
          let selectedSoundName = soundName.isEmpty ? "Sound \(selected)" : soundName
          attributes.append([Constants.selectedSoundKey: selectedSoundName])
        }
      }
    }

    if let rangeControl = self.rangeControl {
      let percent = NSNumber(value: rangeControl.rangeValue).percentFormatted() ?? ""
      attributes.append([Constants.volumeAttributeKey: percent])
    }

    self.tileInfo = DeviceTileInfo(
      title: self.device.name,
      typeName: Constants.chimeTypeName,
      imageName: Constants.defaultImageName,
      isActive: isActive,
      isBusy: isBusy,
      statusLabel: statusLabel,
      attributes: attributes,
      error: nil
    )
  }
}
