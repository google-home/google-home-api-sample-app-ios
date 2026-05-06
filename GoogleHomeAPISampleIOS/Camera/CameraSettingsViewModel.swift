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

extension UInt8 {
  fileprivate init(_ bool: Bool) {
    self = bool ? 1 : 0
  }
}

private enum BatteryUsageLabel: String {
  case extended = "EXTENDED"
  case balanced = "BALANCED"
  case performance = "PERFORMANCE"
  case custom = "CUSTOM"
}

/// A ViewModel handling the camera device settings.
@Observable
@MainActor
class CameraSettingsViewModel<T: DeviceType> {

  // MARK: - Settings Vars

  /// String conversion for the Google.CameraAvStreamManagementTrait.TriStateAutoEnum enum.
  public func triStateAutoEnumDisplayName(
    setting: Google.CameraAvStreamManagementTrait.TriStateAutoEnum
  ) -> String {
    switch setting {
    case .auto:
      return "Auto"
    case .on:
      return "On"
    case .off:
      return "Off"
    default:
      return "Unknown"
    }
  }

  /// String conversion for the Google.CameraAvStreamManagementTrait.ThreeLevelAutoEnum enum.
  public func threeLevelAutoEnumDisplayName(
    setting: Google.CameraAvStreamManagementTrait.ThreeLevelAutoEnum
  ) -> String {
    switch setting {
    case .auto:
      return "Auto"
    case .low:
      return "Low"
    case .high:
      return "High"
    default:
      return "Unknown"
    }
  }

  /// String conversion for the Matter.PowerSourceTrait.BatChargeLevelEnum enum.
  public func batteryChargeLevelDisplayName(
    setting: Matter.PowerSourceTrait.BatChargeLevelEnum?
  ) -> String {
    guard let setting = setting else { return "Unknown" }
    switch setting {
    case .ok:
      return "OK"
    case .warning:
      return "Warning"
    case .critical:
      return "Critical"
    default:
      return "Unknown"
    }
  }

  /// String conversion for the Matter.PowerSourceTrait.BatChargeStateEnum enum.
  public func batteryChargeStateDisplayName(
    setting: Matter.PowerSourceTrait.BatChargeStateEnum?
  ) -> String {
    guard let setting = setting else { return "Unknown" }
    switch setting {
    case .isCharging:
      return "Charging"
    case .isAtFullCharge:
      return "Full"
    case .isNotCharging:
      return "Not Charging"
    default:
      return "Unknown"
    }
  }

  /// String conversion for the wake up sensitivity setting integer.
  public func wakeUpSensitivityDisplayName(setting: UInt8) -> String {
    switch setting {
    case 1:
      return "Low"
    case 5:
      return "Medium"
    case 10:
      return "High"
    default:
      return ""
    }
  }

  /// String conversion for the recordingmode setting integer.
  public func recordingModeDisplayName(setting: UInt8) -> String {
    guard let supported = recordingModeTrait?.attributes.supportedRecordingModes,
          Int(setting) < supported.count
    else {
      return "Unknown (\(setting))"
    }

    let mode = supported[Int(setting)].recordingMode
    switch mode {
    case .disabled:
      return "Off"
    case .cvr:
      return "Continuous"
    case .ebr:
      return "Event Based"
    case .images:
      return "Images"
    case .liveView:
      return "Live View"
    case .etr:
      return "Event Triggered"
    default:
      return "Unknown"
    }
  }

  /// String conversion for the battery usage setting enum.
  public func batteryUsageDisplayName(setting: CameraSettingsViewModel.BatteryUsageSetting)
    -> String
  {
    BatteryUsageLabel(rawValue: setting.label)?.rawValue.capitalized ?? setting.label
  }

  /// String conversion for the external chime setting enum.
  public func externalChimeDisplayName(setting: Google.ChimeTrait.ExternalChimeType) -> String {
    switch setting {
    case .none:
      return "None"
    case .electronic:
      return "Electronic"
    case .mechanical:
      return "Mechanical"
    default:
      return "Unknown"
    }
  }

