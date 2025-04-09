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

@MainActor
public class CandidatesViewModel: ObservableObject {

  private let home: Home
  public let structure: Structure

  @Published public var roomEntries = [RoomEntry]()
  @Published public var hasLoaded = false

  /// Array stores selected starter info
  @Published public var selectedStarters = [SelectedEntry]()
  /// Array stores selected action info
  @Published public var selectedActions = [SelectedEntry]()
  /// Current selected device, use to display the StarterCandidatesView
  @Published public var selectedStarterDevice: DeviceEntry?
  /// Current selected device, use to display the ActionCandidatesView
  @Published public var selectedActionDevice: DeviceEntry?

  private var candidatesCancellable: AnyCancellable? = nil

  public init(home: Home, structure: Structure) {
    self.home = home
    self.structure = structure

    /// Fetch candidates from the structure through Discovery API
    self.candidatesCancellable = Publishers.CombineLatest(
      self.home.rooms().batched(),
      structure.candidates(includeDescendants: true).batched()
    )
    .receive(on: DispatchQueue.main)
    .catch { _ in
      // Deal with the exception if displaying any alert needed
      Empty()
    }.sink { rooms, candidates in
      let deviceNodeTable: [HomeDevice: [NodeEntry]] =
        candidates
        .reduce(into: [HomeDevice: [NodeEntry]]()) { table, candidate in
          // Filter out nodes that are not devices or devices that do not have a room ID
          if let device = candidate.node.homeObject as? HomeDevice, device.roomID != nil {
            table[device, default: []].append(NodeEntry(node: candidate.node))
          }
         }
      // Create DeviceEntries and group them with roomID
      let roomIDDeviceEntriesTable =
        deviceNodeTable
        .reduce(into: [String: [DeviceEntry]]()) { table, keyValue in
          let device = keyValue.key
          let nodeEntries = keyValue.value
          guard let roomID = device.roomID else { return }
          table[roomID, default: []].append(DeviceEntry(device: device, nodes: nodeEntries))
        }
      // Map to RoomEntries
      self.roomEntries = rooms.compactMap { room in
        roomIDDeviceEntriesTable[room.id].map { RoomEntry(room: room, devices: $0) }
      }
      self.hasLoaded = true
    }
  }

  public func addSelectedStarters(device: HomeDevice, deviceType: any DeviceType.Type, trait: any GoogleHomeSDK.Trait.Type, valueOnOff: Bool, operation: Operations, levelValue: UInt8) {
    let _selectedStarter = SelectedEntry(device: device, deviceType: deviceType, traitType: trait, valueOnOff: valueOnOff, operation: operation, levelValue: levelValue)
    self.selectedStarters.append(_selectedStarter)
  }

  public func addSelectedActions(device: HomeDevice, deviceType: any DeviceType.Type, trait: any GoogleHomeSDK.Trait.Type, valueOnOff: Bool, operation: Operations, levelValue: UInt8) {
    let _selectedAction = SelectedEntry(device: device, deviceType: deviceType, traitType: trait, valueOnOff: valueOnOff, operation: operation, levelValue: levelValue)
    self.selectedActions.append(_selectedAction)
  }

  public func clearSelected() {
    selectedStarters.removeAll()
    selectedActions.removeAll()
    selectedStarterDevice = nil
    selectedActionDevice = nil
  }

  /// Entry of a room, contains several devices
  public struct RoomEntry: Identifiable, Comparable {
    public static func < (lhs: CandidatesViewModel.RoomEntry, rhs: CandidatesViewModel.RoomEntry)
      -> Bool
    {
      return lhs.room.name < rhs.room.name
    }

    public var id: String { self.room.id }
    public let room: Room
    public let devices: [DeviceEntry]
  }

  /// Entry of a device, contains several nodes
  public struct DeviceEntry: Identifiable, Hashable {
    public var id: String { self.device.id }

