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

import GoogleHomeSDK
import GoogleHomeTypes

// Factory that creates the corresponding device control for a `HomeDevice`.
struct DeviceControlFactory {
  /// List of supported device types. Order matters because some types can overlap, like
  /// `OnOffLightDeviceType` and `DimmableLightDeviceType`.
  private static let supportedDeviceTypes: [any DeviceType.Type] = [
    ExtendedColorLightDeviceType.self,
    ColorTemperatureLightDeviceType.self,
    DimmableLightDeviceType.self,
    OnOffLightDeviceType.self,
    DoorLockDeviceType.self,
    FanDeviceType.self,
    WindowCoveringDeviceType.self,
    TemperatureSensorDeviceType.self,
    ThermostatDeviceType.self,
    OnOffPluginUnitDeviceType.self,
    OccupancySensorDeviceType.self,
    GoogleTVDeviceType.self,
    GoogleCameraDeviceType.self,
    GoogleDoorbellDeviceType.self,
  ]

  private static let deviceControlBuilders: [String: (HomeDevice) throws -> DeviceControl] = [
    ExtendedColorLightDeviceType.identifier: LightControl<ExtendedColorLightDeviceType>.init,
    ColorTemperatureLightDeviceType.identifier: LightControl<ColorTemperatureLightDeviceType>.init,
    DimmableLightDeviceType.identifier: LightControl<DimmableLightDeviceType>.init,
    OnOffLightDeviceType.identifier: LightControl<OnOffLightDeviceType>.init,
    DoorLockDeviceType.identifier: DoorLockControl.init,
    FanDeviceType.identifier: FanControl.init,
    WindowCoveringDeviceType.identifier: WindowCoveringControl.init,
    TemperatureSensorDeviceType.identifier: TemperatureSensorControl.init,
    ThermostatDeviceType.identifier: ThermostatControl.init,
    OnOffPluginUnitDeviceType.identifier: OnOffPlugInUnitControl.init,
    OccupancySensorDeviceType.identifier: OccupancySensorControl.init,
    GoogleTVDeviceType.identifier: TVControl.init,
    GoogleCameraDeviceType.identifier: CameraControl.init,
    GoogleDoorbellDeviceType.identifier: DoorbellControl.init,
  ]

  /// Factory method that builds a `DeviceControl` based on the supported `DeviceType` of a
  /// `HomeDevice`. If the device doesn't support any known `DeviceType` return a
  /// `GenericDeviceControl`.
  static func make(device: HomeDevice) throws -> DeviceControl {
    guard let type = self.supportedDeviceTypes.first(where: { device.types.contains($0) }) else {
      return try GenericDeviceControl(device: device)
    }
    guard let builder = self.deviceControlBuilders[type.identifier] else {
      assertionFailure("No builder found for device type: \(type.identifier)")
      return try GenericDeviceControl(device: device)
    }
    return try builder(device)
  }
}