  /// Setting controller for the microphone on/off setting.
  public private(set) var microphoneOnController: CameraSetting<Bool> =
    CameraSetting<Bool>(defaultValue: true)
  /// Setting controller for the audio recording on/off setting.
  public private(set) var audioRecordingOnController: CameraSetting<Bool> =
    CameraSetting<Bool>(defaultValue: true)
  /// Accepted values for the image rotation setting (in degrees).
  public let imageRotationSettings: [Int] = [0, 180]
  /// Setting controller for the image rotation setting.
  public private(set) var imageRotationController: CameraSetting<Int> =
    CameraSetting<Int>(defaultValue: 0)
  /// Accepted values for the night vision setting.
  public let nightVisionSettings: [Google.CameraAvStreamManagementTrait.TriStateAutoEnum] = [
    .auto, .on, .off,
  ]
  /// Setting controller for the night vision setting.
  public private(set) var nightVisionController:
    CameraSetting<Google.CameraAvStreamManagementTrait.TriStateAutoEnum> =
      CameraSetting<Google.CameraAvStreamManagementTrait.TriStateAutoEnum>(
        defaultValue: .auto)
  public let statusLightBrightnessSettings:
    [Google.CameraAvStreamManagementTrait.ThreeLevelAutoEnum] = [.auto, .low, .high]
  /// Setting controller for the status light brightness setting.
  public private(set) var statusLightBrightnessController:
    CameraSetting<Google.CameraAvStreamManagementTrait.ThreeLevelAutoEnum> =
      CameraSetting<Google.CameraAvStreamManagementTrait.ThreeLevelAutoEnum>(
        defaultValue: .auto)
  /// Setting controller for the speaker volume setting.
  public private(set) var speakerVolumeController: CameraSetting<Double> =
    CameraSetting<Double>(defaultValue: 100, manualUpdate: true)

  /// Accepted values for the recording mode settings.
  public private(set) var recordingModeSettings: [UInt8] = []
  /// Setting controller for the recording mode setting.
  public private(set) var recordingModeController: CameraSetting<UInt8> =
    CameraSetting<UInt8>(defaultValue: 0)

  /// Struct to hold the doorbell chime names and ids.
  public struct DoorbellChime: Hashable, Identifiable {
    public var id: UInt8
    public var displayName: String
  }
  /// The available doorbell chimes for the doorbell chime setting.
  public private(set) var doorbellChimeSettings: [DoorbellChime] = []
  /// Binding for the doorbell chime setting.
  public private(set) var doorbellChimeController: CameraSetting<DoorbellChime> =
    CameraSetting<DoorbellChime>(defaultValue: DoorbellChime(id: 0, displayName: ""))
  /// Accepted values for the external chime setting enum.
  public let externalChimeSettings: [Google.ChimeTrait.ExternalChimeType] = [
    .none, .electronic, .mechanical,
  ]
  /// Setting controller for the external chime setting.
  public private(set) var externalChimeController:
    CameraSetting<Google.ChimeTrait.ExternalChimeType> =
      CameraSetting<Google.ChimeTrait.ExternalChimeType>(defaultValue: .none)

  /// Accepted values for the wake up sensitivity setting.
  public let wakeUpSensitivitySettings: [UInt8] = [1, 5, 10]
  /// Setting controller for the wake up sensitivity setting.
  public private(set) var wakeUpSensitivityController: CameraSetting<UInt8> =
    CameraSetting<UInt8>(defaultValue: 1)
  /// Accepted values for the max event length setting.
  public let maxEventLengthSettings: [UInt32] = [10, 15, 30, 60, 120, 180]
  /// Setting controller for the max event length setting.
  public private(set) var maxEventLengthController: CameraSetting<UInt32> =
    CameraSetting<UInt32>(defaultValue: 10)

  /// The current battery percentage remaining for the device.
  public private(set) var batteryPercentRemaining: UInt8?
  /// The current descriptive capacity remaining for the device.
  public private(set) var descriptiveCapacityRemaining: Matter.PowerSourceTrait.BatChargeLevelEnum?
  /// The current charging state for the device.
  public private(set) var chargingState: Matter.PowerSourceTrait.BatChargeStateEnum?

