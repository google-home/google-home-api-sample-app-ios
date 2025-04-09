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

import Foundation
import GoogleHomeSDK
import GoogleHomeTypes
import OSLog

/// The intended usage is to provide a list of pre-defined draft automations
/// for the user to choose from.
public final class AutomationsRepository: Sendable {
  typealias OnOffTrait = Matter.OnOffTrait
  typealias WindowCoveringTrait = Matter.WindowCoveringTrait
  typealias FanControlTrait = Matter.FanControlTrait
  typealias OvenCavityOperationalStateTrait = Matter.OvenCavityOperationalStateTrait
  typealias MediaPlaybackTrait = Matter.MediaPlaybackTrait
  typealias OccupancySensingTrait = Matter.OccupancySensingTrait
  typealias TemperatureMeasurementTrait = Matter.TemperatureMeasurementTrait
  typealias BooleanStateTrait = Matter.BooleanStateTrait
  typealias LevelControlTrait = Matter.LevelControlTrait
  typealias ThermostatTrait = Matter.ThermostatTrait
  typealias OperationalStateTrait = Matter.OperationalStateTrait
  typealias DoorLockTrait = Matter.DoorLockTrait
  typealias RvcRunModeTrait = Matter.RvcRunModeTrait
  typealias ColorControlTrait = Matter.ColorControlTrait

  private let home: Home
  private let structure: Structure

  public init(home: Home, structure: Structure) {
    self.home = home
    self.structure = structure
  }

  public func list() async throws -> [any DraftAutomation] {
    let devices = try await self.home.devices().list().filter{$0.structureID == structure.id}

    return await withTaskGroup(
      of: (any DraftAutomation)?.self,
      returning: [any DraftAutomation].self,
      body: { taskGroup in
        taskGroup.addTask { [weak self] in try? await self?.windowBlindsAutomation(devices: devices) }
        taskGroup.addTask { [weak self] in try? await self?.lightAndThermostatAutomation(devices: devices) }
        taskGroup.addTask { [weak self] in try? await self?.speakerAndFanAutomation(devices: devices) }
        taskGroup.addTask { [weak self] in try? await self?.lightAndTVPeriodicAutomation(devices: devices) }
        taskGroup.addTask { [weak self] in try? await self?.onOffAutomation(devices: devices) }
        taskGroup.addTask { [weak self] in try? await self?.lightAutomation(devices: devices) }
        var draftAutomations = [any DraftAutomation]()
        for await result in taskGroup {
          if let draftAutomation = result {
            draftAutomations.append(draftAutomation)
          }
        }
        return draftAutomations
      })
  }

  /// - Parameter devices: devices in current selected structure
  /// - Returns: the automation object to be created
  /// Simple automation that turns off a light when another light is turned off.
  public func onOffAutomation(devices: Set<HomeDevice>) async throws -> any DraftAutomation {
    // Obtain the devices to be used in the automation. In this case two OnOffLightDeviceTypes are needed.
    let onOffLightDevices = Array(devices.filter({ $0.types.contains(OnOffLightDeviceType.self) }))
    guard onOffLightDevices.count >= 2 else {
      Logger().error("Unable to find required OnOff devices.")
      throw HomeError.notFound("OnOffLightDeviceType")
    }

    return automation(
      name: "OnOffLight Automation",
      description: "Turn on a device when another device is turned on."
    ) {
      sequential {
        select {
          sequential {
            let onOffStarter = starter(onOffLightDevices[0], OnOffLightDeviceType.self, OnOffTrait.self)
            onOffStarter
            condition {
              onOffStarter.onOff.equals(true)
            }
          }
          manualStarter()
        }

        action(onOffLightDevices[1], OnOffLightDeviceType.self) {
          Matter.OnOffTrait.on()
        }
      }
    }
  }