    public let device: HomeDevice
    public let nodes: [NodeEntry]
    /// Transfer to specific DeviceType for storage
    public var deviceType: any DeviceType.Type {
      if device.types.contains(ColorTemperatureLightDeviceType.self) {
        return ColorTemperatureLightDeviceType.self
      } else if device.types.contains(DimmableLightDeviceType.self) {
        return DimmableLightDeviceType.self
      } else if device.types.contains(OnOffLightDeviceType.self) {
        return OnOffLightDeviceType.self
      } else if device.types.contains(OnOffLightSwitchDeviceType.self) {
        return OnOffLightSwitchDeviceType.self
      } else if device.types.contains(OnOffPluginUnitDeviceType.self) {
        return OnOffPluginUnitDeviceType.self
      } else if device.types.contains(ThermostatDeviceType.self) {
        return ThermostatDeviceType.self
      } else if device.types.contains(DoorLockDeviceType.self) {
        return DoorLockDeviceType.self
      } else if device.types.contains(TemperatureSensorDeviceType.self) {
        return TemperatureSensorDeviceType.self
      } else if device.types.contains(WindowCoveringDeviceType.self) {
        return WindowCoveringDeviceType.self
      } else if device.types.contains(GoogleDisplayDeviceType.self) {
        return GoogleDisplayDeviceType.self
      } else {
        return UnknownDeviceType.self
      }
    }

    public var iconName: String {
      if device.types.contains(OnOffLightDeviceType.self) {
        return "lightbulb_symbol"
      } else if device.types.contains(OnOffLightSwitchDeviceType.self) {
        return "lightbulb_symbol"
      } else if device.types.contains(OnOffPluginUnitDeviceType.self) {
        return "outlet_symbol"
      } else if device.types.contains(ThermostatDeviceType.self) {
        return "thermostat_symbol"
      } else if device.types.contains(DoorLockDeviceType.self) {
        return "lock_lock_symbol"
      } else if device.types.contains(TemperatureSensorDeviceType.self) {
        return "sensors_symbol"
      } else if device.types.contains(WindowCoveringDeviceType.self) {
        return "blinds_symbol"
      } else if device.types.contains(GoogleDisplayDeviceType.self) {
        return "tv_symbol"
      } else if device.types.contains(DimmableLightDeviceType.self) {
        return "lightbulb_symbol"
      } else {
        return "devices_other_symbol"
      }
    }

    public var typeName: String {
      if device.types.contains(OnOffLightDeviceType.self) {
        return "Light"
      } else if device.types.contains(OnOffLightSwitchDeviceType.self) {
        return "Light Switch"
      } else if device.types.contains(OnOffPluginUnitDeviceType.self) {
        return "Outlet"
      } else if device.types.contains(GoogleCameraDeviceType.self) {
        return "Camera"
      } else if device.types.contains(GoogleDoorbellDeviceType.self) {
        return "Doorbell"
      } else if device.types.contains(ThermostatDeviceType.self) {
        return "Thermostat"
      } else if device.types.contains(DoorLockDeviceType.self) {
        return "Door Lock"
      } else if device.types.contains(SmokeCOAlarmDeviceType.self) {
        return "Smoke CO Alarm"
      } else if device.types.contains(TemperatureSensorDeviceType.self) {
        return "Temperature Sensor"
      } else if device.types.contains(WindowCoveringDeviceType.self) {
        return "Window Covering"
      } else if device.types.contains(SpeakerDeviceType.self) {
        return "Speaker"
      } else if device.types.contains(GoogleDisplayDeviceType.self) {
        return "Display"
      } else if device.types.contains(AirQualitySensorDeviceType.self) {
        return "Air Quality Sensor"
      } else if device.types.contains(DimmableLightDeviceType.self) {
        return "Light"
      } else {
        return "Device"
      }
    }
  }

  /// Entry of a node, could be mapped to a trait.
  public struct NodeEntry: Identifiable, Equatable, Hashable {
    public static func == (lhs: CandidatesViewModel.NodeEntry, rhs: CandidatesViewModel.NodeEntry)
      -> Bool
    {
      return lhs.id == rhs.id
    }

    public var id: String {
      return String(self.node.hashValue)
    }

    public func hash(into hasher: inout Hasher) {
      node.hash(into: &hasher)
    }

    public let node: any NodeCandidate

    public var traitType: any GoogleHomeSDK.Trait.Type {
      if self.node.trait == Matter.OnOffTrait.self {
        return Matter.OnOffTrait.self
      } else if self.node.trait == Matter.ColorControlTrait.self {
        return Matter.ColorControlTrait.self
      } else if self.node.trait == Matter.LevelControlTrait.self {
        return Matter.LevelControlTrait.self
      } else if self.node.trait == Matter.OccupancySensingTrait.self {
        return Matter.OccupancySensingTrait.self
      } else if self.node.trait == Google.BrightnessTrait.self {
        return Google.BrightnessTrait.self
      } else if self.node.trait == Google.SimplifiedOnOffTrait.self {
        return Google.SimplifiedOnOffTrait.self
      } else {
        return UnknownTrait.self
      }
    }

