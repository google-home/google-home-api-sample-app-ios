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
import Foundation
import GoogleHomeSDK
import GoogleHomeTypes
import OSLog

/// A viewModel for managing the structure, rooms, and devices within them.
@MainActor
final class StructureViewModel: ObservableObject {

  private enum Constants {
    static let unassignedRoomName = "In your home"
    static let unassignedRoomID = "unassignedDevices"
    static let emptyRoomName = "<unassigned>"
  }

  public let home: Home
  public let structureID: String
  private var commissioningManager = CommissioningManager()

  @Published var entries = [StructureEntry]()
  private var hub: Hub? = nil
  @Published var faceLibraryConsentStatus: StructureScopedPermissionsController.ConsentStatus = .unspecified
  @Published var isFetchingConsentStatus = true
  @Published var presenceSensingConsentStatus: StructureScopedPermissionsController.ConsentStatus = .unspecified
  @Published var isFetchingPresenceConsentStatus = true
  /// Indicates whether the initial load has completed
  @Published var hasLoaded = false
  @Published var showRoomNameInput = false
  @Published var roomNameInput = ""
  @Published var roomIDToBeDeleted: String?
  @Published var showNoHubFoundDialog: Bool = false
  @Published var isDiscoveringHubs = false

  var isConfirmingRoomDeletion: Bool {
    get { return roomIDToBeDeleted != nil }
    set { if !newValue { roomIDToBeDeleted = nil } }
  }

  // MARK: - Initialization

  init(home: Home, structureID: String) {
    self.home = home
    self.structureID = structureID
    Task {
      await self.refreshFaceLibraryConsentStatus()
      await self.refreshPresenceSensingConsentStatus()
    }
    /// query rooms and devices and map them to current structure
    self.home.rooms().batched()
      .combineLatest(self.home.devices().batched())
      .receive(on: DispatchQueue.main)
      .catch { error in
        Logger().error("Failed to load rooms and devices: \(error)")
        return Just((Set<Room>(), Set<HomeDevice>()))
      }
      .map { [weak self] rooms, devices in
        guard let self = self else { return [] }
        self.hasLoaded = true
        let entriesByRoom = rooms.reduce(into: [String: StructureEntry]()) { result, room in
          if room.structureID == self.structureID {
            result[room.id] = StructureEntry(
              room: room,
              roomID: room.id,
              roomName: room.name.isEmpty ? Constants.emptyRoomName : room.name
            )
          }
        }
        // Create a specific entry for "In your home" (Unassigned)
        let unassignedEntry = StructureEntry(
          room: nil,
          roomID: Constants.unassignedRoomID,
          roomName: Constants.unassignedRoomName
        )
        var hasUnassignedDevices = false
        for device in devices where device.structureID == self.structureID {
          do {
            let control = try DeviceControlFactory.make(device: device)

            // Check if device belongs to a known room
            if let roomID = device.roomID, let entry = entriesByRoom[roomID] {
              entry.appendDeviceControl(control)
            } else {
              // If no room ID, or room not found, add to "In your home"
              unassignedEntry.appendDeviceControl(control)
              hasUnassignedDevices = true
            }
          } catch {
            Logger().error("Failed to create device control: \(error)")
          }
        }
        return Array(entriesByRoom.values)
          .sorted { $0.roomName < $1.roomName }
        + (hasUnassignedDevices ? [unassignedEntry] : [])
      }
      /// receive from .map and .assign() to publisher entries
      .assign(to: &self.$entries)
  }

  // MARK: - Commissioning

  /// Commissions Matter devices through the `CommissioningManager` and returns the corresponding
  /// `HomeDevice` objects from `Home`.
  /// - Parameters:
  ///   - structure: The structure to add the device to.
  ///   - add3PFabricFirst: If `true` adds the device to a 3P fabric.
  ///   - setupPayload: The custom payload to be used to bypass the QR code scanning process.
  /// - Returns: The device objects of the commissioned devices.
  /// - Throws: An error if the commissioning flow fails.
  func addMatterDevice(
    to structure: Structure, add3PFabricFirst: Bool, setupPayload: String? = nil
  ) async throws -> Set<HomeDevice> {
    let deviceIDs = try await self.commissioningManager.addMatterDevice(
      to: structure, add3PFabricFirst: add3PFabricFirst, setupPayload: setupPayload
    )
    return try await self.home.devices().list().filter { deviceIDs.contains($0.id) }
  }

  // MARK: - `StructureViewModel.StructureEntry`

  final class StructureEntry: Identifiable {
    let room: Room?
    let roomID: String
    let roomName: String
    private(set) var deviceControls = [DeviceControl]()

    // MARK: Initialization
    init(room: Room?, roomID: String, roomName: String) {
      self.room = room
      self.roomID = roomID
      self.roomName = roomName
    }

    var id: String { self.roomID }

    func appendDeviceControl(_ deviceControl: DeviceControl) {
      self.deviceControls.append(deviceControl)
      self.deviceControls.sort(by: { $0.id < $1.id })
    }
  }

  // MARK: Hub Activation