  /// Setting controller for the auto battery saver setting.
  public private(set) var autoBatterySaverEnabledController: CameraSetting<Bool> =
    CameraSetting<Bool>(defaultValue: false)
  /// Struct to hold the battery usage setting values and their corresponding indices.
  public struct BatteryUsageSetting: Hashable {
    public var idx: UInt8
    public var label: String
  }
  /// The available battery usage settings.
  public var batteryUsageSettings: [BatteryUsageSetting] {
    energyPreferenceTrait?.attributes.energyBalances?.enumerated().compactMap { index, setting in
      BatteryUsageSetting(idx: UInt8(index), label: setting.label ?? "Unknown")
    } ?? []
  }
  /// Setting controller for the battery usage setting.
  public private(set) var batteryUsageController: CameraSetting<BatteryUsageSetting> =
    CameraSetting<BatteryUsageSetting>(
      defaultValue: BatteryUsageSetting(idx: 0, label: BatteryUsageLabel.custom.rawValue))

  /// The last connected time for the device.
  public private(set) var lastConnectedTime: Date?
  /// Setting controller for the analytics on/off setting.
  public private(set) var analyticsEnabledController: CameraSetting<Bool> =
    CameraSetting<Bool>(defaultValue: false)
  /// Setting controller for the log upload enabled setting.
  public private(set) var logUploadEnabledController: CameraSetting<Bool> =
    CameraSetting<Bool>(defaultValue: false)

  /// Vendor name for the device from the Matter BasicInformationTrait.
  public private(set) var vendorName: String?
  /// Product name for the device from the Matter BasicInformationTrait.
  public private(set) var productName: String?
  /// Software version string for the device from the Matter basicInformationTrait.
  public private(set) var softwareVersionString: String?

  /// Serial number for the device from the Matter ExtendedBasicInformationTrait.
  public private(set) var serialNumber: String?

  public private(set) var settingsInitialized: Bool = false

  private var streamManagementTrait: Google.CameraAvStreamManagementTrait? {
    didSet {
      self.updateSettingsFromStreamManagementTrait()
    }
  }
  private var recordingModeTrait: Google.RecordingModeTrait? {
    didSet {
      self.updateSettingsFromRecordingModeTrait()
    }
  }
  private var doorbellChimeTrait: Google.ChimeTrait? {
    didSet {
      self.updateSettingsFromDoorbellChimeTrait()
    }
  }
  private var pushAvStreamTransportTrait: Google.PushAvStreamTransportTrait? {
    didSet {
      Task {
        await self.updateSettingsFromPushAvStreamTransportTrait()
      }
    }
  }
  private var powerSourceTrait: Matter.PowerSourceTrait? {
    didSet {
      Task {
        await self.updateSettingsFromPowerSourceTrait()
      }
    }
  }
  private var energyPreferenceTrait: Google.EnergyPreferenceTrait? {
    didSet {
      self.updateSettingsFromEnergyPreferenceTrait()
    }
  }
  private var extendedGeneralDiagnosticsTrait: Google.ExtendedGeneralDiagnosticsTrait? {
    didSet {
      Task {
        await self.updateSettingsFromExtendedGeneralDiagnosticsTrait()
      }
    }
  }
  private var extendedBasicInformationTrait: Google.ExtendedBasicInformationTrait? {
    didSet {
      Task {
        await self.updateSettingsFromExtendedBasicInformationTrait()
      }
    }
  }

  private let home: Home
  private let deviceID: String
  private var device: HomeDevice?
  private let initiatingFlow: CameraSettingsView<T>.InitiatingFlow

  // The settings that are currently displayed in the UI.
  // It is assumed that all cameras will display the microphone and camera settings.
  // Doorbells will display the doorbell setting.
  // Cameras with battery power will display the battery setting.
  public private(set) var displayedSettings: SettingsDisplayed = []
  private var cancellables = Set<AnyCancellable>()

