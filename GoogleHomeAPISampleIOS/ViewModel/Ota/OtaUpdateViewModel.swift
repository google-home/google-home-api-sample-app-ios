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

private enum OtaUiStateConstants {
  static let waitingBusyResponse = "Waiting after a busy response"
  static let waitingNextAction = "Waiting due to a next action"
  static let waitingUserConsent = "Waiting on user consent"
  static let rollingBackUpdateError = "Rolling back update"
  static let checkingForUpdates = "Checking for updates..."
  static let downloadingUpdate = "Downloading update..."
  static let installingUpdate = "Installing update & restarting device..."
  static let defaultFailedMessage = "Device restored to previous version."
  static let upToDate = "Up to date"
  static let possibleProblem = "There may be a problem"

  static func downloadingProgress(percent: Int) -> String {
    "Downloading (\(percent)%)"
  }

  static func updateFailed(error: String) -> String {
    "Update failed: \(error)"
  }
}

/// Represents the UI state of an OTA software update.
///
/// `currentVersionString` is the firmware version currently running on the device.
public enum OtaUiState: Equatable, Sendable {
  // Initial loading state before trait evaluation.
  case loading
  // Actively querying the OTA provider for available updates.
  case checking
  /// Downloading an update; `progressPercent` is nil when the device reports no progress.
  case downloading(progressPercent: Int?, currentVersionString: String?)
  /// Applying the downloaded update and restarting the device.
  case installing(currentVersionString: String?)
  /// Update is delayed; `reason` is a user-facing explanation.
  case delayed(reason: String, currentVersionString: String?)
  /// Update failed or rolled back; `error` is a user-facing message, if known.
  case failed(error: String?, currentVersionString: String?)
  /// No update is pending.
  case upToDate(currentVersionString: String?)

  /// Human-readable status string for display in OTA views and settings rows.
  public var displayStatusText: String {
    switch self {
    case .loading, .checking:
      return OtaUiStateConstants.checkingForUpdates
    case .downloading(let percent, _):
      if let percent {
        return OtaUiStateConstants.downloadingProgress(percent: percent)
      }
      return OtaUiStateConstants.downloadingUpdate
    case .installing:
      return OtaUiStateConstants.installingUpdate
    case .delayed:
      return OtaUiStateConstants.possibleProblem
    case .failed(let error, _):
      if let error, !error.isEmpty {
        return OtaUiStateConstants.updateFailed(error: error)
      }
      return OtaUiStateConstants.defaultFailedMessage
    case .upToDate:
      return OtaUiStateConstants.upToDate
    }
  }
}

/// Maps `OtaSoftwareUpdateRequestorTrait` state, progress, and version string into `OtaUiState`.
///
/// - Parameters:
///   - updateState: The requestor's `updateState`; nil maps to `.checking`.
///   - progress: The requestor's `updateStateProgress` percentage, if reported.
///   - versionString: The device's current firmware version, if known.
/// - Returns: The UI state to display for the given trait values.
public func mapUpdateStateToUiState(
  updateState: Matter.OtaSoftwareUpdateRequestorTrait.UpdateStateEnum?,
  progress: UInt8?,
  versionString: String?
) -> OtaUiState {
  guard let updateState else {
    return .checking
  }
  switch updateState {
  case .idle:
    return .upToDate(currentVersionString: versionString)
  case .querying:
    return .checking
  case .downloading:
    let progressPercent = progress.map { Int($0) }
    return .downloading(
      progressPercent: progressPercent,
      currentVersionString: versionString
    )
  case .applying:
    return .installing(
      currentVersionString: versionString
    )
  // In delayed states, the UI shows "There may be a problem" while the
  // device keeps running the update. Partners may customize this, e.g. prompt for consent on
  // `.delayedOnUserConsent` or show "downloaded, installs later" on `.delayedOnApply`.
  case .delayedOnQuery:
    return .delayed(
      reason: OtaUiStateConstants.waitingBusyResponse,
      currentVersionString: versionString
    )
  case .delayedOnApply:
    return .delayed(
      reason: OtaUiStateConstants.waitingNextAction,
      currentVersionString: versionString
    )
  case .delayedOnUserConsent:
    return .delayed(
      reason: OtaUiStateConstants.waitingUserConsent,
      currentVersionString: versionString
    )
  case .rollingBack:
    return .failed(
      error: OtaUiStateConstants.rollingBackUpdateError,
      currentVersionString: versionString
    )
  // UNKNOWN means the device has not determined its OTA state yet (e.g. right after commissioning).
  // It and unrecognized values show as checking. In the OOBE flow, if the state is still checking
  // when the watchdog (OtaUpdateViewModel `checkingTimeout`) fires, it becomes `.failed`.
  case .unknown, .unrecognized_:
    return .checking
  @unknown default:
    return .checking
  }
}