    public var iconName: String {
      if self.node.trait == Matter.OnOffTrait.self {
        return "power_settings_new_symbol"
      } else if self.node.trait == Matter.ColorControlTrait.self {
        return "palette_symbol"
      } else if self.node.trait == Matter.LevelControlTrait.self {
        return "brightness_symbol"
      } else if self.node.trait == Matter.OccupancySensingTrait.self {
        return "google_symbols/home_symbol"
      } else if self.node.trait == Google.BrightnessTrait.self {
        return "brightness_symbol"
      } else if self.node.trait == Google.SimplifiedOnOffTrait.self {
        return "power_settings_new_symbol"
      } else {
        return ""
      }
    }

    public var description: String {
      if self.node.trait == Matter.OnOffTrait.self {
        return "Turns on or off"
      } else if self.node.trait == Matter.ColorControlTrait.self {
        return "Changes color"
      } else if self.node.trait == Matter.LevelControlTrait.self {
        return "Changes brightness"
      } else if self.node.trait == Matter.OccupancySensingTrait.self {
        return "Reports occupancy"
      } else if self.node.trait == Google.BrightnessTrait.self {
        return "Changes brightness"
      } else if self.node.trait == Google.SimplifiedOnOffTrait.self {
        return "Turns on or off"
      } else {
        return node.trait.identifier
      }
    }

    /// Whether it's a supported trait in current generic editor
    public var isSupported: Bool {
      if self.node.trait == Matter.OnOffTrait.self {
        return true
      } else if self.node.trait == Matter.LevelControlTrait.self {
        return true
      }  else {
        return false
      }
    }

    public var constraintEntry: ConstraintEntry {
      return ConstraintEntry(node: self.node)
    }
  }

  /// Map the constraint for each trait. It can support filtering unqualified value selection.
  public enum ConstraintEntry {
    case none
    case toggle(values: [String])
    case levelInt(values: [Int64])
    case levelUInt(values: [UInt64])
    case levelDouble(values: [Double])

    init(node: any NodeCandidate) {
      guard let constraint = node.fieldDetails.values.first?.constraint else {
        self = .none
        return
      }

      switch constraint {
      case .enumConstraint(let allowedSet):
        // A constraint on an Enum field. Supports On/Off as a sample.
        self = .toggle(
          values: allowedSet.compactMap {
            if let onOffEnum = $0.cast(Google.SimplifiedOnOffTrait.OnOffEnum.self) {
              return String(describing: onOffEnum).prefix(1).uppercased()
                + String(describing: onOffEnum).dropFirst()
            }
            return nil
          })
      case .booleanConstraint:
        // A constraint on a Boolean field. Supports On/Off as a sample.
        if node.fieldDetails.values.first?.field.id == Matter.OnOffTrait.Attribute.onOff.id {
          self = .toggle(values: ["On", "Off"])
        } else {
          self = .none
        }
      case .intRangeConstraint(let lowerBound, let upperBound, _, _):
        // A constraint on an Int field, which can get lowerBound/upperBound from
        self = .levelInt(values: [lowerBound, upperBound])
      case .uintRangeConstraint(let lowerBound, let upperBound, _, _):
        // A constraint on an UInt field, which can get lowerBound/upperBound from
        self = .levelUInt(values: [lowerBound, upperBound])
      case .doubleRangeConstraint(let lowerBound, let upperBound, _, _):
        // A constraint on a Double field, which can get lowerBound/upperBound from
        self = .levelDouble(values: [lowerBound, upperBound])
      default:
        self = .none
      }
    }
  }
}

/// Store the selected component info
public struct SelectedEntry: Identifiable {
  public var id: String { self.device.id }

  public let device: HomeDevice
  public let deviceType: any DeviceType.Type
  public let traitType: any GoogleHomeSDK.Trait.Type

  public let valueOnOff: Bool
  public let operation: Operations
  public let levelValue: UInt8
}

public enum Operations {
  case equalsTo
  case greaterThan
  case lessThan
}