  public init(home: Home, deviceID: String, initiatingFlow: CameraSettingsView<T>.InitiatingFlow) {

    self.home = home
    self.deviceID = deviceID
    self.initiatingFlow = initiatingFlow

    // During oobe, we only want to display the microphone setting.
    if self.initiatingFlow == .oobe {
      self.displayedSettings.insert(.microphone)
    }

    self.home.device(id: deviceID)
      .removeDuplicates()
      .receive(on: DispatchQueue.main)
      .flatMap { [weak self] device -> AnyPublisher<DeviceTypeCollection, HomeError> in
        guard let self = self else { return Empty().eraseToAnyPublisher() }
        Logger().info("Device: \(device.id)")
        self.device = device
        return device.types.subscribeAll().eraseToAnyPublisher()
      }
      .receive(on: DispatchQueue.main)
      .sink { completion in
        switch completion {
        case .finished:
          Logger().info("Device subscription finished.")
        case .failure(let error):
          Logger().error("Received unexpected device subscription error: \(error.localizedDescription)")
        }
      } receiveValue: { [weak self] deviceTypeCollection in
        guard let deviceType = deviceTypeCollection.getAll(of: T.self).first else { return }
        Logger().info("Device type: \(deviceType.debugDescription)")
        guard let self = self else { return }
        self.streamManagementTrait = deviceType.traits[Google.CameraAvStreamManagementTrait.self]
        self.doorbellChimeTrait = deviceType.traits[Google.ChimeTrait.self]
        self.pushAvStreamTransportTrait = deviceType.traits[Google.PushAvStreamTransportTrait.self]
        self.extendedGeneralDiagnosticsTrait = deviceType.traits[Google.ExtendedGeneralDiagnosticsTrait.self]
        self.powerSourceTrait = deviceType.traits[Matter.PowerSourceTrait.self]
        self.energyPreferenceTrait = deviceType.traits[Google.EnergyPreferenceTrait.self]
        self.extendedBasicInformationTrait = deviceType.traits[Google.ExtendedBasicInformationTrait.self]
        self.recordingModeTrait = deviceType.traits[Google.RecordingModeTrait.self]

        if deviceTypeCollection.contains(RootNodeDeviceType.self) {
          let rootNodeDeviceType = deviceTypeCollection.getAll(of: RootNodeDeviceType.self).first
          if let basicInformationTrait = rootNodeDeviceType?.traits[Matter.BasicInformationTrait.self] {
            self.vendorName = basicInformationTrait.attributes.vendorName
            self.productName = basicInformationTrait.attributes.productName
            self.softwareVersionString = basicInformationTrait.attributes.softwareVersionString
          }
        }

        if !self.settingsInitialized {

          self.initializeSettingsControllers()

          if self.initiatingFlow == .settings {
            self.displayedSettings.insert(.microphone)
            self.displayedSettings.insert(.camera)

            if deviceType.traits.contains(Google.ExtendedPowerSourceTrait.self) {
              self.displayedSettings.insert(.battery)
            }

            if deviceType.traits.contains(Google.RecordingModeTrait.self) {
              self.displayedSettings.insert(.recording)
            }

            if deviceType is GoogleDoorbellDeviceType {
              self.displayedSettings.insert(.doorbell)
            }

            self.displayedSettings.insert(.information)
            self.displayedSettings.insert(.diagnostics)
          }
        }
        self.settingsInitialized = true

      }
      .store(in: &self.cancellables)
  }