/// A ViewModel for observing and managing Matter OTA software updates on any device type.
///
/// Workflow and architecture:
/// 1. Queries `Matter.BasicInformationTrait` on Endpoint 0 (RootNode) for current firmware version.
/// 2. Observes `Matter.OtaSoftwareUpdateRequestorTrait` on `OtaRequestorDeviceType` for live
///    update states.
/// 3. Incorporates per-phase watchdog timers (300s checking, 1800s download, 900s install) to
///    handle late cloud component arrival and background installation transitions.
@MainActor
public final class OtaUpdateViewModel: ObservableObject {
  private enum Constants {
    static let defaultDeviceName = "Device"
    static let checkingTimeout: Duration = .seconds(300)
    static let downloadTimeout: Duration = .seconds(1800)
    static let installTimeout: Duration = .seconds(900)
    static let checkingTimedOutError = "Timed out checking for updates. The device may still be updating."
    static let downloadTimedOutError = "Download timed out"
    static let installTimedOutError = "Installation timed out"
    static let traitSubscriptionFailedError = "OTA trait subscription failed"
  }

  /// The `Home` instance owning the observed device.
  public let home: Home
  /// The identifier of the observed device.
  public let deviceID: String
  private let isOobeFlow: Bool

  /// Display name of the observed device.
  @Published public private(set) var deviceName: String = Constants.defaultDeviceName
  /// Current OTA software update UI state.
  @Published public private(set) var otaUiState: OtaUiState = .loading
  /// Current firmware version reported by `BasicInformationTrait`.
  @Published public private(set) var currentVersion: String?
  /// Whether `ConfigurationDoneTrait` was written successfully or is absent from the device.
  @Published public private(set) var isSetupComplete: Bool = false
  /// The latest resolved `HomeDevice` instance.
  @Published public private(set) var currentDevice: HomeDevice?

  private var configurationTask: Task<Void, Error>?
  private var checkingTimerTask: Task<Void, Never>?
  private var downloadTimerTask: Task<Void, Never>?
  private var installTimerTask: Task<Void, Never>?
  private var cancellables = Set<AnyCancellable>()

  /// Initializes the OTA ViewModel with an existing `HomeDevice` instance.
  ///
  /// - Parameters:
  ///   - home: The `Home` instance owning `device`.
  ///   - device: The device to observe.
  ///   - isOobeFlow: Whether this is the post-commissioning setup flow. If true, the checking
  ///     watchdog runs, and a Root Node without an OTA Requestor shows `.checking` instead of
  ///     `.upToDate`.
  public init(home: Home, device: HomeDevice, isOobeFlow: Bool = false) {
    self.home = home
    self.deviceID = device.id
    self.isOobeFlow = isOobeFlow
    self.currentDevice = device
    self.deviceName = device.name

    self.observeOtaFlow()
  }

  deinit {
    checkingTimerTask?.cancel()
    downloadTimerTask?.cancel()
    installTimerTask?.cancel()
  }

  /// Builds a reusable publisher emitting `(OtaUiState, currentVersion)` for a `HomeDevice`.
  ///
  /// The branch is chosen synchronously from the device's types; all streams are plain Combine
  /// and are torn down when the returned publisher is cancelled.
  ///
  /// - Parameters:
  ///   - device: The device whose OTA state and firmware version are observed.
  ///   - treatMissingRequestorAsUpToDate: Whether a Matter device that has a
  ///     `RootNodeDeviceType` but no `OtaRequestorDeviceType` reports `.upToDate` (true) or
  ///     `.checking` (false). Non-Matter devices, and Matter devices with neither type, always
  ///     report `.upToDate`.
  /// - Returns: A publisher of `(OtaUiState, currentVersion)` that never fails; an OTA trait
  ///   subscription error is reported as `.failed`.
  public static func otaStatePublisher(
    for device: HomeDevice,
    treatMissingRequestorAsUpToDate: Bool = false
  ) -> AnyPublisher<(OtaUiState, String?), Never> {
    let versionPublisher = device.types.subscribe(RootNodeDeviceType.self)
      .map { $0.traits[Matter.BasicInformationTrait.self]?.attributes.softwareVersionString }
      .replaceError(with: nil)
      .prepend(String?.none)
      .removeDuplicates()
      .receive(on: DispatchQueue.main)

    if !device.isMatterDevice ||
       (!device.types.contains(RootNodeDeviceType.self) &&
        !device.types.contains(OtaRequestorDeviceType.self)) {
      return versionPublisher
        .map { version -> (OtaUiState, String?) in
          (.upToDate(currentVersionString: version), version)
        }
        .eraseToAnyPublisher()
    }

    guard device.types.contains(OtaRequestorDeviceType.self) else {
      return versionPublisher
        .map { version -> (OtaUiState, String?) in
          let fallbackState: OtaUiState = treatMissingRequestorAsUpToDate
            ? .upToDate(currentVersionString: version)
            : .checking
          return (fallbackState, version)
        }
        .eraseToAnyPublisher()
    }

    let otaPublisher = device.types.subscribe(OtaRequestorDeviceType.self)
      .compactMap { $0.traits[Matter.OtaSoftwareUpdateRequestorTrait.self] }
      .receive(on: DispatchQueue.main)

    return Publishers.CombineLatest(otaPublisher, versionPublisher.setFailureType(to: HomeError.self))
      .removeDuplicates { prev, curr in
        prev.0.attributes == curr.0.attributes && prev.1 == curr.1
      }
      .map { otaTrait, version -> (OtaUiState, String?) in
        let state = mapUpdateStateToUiState(
          updateState: otaTrait.attributes.updateState,
          progress: otaTrait.attributes.updateStateProgress,
          versionString: version
        )
        return (state, version)
      }
      .replaceError(
        with: (
          .failed(error: Constants.traitSubscriptionFailedError, currentVersionString: nil),
          nil
        )
      )
      .eraseToAnyPublisher()
  }

