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

  /// Indicates whether the initial load has completed
  @Published var hasLoaded = false
  @Published var showRoomNameInput = false
  @Published var roomNameInput = ""
  @Published var roomIDToBeDeleted: String?

  var isConfirmingRoomDeletion: Bool {
    get { return roomIDToBeDeleted != nil }
    set { if !newValue { roomIDToBeDeleted = nil } }
  }

  // MARK: - Initialization

  init(home: Home, structureID: String) {
    self.home = home
    self.structureID = structureID

    getRoomsAndDevices()
  }

  /// TODO: get rooms and devices
  /// Remove comments to get the rooms and devices from home entry
  private func getRoomsAndDevices(){
//    self.home.rooms().batched()
//      .combineLatest(self.home.devices().batched())
//      .receive(on: DispatchQueue.main)
//      .catch { error in
//        Logger().error("Failed to load rooms and devices: \(error)")
//        return Just((Set<Room>(), Set<HomeDevice>()))
//      }
//      .map { [weak self] rooms, devices in
//        guard let self = self else { return [] }
//        self.hasLoaded = true
//        return self.process(rooms: rooms, devices: devices)
//      }
//      /// receive from .map and .assign() to publisher entries
//      .assign(to: &self.$entries)
    AlertHelper.showAlert(text: "TODO: get rooms and devices")
  }

  /// Processes the fetched rooms and devices, filtering and organizing them for the view.
  /// - Parameters:
  ///   - rooms: A set of all rooms fetched.
  ///   - devices: A set of all devices fetched.
  /// - Returns: An array of `StructureEntry` objects, sorted by room name.
  private func process(rooms: Set<Room>, devices: Set<HomeDevice>) -> [StructureEntry] {
    let entriesByRoom = rooms.reduce(into: [String: StructureEntry]()) { result, room in
      if room.structureID == self.structureID {
        result[room.id] = StructureEntry(
          roomID: room.id,
          roomName: room.name.isEmpty ? "<Unassigned>" : room.name
        )
      }
    }

    /// Process devices and assign them to their respective rooms
    for device in devices where device.structureID == self.structureID {
      /// Ensure the device has a valid room ID and the room entry exists in our dictionary
      guard let roomID = device.roomID, let entry = entriesByRoom[roomID] else {
        /// Log a warning if a device can't be placed in a room
        Logger().warning("Device \(device.id) has invalid or missing roomID (\(device.roomID ?? "nil")) or room not found in structure \(self.structureID).")
        continue // Skip devices not in a known room of this structure
      }
      do {
        /// Create a specific DeviceControl (e.g., LightControl, FanControl) based on the device type
        let control = try DeviceControlFactory.make(device: device)
        /// Add the control to the corresponding room's entry
        entry.appendDeviceControl(control)
      } catch {
        /// Log errors during DeviceControl creation
        Logger().error("Failed to create device control for \(device.id): \(error)")
      }
    }

    /// Sort the room entries alphabetically by name for consistent display order
    return entriesByRoom.values
      .sorted { $0.roomName < $1.roomName }
  }

  /// TODO: add room
  /// Add a new room in a given structure.
  func addRoom(name: String, structure: Structure) {
//    Task {
//      do {
//        // The view will be updated with the values from the devices publisher.
//        _ = try await structure.createRoom(name: name)
//      } catch {
//        Logger().error("Failed to create room: \(error)")
//      }
//    }
    AlertHelper.showAlert(text: "TODO: add room")
  }

  /// TODO: delete room
  /// Delete an empty room in a given structure.
  func removeRoom(id: String, structure: Structure) {
//    Task {
//      do {
//        // The view will be updated with the values from the devices publisher.
//        _ = try await structure.deleteRoom(id: id)
//      } catch {
//        Logger().error("Failed to remove room: \(error)")
//      }
//    }
    AlertHelper.showAlert(text: "TODO: delete room")
  }

  /// TODO: move device
  /// Move a device into a different room.
  func moveDevice(device deviceID: String, to roomID: String, structure: Structure) {
//    Task {
//      do {
//        _ = try await structure.move(device: deviceID, to: roomID)
//      } catch {
//        Logger().error("Failed to move to room: \(error)")
//      }
//    }
    AlertHelper.showAlert(text: "TODO: move device")
  }

  // MARK: - Commissioning

  /// If `true`  the commissioning manager is actively commissioning a device.
  var isCommissioningInProgress: Bool {
    self.commissioningManager.isCommissioning
  }


  /// Adds a Matter device through the `CommissioningManager`.
  /// - Parameters:
  ///   - structure: The structure to add the device to.
  ///   - add3PFabricFirst: If `true` adds the device to a 3P fabric.
  func addMatterDevice(to structure: Structure, add3PFabricFirst: Bool) {
    self.commissioningManager.addMatterDevice(to: structure, add3PFabricFirst: add3PFabricFirst)
  }

  // MARK: - `StructureViewModel.StructureEntry`

  final class StructureEntry: Identifiable {
    let roomID: String
    let roomName: String
    private(set) var deviceControls = [DeviceControl]()

    // MARK: Initialization

    init(roomID: String, roomName: String) {
      self.roomID = roomID
      self.roomName = roomName
    }

    var id: String { self.roomID }

    func appendDeviceControl(_ deviceControl: DeviceControl) {
      self.deviceControls.append(deviceControl)
      self.deviceControls.sort(by: { $0.id < $1.id })
    }
  }
}