  private func initializeSettingsControllers() {
    // The callback passed to the setUpdateFunc must be weakified to avoid a retain cycle between
    // the setting controller and the view model.
    self.microphoneOnController.onUpdate = { [weak self] on in await self?.setMicrophone(on: on) }
    self.audioRecordingOnController.onUpdate =
      { [weak self] on in await self?.setAudioRecording(on: on) }
    self.imageRotationController.onUpdate =
      { [weak self] value in await self?.setImageRotation(to: value) }
    self.nightVisionController.onUpdate =
      { [weak self] value in await self?.setNightVision(to: value) }
    self.doorbellChimeController.onUpdate =
      { [weak self] value in await self?.setDoorbellChime(doorbellChime: value) }
    self.statusLightBrightnessController.onUpdate =
      { [weak self] value in await self?.setStatusLightBrightness(to: value) }
    self.speakerVolumeController.onUpdate =
      { [weak self] value in await self?.setSpeakerVolume(to: value) }
    self.wakeUpSensitivityController.onUpdate =
      { [weak self] value in await self?.setWakeUpSensitivity(to: value) }
    self.maxEventLengthController.onUpdate =
      { [weak self] value in await self?.setMaxEventLength(to: value) }
    self.externalChimeController.onUpdate =
      { [weak self] value in await self?.setExternalChime(to: value) }
    self.autoBatterySaverEnabledController.onUpdate =
      { [weak self] value in await self?.setEnergyPreference(to: value) }
    self.batteryUsageController.onUpdate =
      { [weak self] value in await self?.setBatteryUsage(to: value) }
    self.analyticsEnabledController.onUpdate =
      { [weak self] value in await self?.setAnalyticsEnabled(to: value) }
    self.logUploadEnabledController.onUpdate =
      { [weak self] value in await self?.setLogUploadEnabled(to: value) }
    self.recordingModeController.onUpdate =
      { [weak self] value in await self?.setRecordingMode(to: value) }
  }

  private func updateSettingsFromStreamManagementTrait() {

    guard let streamManagementTrait else {
      Logger().error("Stream management trait not available")
      return
    }

    Logger().info("Initializing settings from trait attributes")
    // We use map when required to map the values from the api to the correct types and keep them
    // nullable for correct logging and handling.
    self.microphoneOnController.updateValue(
      value: streamManagementTrait.attributes.microphoneMuted.map { !$0 })
    self.audioRecordingOnController.updateValue(
      value: streamManagementTrait.attributes.recordingMicrophoneMuted.map { !$0 })
    self.imageRotationController.updateValue(
      value: streamManagementTrait.attributes.imageRotation.map { Int($0) })
    self.nightVisionController.updateValue(
      value: streamManagementTrait.attributes.nightVision)
    self.statusLightBrightnessController.updateValue(
      value: streamManagementTrait.attributes.statusLightBrightness)
    self.speakerVolumeController.updateValue(
      value: streamManagementTrait.attributes.speakerVolumeLevel.map { Double($0) })
  }

  private func updateSettingsFromRecordingModeTrait() {
    guard let recordingModeTrait else {
      Logger().error("Recording mode trait not available")
      return
    }

    if let availableRecordingModes = recordingModeTrait.attributes.availableRecordingModes {
      self.recordingModeSettings = availableRecordingModes
    }

    if let selectedRecordingMode = recordingModeTrait.attributes.selectedRecordingMode {
      self.recordingModeController.updateValue(value: selectedRecordingMode)
    }
  }

  private func updateSettingsFromDoorbellChimeTrait() {
    guard let doorbellChimeTrait else {
      Logger().error("Doorbell chime trait not available")
      return
    }

    self.doorbellChimeSettings =
      doorbellChimeTrait.attributes.installedChimeSounds?.compactMap { chimeSound in
        return DoorbellChime(id: chimeSound.chimeID, displayName: chimeSound.name)
      } ?? []

    self.doorbellChimeController.updateValue(
      value: self.doorbellChimeSettings.first {
        $0.id == doorbellChimeTrait.attributes.selectedChime
      }
    )

    self.externalChimeController.updateValue(
      value: doorbellChimeTrait.attributes.externalChime
    )

  }

  private func updateSettingsFromPushAvStreamTransportTrait() async {
    do {
      let connection = try await getRecordingConnection()

      guard let transportOptions = connection?.transportOptions else {
        Logger().error("Transport options not available")
        return
      }

      if let wakeUpSensitivity = transportOptions.triggerOptions.motionSensitivity {
        self.wakeUpSensitivityController.updateValue(
          value: wakeUpSensitivity)
      }

      if let maxEventLength = transportOptions.triggerOptions.motionTimeControl?.maxDuration {
        self.maxEventLengthController.updateValue(
          value: maxEventLength)
      }

    } catch {
      Logger().error("Failed to get transport configurations: \(error)")
      return
    }
  }

