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
/// An instance of `DeviceControl` representing a sensor with a temperature value.
final class TemperatureSensorControl: SensorControl<TemperatureSensorDeviceType> {
  /// Provided to the generic publisher to convert from an event to the `DeviceTileInfo` state.
  override func updateTileInfo() {
    guard
      let deviceType = self.sensorDeviceType
    else {
      return
    }
    let hundredths = deviceType.matterTraits.temperatureMeasurementTrait?.attributes
      .measuredValue
      ?? 0
    let degrees = Self.hundredthsToCelsius(hundredths: hundredths)
    self.tileInfo = DeviceTileInfo(
      title: self.device.name,
      typeName: "Temperature sensor",
      imageName: "sensors_symbol",
      isActive: true,
      isBusy: false,
      statusLabel: "\(degrees) °C",
      attributes: [
        ["Temperature": "\(degrees) °C"]
      ],
      error: nil
    )
  }
  private static func hundredthsToCelsius(hundredths: Int16) -> Float {
    return Float(hundredths) / 100.0
  }
}