  /// Discovey the Google Home hub under the same local network.
  public func discoverAvailableHubs() async {
    self.isDiscoveringHubs = true
    do {
      let hubs = await self.home.discoverAvailableHubs()
      Logger().info("hubs found: \(hubs)")
      if let hub = hubs.first {
        try await self.setupHub(hub)
      } else {
        self.showNoHubFoundDialog = true
      }
    } catch {
      Logger().error("Failed to discover available hubs: \(error)")
    }
    self.isDiscoveringHubs = false
  }

  /// Start the hub activation flow to add the hub under user's structure and room.
  /// - Parameters:
  ///    - hub: The `Hub` object representing the Google Home hub to be activated.
  private func setupHub(_ hub: Hub) async throws {
    try await self.home.startHubActivation(
      hub,
      structureID: self.structureID
    )
  }

  // MARK: - Generic Consent Helpers

  /// Initiates the consent flow or modification screen for a feature.
  ///
  /// - Parameter feature: The permission feature to request or manage.
  /// - Returns: The updated feature consent status.
  ///
  /// - Note: Sensitive features require explicit user consent via `requestConsent(for:)`.
  private func performConsentFlow(for feature: StructureScopedPermissionsController.Feature) async -> StructureScopedPermissionsController.ConsentStatus {
    do {
      let structures = try await home.structures().list()
      if let structure = structures.first(where: { $0.id == self.structureID }) {
        // Launch the OAuth consent modal for the feature.
        if let response = await structure.permissions.requestConsent(for: [feature]) {
          switch response {
          case .success(let completed, let consentedFeatures):
            // Verify that the user completed the web flow and granted consent.
            if let completed = completed, completed, let status = consentedFeatures?[feature] {
              return status
            }
          case .alreadyConsented:
            return .consented
          @unknown default:
            break
          }
        }
        // If the modal was cancelled or missing status, fall back to backend query.
        if let status = await refreshConsentStatus(for: feature) {
          return status
        }
      }
    } catch {
      Logger().error("Failed to perform consent flow for \(String(describing: feature)): \(error)")
    }
    return .unspecified
  }

  /// Fetches the latest feature consent status from the permissions controller.
  ///
  /// - Parameter feature: The permission feature to query.
  /// - Returns: The current `ConsentStatus`, or `nil` on network failure.
  ///
  /// - Note: Returning `nil` on error prevents overwriting valid consent states with `.unspecified`.
  private func refreshConsentStatus(for feature: StructureScopedPermissionsController.Feature) async -> StructureScopedPermissionsController.ConsentStatus? {
    do {
      let structures = try await home.structures().list()
      if let structure = structures.first(where: { $0.id == self.structureID }) {
        // Query feature consent state from ApplicationInfo.
        let consentStateMap = await structure.permissions.featureConsentState(features: [feature])
        return consentStateMap[feature]
      }
    } catch {
      Logger().error("Failed to refresh consent status for \(String(describing: feature)): \(error)")
    }
    return nil
  }

  // MARK: - Familiar Faces Consent

  /// Initiates the familiar faces consent flow.
  ///
  /// - Returns: `true` if the user consented to the face library feature.
  public func requestFaceLibraryConsent() async -> Bool {
    if self.faceLibraryConsentStatus == .consented {
      return true
    }
    self.faceLibraryConsentStatus = await performConsentFlow(for: .faceLibrary)
    return self.faceLibraryConsentStatus == .consented
  }

  /// Refreshes the familiar faces consent status for this structure.
  public func refreshFaceLibraryConsentStatus() async {
    isFetchingConsentStatus = true
    defer { isFetchingConsentStatus = false }
    if let status = await refreshConsentStatus(for: .faceLibrary) {
      self.faceLibraryConsentStatus = status
    }
  }

  /// Presents the familiar faces consent modification screen.
  ///
  /// - Returns: `true` if the user consented to the face library feature.
  public func presentFaceLibraryConsentFlow() async -> Bool {
    self.faceLibraryConsentStatus = await performConsentFlow(for: .faceLibrary)
    return self.faceLibraryConsentStatus == .consented
  }

  // MARK: - Presence Sensing Consent

  /// Initiates the presence sensing consent flow.
  ///
  /// - Returns: `true` if the user consented to the presence sensing feature.
  public func requestPresenceSensingConsent() async -> Bool {
    if self.presenceSensingConsentStatus == .consented {
      return true
    }
    self.presenceSensingConsentStatus = await performConsentFlow(for: .presenceSensing)
    return self.presenceSensingConsentStatus == .consented
  }

  /// Refreshes the presence sensing consent status for this structure.
  public func refreshPresenceSensingConsentStatus() async {
    isFetchingPresenceConsentStatus = true
    defer { isFetchingPresenceConsentStatus = false }
    if let status = await refreshConsentStatus(for: .presenceSensing) {
      self.presenceSensingConsentStatus = status
    }
  }

  /// Presents the presence sensing consent modification screen.
  ///
  /// - Returns: `true` if the user consented to the presence sensing feature.
  public func presentPresenceSensingConsentFlow() async -> Bool {
    self.presenceSensingConsentStatus = await performConsentFlow(for: .presenceSensing)
    return self.presenceSensingConsentStatus == .consented
  }
}
