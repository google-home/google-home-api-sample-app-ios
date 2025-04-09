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

import SwiftUI
import GoogleHomeSDK
import GoogleHomeTypes
import OSLog

@main
struct GoogleHomeAPISampleIOS: App {
  init() {
    Logger().info("Home API Version: \(Home.sdkVersion)")
    Home.configure {
      $0.sharedAppGroup = "HOME_API_TODO_ADD_APP_GROUP"
      $0.referencedAutomationTypes = ReferencedAutomationTypes(
        deviceTypes: [
          OnOffLightDeviceType.self,
          TemperatureSensorDeviceType.self,
          WindowCoveringDeviceType.self,
          GoogleTVDeviceType.self,
        ],
        traits: [
          Google.TimeTrait.self,
          Google.TogglesTrait.self,
          Google.VolumeTrait.self,
          Google.ExtendedMediaInputTrait.self,
          Google.SimplifiedOnOffTrait.self,
          Google.BrightnessTrait.self,
          Google.ExtendedFanControlTrait.self,
          Google.ExtendedThermostatTrait.self,
          Google.SimplifiedThermostatTrait.self,
          Google.AreaPresenceStateTrait.self,
          Google.AreaAttendanceStateTrait.self,
          Matter.LevelControlTrait.self,
          Matter.OnOffTrait.self,
          Matter.TemperatureMeasurementTrait.self,
          Matter.WindowCoveringTrait.self,
          Matter.MediaPlaybackTrait.self,
          Matter.TotalVolatileOrganicCompoundsConcentrationMeasurementTrait.self,
          Matter.AirQualityTrait.self,
          Matter.CarbonDioxideConcentrationMeasurementTrait.self,
          Matter.CarbonMonoxideConcentrationMeasurementTrait.self,
          Matter.OperationalStateTrait.self,
          Matter.ColorControlTrait.self,
          Matter.ThermostatTrait.self,
          Matter.TemperatureControlTrait.self,
          Matter.RelativeHumidityMeasurementTrait.self,
          Matter.Pm25ConcentrationMeasurementTrait.self,
          Matter.OvenCavityOperationalStateTrait.self,
          Matter.RvcOperationalStateTrait.self,
        ]
      )
    }
  }

  var body: some Scene {
        WindowGroup {
            MainView()
        }
    }
}