  /// - Parameter devices: devices in current selected structure
  /// - Returns: the automation object to be created
  /// The automation will automatically close window blinds when the temperature outside drops below
  /// 60F and it's dark outside.
  public func windowBlindsAutomation(devices: Set<HomeDevice>) async throws -> any DraftAutomation {
    let temperatureSensorDevice = devices.first {
      $0.types.contains(TemperatureSensorDeviceType.self)
    }
    guard let temperatureSensorDevice else {
      Logger().error("Unable to find temperature sensor device.")
      throw HomeError.notFound("TemperatureSensorDeviceType")
    }
    let windowBlinds = devices.filter {
      $0.types.contains(WindowCoveringDeviceType.self)
    }
    guard !windowBlinds.isEmpty else {
      Logger().error("Unable to find window blinds device.")
      throw HomeError.notFound("WindowCoveringDeviceType")
    }
    let temperatureMeasurement = stateReader(
      temperatureSensorDevice,
      TemperatureSensorDeviceType.self,
      TemperatureMeasurementTrait.self
    )
    let time = stateReader(structure, Google.TimeTrait.self)
    return automation(
      name: "Close Window blinds",
      description:
      """
      Close window blinds when the temperature inside drops below 60F (15C) and it's dark outside.
      """
    ) {
      select {
        starter(
          temperatureSensorDevice,
          TemperatureSensorDeviceType.self,
          Matter.TemperatureMeasurementTrait.self
        )
        starter(structure, Google.TimeTrait.ScheduledEvent.self) {
          Google.TimeTrait.ScheduledEvent.solarTime(
            SolarTime(type: .sunrise, offset: .seconds(0)))
        }
        starter(structure, Google.TimeTrait.ScheduledEvent.self) {
          Google.TimeTrait.ScheduledEvent.solarTime(
            SolarTime(type: .sunset, offset: .seconds(0)))
        }
      }
      temperatureMeasurement
      time
      // 15 degrees C ~ 60 degrees F
      let exp1 = temperatureMeasurement.measuredValue.lessThan(1555)
      let exp2 = time.currentTime.between(time.sunriseTime, time.sunsetTime)
      condition {
        exp1.and(exp2.not())
      }
      parallel {
        for windowBlind in windowBlinds {
          action(windowBlind, WindowCoveringDeviceType.self) {
            WindowCoveringTrait.downOrClose()
          }
        }
      }
    }
  }

  /// - Parameter devices: devices in current selected structure
  /// - Returns: the automation object to be created
  /// This automation will turn on lights or turn off thermostat eco mode when you unlock the door.
  public func lightAndThermostatAutomation(devices: Set<HomeDevice>) async throws -> any DraftAutomation {
     let doorLock = devices.first {
       $0.types.contains(DoorLockDeviceType.self)
     }
     guard let doorLock else {
       Logger().error("Unable to find door lock device.")
       throw HomeError.notFound("No devices support DoorLockDeviceType")
     }
     let thermostat = devices.first {
       $0.types.contains(ThermostatDeviceType.self)
     }
     guard let thermostat else {
       Logger().error("Unable to find thermostat device.")
       throw HomeError.notFound("No devices support ThermostatDeviceType")
     }
     let lightDevices = devices.filter {
       $0.types.contains(OnOffLightDeviceType.self)
     }
     guard !lightDevices.isEmpty else {
       Logger().error("Unable to find lights device.")
       throw HomeError.notFound("No devices support OnOffLightDeviceType")
     }

     return automation(
       name: "Turn on lights and thermostat",
       description:
         """
         Turn on lights or turn off thermostat eco mode when you unlock the door.
         """
     ) {
       let doorLockEvent = starter(
         doorLock,
         DoorLockDeviceType.self,
         DoorLockTrait.LockOperationEvent.self
       )
       doorLockEvent
       condition {
         doorLockEvent.lockOperationType.equals(.unlock)
       }
       parallel {
         for light in lightDevices {
           action(light, OnOffLightDeviceType.self) {
             OnOffTrait.on()
           }
           // Assume the thermostat is in eco mode, set to auto.
           action(thermostat, ThermostatDeviceType.self) {
             Google.SimplifiedThermostatTrait.setSystemMode(systemMode: .auto)
           }
         }
       }
     }
   }

  /// - Parameter devices: devices in current selected structure
  /// - Returns: the automation object to be created
  /// This automation will play ocean wave sounds, turn on the fan and onOffPlugin
  /// when user says “Hey Google, I can’t sleep”
  public func speakerAndFanAutomation(devices: Set<HomeDevice>) async throws -> any DraftAutomation {
    let speaker = devices.first {
      $0.types.contains(SpeakerDeviceType.self)
    }
    guard let speaker else {
      Logger().error("Unable to find speaker device.")
      throw HomeError.notFound("No devices support SpeakerDeviceType")
    }
    let fan = devices.first {
      $0.types.contains(FanDeviceType.self)
    }
    guard let fan else {
      Logger().error("Unable to find fan device.")
      throw HomeError.notFound("No devices support FanDeviceType")
    }
    let plug = devices.first {
      $0.types.contains(OnOffPluginUnitDeviceType.self)
    }
    guard let plug else {
      Logger().error("Unable to find plug device.")
      throw HomeError.notFound("No devices support OnOffPluginUnitDeviceType")
    }
    let shades = devices.first {
      $0.types.contains(WindowCoveringDeviceType.self)
    }
    guard let shades else {
      Logger().error("Unable to find shades device.")
      throw HomeError.notFound("No devices support WindowCoveringDeviceType")
    }

    return automation(
      name: "Play sounds and turn on fan and plugin",
      description:
        """
        If user says “Hey Google, I can’t sleep”, play ocean wave sounds, turn on the fan and onOffPlugin.
        """
    ) {
      starter(structure, Google.VoiceStarterTrait.OkGoogleEvent.self) {
        Google.VoiceStarterTrait.OkGoogleEvent.query("I can't sleep")
      }
      parallel {
        action(speaker, SpeakerDeviceType.self) {
          Google.AssistantFulfillmentTrait.okGoogle(query: "Play ocean wave sounds")
        }
        action(fan, FanDeviceType.self) {
          OnOffTrait.on()
        }
        action(plug, OnOffPluginUnitDeviceType.self) {
          OnOffTrait.on()
        }
        action(shades, WindowCoveringDeviceType.self) {
          WindowCoveringTrait.downOrClose()
        }
      }
    }
  }