  private func observeOtaFlow() {
    Logger().info("Observing OTA flow for device ID: \(self.deviceID) (isOobeFlow: \(self.isOobeFlow))")

    if self.isOobeFlow {
      self.startCheckingTimer(versionString: nil)
    }

    let useMultipart = self.currentDevice?.enableMultipartDevices ?? true
    let treatMissingAsUpToDate = !self.isOobeFlow

    home.device(id: deviceID, enableMultipartDevices: useMultipart)
      .removeDuplicates()
      .receive(on: DispatchQueue.main)
      .handleEvents(receiveOutput: { [weak self] device in
        guard let self else { return }
        self.currentDevice = device
        self.deviceName = device.name
      })
      .map { device -> AnyPublisher<(OtaUiState, String?), Never> in
        Self.otaStatePublisher(for: device, treatMissingRequestorAsUpToDate: treatMissingAsUpToDate)
      }
      .switchToLatest()
      .receive(on: DispatchQueue.main)
      .sink(
        receiveCompletion: { [weak self] completion in
          if case .failure(let error) = completion {
            Logger().error("OTA device subscription failed: \(error)")
            guard let self else { return }
            self.handleStateTransition(
              to: .failed(error: error.localizedDescription, currentVersionString: self.currentVersion),
              versionString: self.currentVersion
            )
          }
        },
        receiveValue: { [weak self] state, version in
          guard let self else { return }
          self.handleStateTransition(to: state, versionString: version)
        }
      )
      .store(in: &cancellables)
  }

  // MARK: - Watchdog Timers

  private func handleStateTransition(to state: OtaUiState, versionString: String?) {
    if let versionString = versionString {
      self.currentVersion = versionString
    }
    // A re-sent `.checking` (e.g. after `home.device` re-emits) is not progress. Keep `.failed`
    // so the camera Next button stays and the checking watchdog is not re-armed.
    if case .failed = self.otaUiState, state == .checking { return }
    self.otaUiState = state

    // `ConfigurationDoneTrait` is written only when the user leaves the OOBE (Done / dismiss),
    // not automatically on a terminal OTA state.
    switch state {
    case .downloading, .installing, .loading, .checking:
      break
    case .delayed(let reason, _):
      Logger().warning("Device '\(self.deviceName)' OTA delayed: \(reason)")
    case .upToDate(let ver):
      self.cancelAllWatchdogTimers()
      if let ver {
        self.currentVersion = ver
      }
    case .failed:
      self.cancelAllWatchdogTimers()
    }

    Logger().info(
      "Device '\(self.deviceName)' OTA state update: \(String(describing: state)), currentVersion: \(self.currentVersion ?? "nil")"
    )

    switch state {
    case .loading, .checking:
      self.downloadTimerTask?.cancel()
      self.downloadTimerTask = nil
      self.installTimerTask?.cancel()
      self.installTimerTask = nil
      if self.isOobeFlow {
        self.startCheckingTimer(versionString: versionString)
      }
    case .downloading:
      self.checkingTimerTask?.cancel()
      self.checkingTimerTask = nil
      self.installTimerTask?.cancel()
      self.installTimerTask = nil
      self.startDownloadTimer(versionString: versionString)
    case .installing:
      self.checkingTimerTask?.cancel()
      self.checkingTimerTask = nil
      self.downloadTimerTask?.cancel()
      self.downloadTimerTask = nil
      self.startInstallTimer(versionString: versionString)
    case .upToDate, .failed:
      break
    case .delayed:
      // Keep a checking watchdog as a stuck guard; the device may leave the delayed state
      // on its own.
      self.downloadTimerTask?.cancel()
      self.downloadTimerTask = nil
      self.installTimerTask?.cancel()
      self.installTimerTask = nil
      if self.isOobeFlow {
        self.startCheckingTimer(versionString: versionString)
      }
    }
  }

