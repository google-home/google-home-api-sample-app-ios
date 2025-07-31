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

import GoogleHomeTypes

/// An instance of `SensorControl` representing a sensor with a simple BooleanState.
final class OccupancySensorControl: SensorControl<OccupancySensorDeviceType> {

  /// Provided to the generic publisher to convert from an event to the `DeviceTileInfo` state.
  override func updateTileInfo() {
    guard
      let deviceType = self.sensorDeviceType
    else {
      return
    }

    let isOccupied: Bool =
      deviceType.matterTraits.occupancySensingTrait?.attributes.occupancy == .occupied
    self.tileInfo = DeviceTileInfo(
      title: self.device.name,
      typeName: "Occupancy sensor",
      imageName: "sensors_symbol",
      isActive: isOccupied,
      isBusy: false,
      statusLabel: isOccupied ? "Occupied" : "Unoccupied",
      attributes: [["Occupancy": isOccupied ? "Occupied" : "Unoccupied"]],
      error: nil
    )
  }
}