  /// - Parameter devices: devices in current selected structure
  /// - Returns: the automation object to be created
  /// This automation will broadcast alarm and periodically turn on/off lights and TV to deter intruders.
  public func lightAndTVPeriodicAutomation(devices: Set<HomeDevice>) async throws -> any DraftAutomation {
    let allLights = devices.filter {
      $0.types.contains(OnOffLightDeviceType.self)
    }
    let motionSensor = devices.first {
      $0.types.contains(OccupancySensorDeviceType.self)
    }
    guard let motionSensor else {
      Logger().error("Unable to find motion sensor device.")
      throw HomeError.notFound("No devices support OccupancySensorDeviceType")
    }
    let tv = devices.first {
      $0.types.contains(GoogleTVDeviceType.self)
    }
    guard let tv else {
      Logger().error("Unable to find TV device.")
      throw HomeError.notFound("No devices support GoogleTVDeviceType")
    }

    return automation(
      name: "Deter intruders",
      description:
        """
        If motion (sensor) is detected, broadcast alarm sound on smart speakers,
        turn lights on and off periodically and TV to deter intruders.
        """
    ) {
      let motionStarter =
        starter(motionSensor, OccupancySensorDeviceType.self, OccupancySensingTrait.self)
      let homeAwayState = stateReader(structure, Google.AreaPresenceStateTrait.self)
      motionStarter
      homeAwayState

      let exp1 = homeAwayState.presenceState.equals(.presenceStateVacant)
      let exp2 = motionStarter.occupancy.equals(.occupied)

      condition {
        exp1.and(exp2)
      }

      action(structure) {
        Google.AssistantBroadcastTrait.broadcast(msg: "ALARM! ALARM! ALARM!")
      }

      turnOnOff(lights: allLights, tv: tv, shouldTurnOn: true)
      delay(for: Duration.seconds(5))
      turnOnOff(lights: allLights, tv: tv, shouldTurnOn: false)
      delay(for: Duration.seconds(5))
      turnOnOff(lights: allLights, tv: tv, shouldTurnOn: true)
    }
  }


  /// TODO: create automation
  /// - Parameter devices: devices in current selected structure
  /// - Returns: the automation object to be created
  /// This automation will turn off the light after 5 seconds.
  public func lightAutomation(devices: Set<HomeDevice>) async throws -> any DraftAutomation {
//    let light = devices.first { $0.name == "light2" }
//
//    guard let light else {
//      Logger().error("Unable to find light device with name light2")
//      throw HomeError.notFound("No devices support OnOffLightDeviceType")
//    }
//
//    return automation(
//      name: "Turn off light after 5 seconds",
//      description:
//        """
//        Turns off light2 after it has been on for 5 seconds.
//        """
//    ) {
//      let onOffStarter = starter(light, OnOffLightDeviceType.self, OnOffTrait.self)
//
//      onOffStarter
//      condition {
//        onOffStarter.onOff.equals(true)
//      }
//      delay(for: Duration.seconds(5))
//      action(light, OnOffLightDeviceType.self) {
//        OnOffTrait.off()
//      }
//    }
    AlertHelper.showAlert(text: "TODO: create automation")
    return automation(){}
  }

  private func turnOnOff(
    lights: Set<HomeDevice>,
    tv: HomeDevice,
    shouldTurnOn: Bool
  ) -> ParallelFlow {
    parallel {
      for light in lights {
        action(light, OnOffLightDeviceType.self) {
          shouldTurnOn ? OnOffTrait.on() : OnOffTrait.off()
        }
      }
      action(tv, GoogleTVDeviceType.self) {
        shouldTurnOn ? OnOffTrait.on() : OnOffTrait.off()
      }
    }
  }
}