  private func startCheckingTimer(versionString: String?) {
    guard self.checkingTimerTask == nil else { return }
    Logger().debug("Starting 300s OTA checking watchdog timer")
    self.checkingTimerTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: Constants.checkingTimeout)
      guard let self = self, !Task.isCancelled else { return }
      switch self.otaUiState {
      case .loading, .checking, .delayed:
        // The OTA keeps running on the device after the app stops waiting, so never report
        // "Up to date" here.
        Logger().warning("300s checking timer expired in state \(String(describing: self.otaUiState)).")
        self.handleStateTransition(
          to: .failed(
            error: Constants.checkingTimedOutError,
            currentVersionString: self.currentVersion ?? versionString
          ),
          versionString: self.currentVersion ?? versionString
        )
      case .downloading, .installing, .failed, .upToDate:
        break
      }
      self.checkingTimerTask = nil
    }
  }

  private func startDownloadTimer(versionString: String?) {
    guard self.downloadTimerTask == nil else { return }
    Logger().debug("Starting 1800s OTA download watchdog timer")
    self.downloadTimerTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: Constants.downloadTimeout)
      guard let self = self, !Task.isCancelled else { return }
      if case .downloading = self.otaUiState {
        Logger().warning("1800s download timer expired. OTA download timed out.")
        self.handleStateTransition(
          to: .failed(
            error: Constants.downloadTimedOutError,
            currentVersionString: self.currentVersion ?? versionString
          ),
          versionString: self.currentVersion ?? versionString
        )
      }
      self.downloadTimerTask = nil
    }
  }

  private func startInstallTimer(versionString: String?) {
    guard self.installTimerTask == nil else { return }
    Logger().debug("Starting 900s OTA install watchdog timer")
    self.installTimerTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: Constants.installTimeout)
      guard let self = self, !Task.isCancelled else { return }
      if case .installing = self.otaUiState {
        Logger().warning("900s install timer expired. OTA install timed out.")
        self.handleStateTransition(
          to: .failed(
            error: Constants.installTimedOutError,
            currentVersionString: self.currentVersion ?? versionString
          ),
          versionString: self.currentVersion ?? versionString
        )
      }
      self.installTimerTask = nil
    }
  }

  private func cancelAllWatchdogTimers() {
    self.checkingTimerTask?.cancel()
    self.checkingTimerTask = nil
    self.downloadTimerTask?.cancel()
    self.downloadTimerTask = nil
    self.installTimerTask?.cancel()
    self.installTimerTask = nil
  }

  // MARK: - Configuration

  /// Marks post-commissioning app configuration complete via `Google.ConfigurationDoneTrait`.
  ///
  /// Concurrent callers await one shared write, which cancelling a caller does not abort.
  ///
  /// - Throws: The trait write error; `isSetupComplete` stays false so the next call retries.
  public func finishConfiguration() async throws {
    guard !self.isSetupComplete else { return }
    if let configurationTask = self.configurationTask {
      return try await configurationTask.value
    }

    guard let device = self.currentDevice else {
      self.isSetupComplete = true
      return
    }
    let task = Task<Void, Error> {
      if let configDoneTrait = await device.types.get(OtaRequestorDeviceType.self)?
        .traits[Google.ConfigurationDoneTrait.self] {
        _ = try await configDoneTrait.update {
          $0.setAppConfigurationComplete(true)
        }
      } else if let configDoneTrait = await device.types.get(RootNodeDeviceType.self)?
        .traits[Google.ConfigurationDoneTrait.self] {
        _ = try await configDoneTrait.update {
          $0.setAppConfigurationComplete(true)
        }
      } else {
        Logger().debug("ConfigurationDoneTrait not available on device, skipping.")
        return
      }
      Logger().info("ConfigurationDoneTrait setAppConfigurationComplete successfully.")
    }
    self.configurationTask = task
    defer { self.configurationTask = nil }
    do {
      try await task.value
    } catch {
      Logger().warning("Failed to update ConfigurationDoneTrait: \(error)")
      throw error
    }
    self.isSetupComplete = true
  }
}