  private func updateSettingsFromPowerSourceTrait() async {
    guard let powerSourceTrait else {
      Logger().error("Power source trait not available")
      return
    }

    self.batteryPercentRemaining = powerSourceTrait.attributes.batPercentRemaining
    self.descriptiveCapacityRemaining = powerSourceTrait.attributes.batChargeLevel
    self.chargingState = powerSourceTrait.attributes.batChargeState
  }

  private func updateSettingsFromEnergyPreferenceTrait() {
    guard let energyPreferenceTrait else {
      Logger().error("Energy preference trait not available")
      return
    }

    let attributes = energyPreferenceTrait.attributes

    self.autoBatterySaverEnabledController.updateValue(
      value: attributes.currentLowPowerModeSensitivity == UInt8(true)
    )

    let selected =
      batteryUsageSettings.first { $0.idx == attributes.currentEnergyBalance }
      ?? BatteryUsageSetting(idx: 0, label: BatteryUsageLabel.custom.rawValue)

    self.batteryUsageController.updateValue(value: selected)
  }

  private func updateSettingsFromExtendedGeneralDiagnosticsTrait() async {
    guard let extendedGeneralDiagnosticsTrait else {
      Logger().error("Extended general diagnostics trait not available")
      return
    }

    if let lastConnectedTimeStamp = extendedGeneralDiagnosticsTrait.attributes.lastContactTimestamp
    {
      self.lastConnectedTime = Date(timeIntervalSince1970: Double(lastConnectedTimeStamp))
    }

    self.analyticsEnabledController.updateValue(
      value: extendedGeneralDiagnosticsTrait.attributes.analyticsEnabled)
    self.logUploadEnabledController.updateValue(
      value: extendedGeneralDiagnosticsTrait.attributes.logUploadEnabled)
  }

  private func updateSettingsFromExtendedBasicInformationTrait() async {
    guard let extendedBasicInformationTrait else {
      Logger().error("Extended basic information trait not available")
      return
    }

    do {
      let response = try await extendedBasicInformationTrait.getSerialNumber()
      self.serialNumber = response.serialNumber
    } catch {
      Logger().error("Failed to get serial number: \(error)")
    }
  }

  private func setMicrophone(on: Bool) async {
    do {
      _ = try await self.streamManagementTrait?.update {
        $0.setMicrophoneMuted(!on)
      }
    } catch {
      Logger().error("Failed to set microphone: \(error)")
    }
  }

  private func setAudioRecording(on: Bool) async {
    do {
      _ = try await self.streamManagementTrait?.update {
        $0.setRecordingMicrophoneMuted(!on)
      }
    } catch {
      Logger().error("Failed to set audio recording: \(error)")
    }
  }

  private func setImageRotation(to value: Int) async {
    guard let streamManagementTrait else {
      Logger().error("Stream management trait not available")
      return
    }

    do {
      _ = try await streamManagementTrait.update {
        $0.setImageRotation(UInt16(value))
      }
    } catch {
      Logger().error("Failed to set image rotation: \(error)")
    }
  }

  private func setNightVision(
    to value: Google.CameraAvStreamManagementTrait.TriStateAutoEnum
  ) async {
    guard let streamManagementTrait else {
      Logger().error("Stream management trait not available")
      return
    }

    do {
      _ = try await streamManagementTrait.update {
        $0.setNightVision(value)
      }
    } catch {
      Logger().error("Failed to set night vision: \(error)")
    }
  }

  private func setSpeakerVolume(to value: Double) async {
    guard let streamManagementTrait else {
      Logger().error("Stream management trait not available")
      return
    }

    do {
      _ = try await streamManagementTrait.update {
        $0.setSpeakerVolumeLevel(UInt8(value))
      }
    } catch {
      Logger().error("Failed to set speaker volume: \(error)")
    }
  }

