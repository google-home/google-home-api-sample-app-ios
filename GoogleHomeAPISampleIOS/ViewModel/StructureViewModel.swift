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
import OSLog

final class StructureViewModel: ObservableObject {

  private let home: Home
  let structureID: String
  private var commissioningManager = CommissioningManager()

  @Published var entries = [StructureEntry]()
  private var hub: Hub? = nil

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

    /// query rooms and devices and map them to current structure
    self.home.rooms().batched()
      .combineLatest(self.home.devices().batched())
      .receive(on: DispatchQueue.main)
      .catch { error in
        Logger().error("Failed to load rooms and devices: \(error)")
        return Just((Set<Room>(), Set<HomeDevice>()))
      }
      .map { [weak self] rooms, devices in
        self?.hasLoaded = true
        /// check structure ID to filter rooms under the strucutre
        let entriesByRoom = rooms.reduce(into: [String: StructureEntry]()) { result, room in
          if room.structureID == structureID {
            result[room.id] = StructureEntry(
              room: room,
              roomID: room.id,
              roomName: room.name.isEmpty ? "<unassigned>" : room.name
            )
          }
        }
        /// Read devices in this structure then assign to corresponding rooms.
        for device in devices where device.structureID == structureID {
          /// Skip processing device with an invalid room.
          guard let roomID = device.roomID, let entry = entriesByRoom[roomID] else { continue }
          do {
            // Create DeviceControl.
            let control = try DeviceControlFactory.make(device: device)
            entry.appendDeviceControl(control)
          } catch {
            Logger().error("Failed to create device control: \(error)")
          }
        }
        /// return to .map
        return entriesByRoom.values
          .sorted { $0.roomName < $1.roomName }
      }
      /// receive from .map and .assign() to publisher entries
      .assign(to: &self.$entries)
  }

  // MARK: - Commissioning

  /// Adds a Matter device through the `CommissioningManager`.
  /// - Parameters:
  ///   - structure: The structure to add the device to.
  ///   - add3PFabricFirst: If `true` adds the device to a 3P fabric.
  func addMatterDevice(to structure: Structure, add3PFabricFirst: Bool) {
    self.commissioningManager.addMatterDevice(to: structure, add3PFabricFirst: add3PFabricFirst)
  }

  // MARK: - `StructureViewModel.StructureEntry`

  final class StructureEntry: Identifiable {
    let room: Room
    let roomID: String
    let roomName: String
    private(set) var deviceControls = [DeviceControl]()

    // MARK: Initialization

    init(room: Room, roomID: String, roomName: String) {
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
  @MainActor
  public func discoverAvailableHubs() async {
    await MainActor.run {
      self.isDiscoveringHubs = true
    }
    do {
      let hubs = try await self.home.discoverAvailableHubs()
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
}