  private func setDoorbellChime(doorbellChime: DoorbellChime) async {
    guard let doorbellChimeTrait else {
      Logger().error("Doorbell chime trait not available")
      return
    }

    do {
      _ = try await doorbellChimeTrait.update {
        $0.setSelectedChime(doorbellChime.id)
      }
    } catch {
      Logger().error("Failed to set doorbell chime: \(error)")
    }
  }

  private func setStatusLightBrightness(
    to value: Google.CameraAvStreamManagementTrait.ThreeLevelAutoEnum
  ) async {
    guard let streamManagementTrait else {
      Logger().error("Stream management trait not available")
      return
    }

    do {
      _ = try await streamManagementTrait.update {
        $0.setStatusLightBrightness(value)
      }
    } catch {
      Logger().error("Failed to set status light brightness: \(error)")
    }
  }

  private func setExternalChime(to value: Google.ChimeTrait.ExternalChimeType) async {
    guard let doorbellChimeTrait else {
      Logger().error("Doorbell chime trait not available")
      return
    }

    do {
      _ = try await doorbellChimeTrait.update {
        $0.setExternalChime(value)
      }
    } catch {
      Logger().error("Failed to set external chime: \(error)")
    }
  }

  private func setWakeUpSensitivity(to value: UInt8) async {
    guard let pushAvStreamTransportTrait else {
      Logger().error("Push av stream transport trait not available")
      return
    }

    do {
      let connection = try await getRecordingConnection()
      guard let connection,
        let transportOptions = connection.transportOptions
      else {
        Logger().error("Transport options not available")
        return
      }

      guard transportOptions.triggerOptions.motionSensitivity != nil else {
        Logger().error("Motion sensitivity not available to be updated for this device")
        return
      }

      try await pushAvStreamTransportTrait.modifyPushTransport(
        connectionID: connection.connectionID,
        transportOptions: self.getTransportOptions(
          transportOptions: transportOptions,
          wakeUpSensitivity: value,
          maxEventLength: nil
        )
      )

    } catch {
      Logger().error("Failed to set wake up sensitivity: \(error)")
    }
  }

  private func setMaxEventLength(to value: UInt32) async {
    guard let pushAvStreamTransportTrait else {
      Logger().error("Push av stream transport trait not available")
      return
    }

    do {
      let connection = try await getRecordingConnection()
      guard let connection,
        let transportOptions = connection.transportOptions
      else {
        Logger().error("Transport options not available")
        return
      }

      guard transportOptions.triggerOptions.motionTimeControl != nil else {
        Logger().error("Motion time control not available to be updated for this device")
        return
      }

      try await pushAvStreamTransportTrait.modifyPushTransport(
        connectionID: connection.connectionID,
        transportOptions: self.getTransportOptions(
          transportOptions: transportOptions,
          wakeUpSensitivity: nil,
          maxEventLength: value
        )
      )

    } catch {
      Logger().error("Failed to set max event length: \(error)")
    }
  }

  private func setEnergyPreference(to value: Bool) async {
    guard let energyPreferenceTrait else {
      Logger().error("Energy preference trait not available")
      return
    }

    do {
      _ = try await energyPreferenceTrait.update {
        $0.setCurrentLowPowerModeSensitivity(UInt8(value))
      }
    } catch {
      Logger().error("Failed to set energy preference: \(error)")
    }
  }

  private func setBatteryUsage(to value: BatteryUsageSetting) async {
    guard let energyPreferenceTrait else {
      Logger().error("Energy preference trait not available")
      return
    }

    do {
      _ = try await energyPreferenceTrait.update {
        $0.setCurrentEnergyBalance(value.idx)
      }
    } catch {
      Logger().error("Failed to set battery usage: \(error)")
    }
  }

  private func setAnalyticsEnabled(to value: Bool) async {
    guard let extendedGeneralDiagnosticsTrait else {
      Logger().error("Extended general diagnostics trait not available")
      return
    }
    do {
      _ = try await extendedGeneralDiagnosticsTrait.update {
        $0.setAnalyticsEnabled(value)
      }
    } catch {
      Logger().error("Failed to set analytics enabled: \(error)")
    }
  }

  private func setLogUploadEnabled(to value: Bool) async {
    guard let extendedGeneralDiagnosticsTrait else {
      Logger().error("Extended general diagnostics trait not available")
      return
    }

    do {
      _ = try await extendedGeneralDiagnosticsTrait.update {
        $0.setLogUploadEnabled(value)
      }
    } catch {
      Logger().error("Failed to set log upload enabled: \(error)")
    }
  }

  private func setRecordingMode(to value: UInt8) async {
    guard let recordingModeTrait else {
      Logger().error("Recording mode trait not available")
      return
    }

    do {
      _ = try await recordingModeTrait.update {
        $0.setSelectedRecordingMode(value)
      }
    } catch {
      Logger().error("Failed to set recording mode: \(error)")
    }
  }

  private func getRecordingConnection() async throws
    -> Google.PushAvStreamTransportTrait.TransportConfigurationStruct?
  {
    guard let pushAvStreamTransportTrait else {
      Logger().error("Push av stream transport trait not available")
      return nil
    }

    let connections = try await pushAvStreamTransportTrait.findTransport().transportConfigurations

    for connection in connections {
      guard let transportOptions = connection.transportOptions,
        transportOptions.streamUsage == .recording
      else {
        continue
      }

      return connection
    }

    return nil
  }

  private func getTransportOptions(
    transportOptions: Google.PushAvStreamTransportTrait.TransportOptionsStruct,
    wakeUpSensitivity: UInt8?,
    maxEventLength: UInt32?
  ) async throws
    -> Google.PushAvStreamTransportTrait.TransportOptionsStruct
  {

    var newMotionTimeControl:
      Google.PushAvStreamTransportTrait.TransportMotionTriggerTimeControlStruct? = nil
    if let maxEventLength {
      guard let motionTimeControl = transportOptions.triggerOptions.motionTimeControl else {
        throw HomeError.failedPrecondition(
          "Cannot update max event length without motion time control.")
      }
      newMotionTimeControl =
        Google.PushAvStreamTransportTrait.TransportMotionTriggerTimeControlStruct(
          initialDuration: motionTimeControl.initialDuration,
          augmentationDuration: motionTimeControl.augmentationDuration,
          maxDuration: maxEventLength,
          blindDuration: motionTimeControl.blindDuration
        )
    }

    // This is required because the SDK requires a struct with updated fields to be passed in.
    return Google.PushAvStreamTransportTrait.TransportOptionsStruct(
      streamUsage: .recording,
      videoStreamID: nil,
      audioStreamID: nil,
      tlsEndpointID: transportOptions.tlsEndpointID,
      url: transportOptions.url,
      triggerOptions: Google.PushAvStreamTransportTrait.TransportTriggerOptionsStruct(
        triggerType: .motion,
        motionZones: nil,
        motionSensitivity: wakeUpSensitivity,
        motionTimeControl: newMotionTimeControl,
        maxPreRollLen: nil
      ),
      ingestMethod: .cmafIngest,
      containerOptions: Google.PushAvStreamTransportTrait.ContainerOptionsStruct(
        containerType: .cmaf,
        cmafContainerOptions: nil
      ),
      expiryTime: nil
    )
  }

}

// Settings displayed in the UI.
struct SettingsDisplayed: OptionSet {
  let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }

  public static let microphone = SettingsDisplayed(rawValue: 1 << 0)
  public static let camera = SettingsDisplayed(rawValue: 1 << 1)
  public static let doorbell = SettingsDisplayed(rawValue: 1 << 2)
  public static let battery = SettingsDisplayed(rawValue: 1 << 3)
  public static let information = SettingsDisplayed(rawValue: 1 << 4)
  public static let diagnostics = SettingsDisplayed(rawValue: 1 << 5)
  public static let recording = SettingsDisplayed(rawValue: 1 << 6)
}
