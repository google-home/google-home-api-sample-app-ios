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

/// Default values for Thermostat traits, based on the Matter specification.
/// These are used as fallbacks when the device does not report a value.
internal enum CommonMatterSpecDefaults {
  static let minSetpointDeadBandCentidegrees: Int16 = 200
  static let minCoolSetpointLimitCentidegrees: Int16 = 1600
  static let minHeatSetpointLimitCentidegrees: Int16 = 700
  static let maxCoolSetpointLimitCentidegrees: Int16 = 3200
  static let maxHeatSetpointLimitCentidegrees: Int16 = 3000
}

internal func deciDegreesToCentiDegrees(_ deciDegrees: Int) -> Int {
  return deciDegrees * 10
}

extension Matter.ThermostatTrait {

  // MARK: - Computed Properties for Thermostat State

  /// The current cooling setpoint for the thermostat in centidegrees (0.01°C).
  /// This only considers the occupiedCoolingSetpoint, which is mandatory on all devices.
  var coolingSetpoint: Int16? {
    return self.attributes.occupiedCoolingSetpoint
  }

  /// The current heating setpoint for the thermostat in centidegrees (0.01°C).
  /// This only considers the occupiedHeatingSetpoint, which is mandatory on all devices.
  var heatingSetpoint: Int16? {
    return self.attributes.occupiedHeatingSetpoint
  }

  /// The the minimum legal distance between heating and cooling setpoints in centidegrees (0.01°C).
  var minSetpointDeadBand: Int16 {
    if let deadBandDeci = self.attributes.minSetpointDeadBand {
      return Int16(deciDegreesToCentiDegrees(Int(deadBandDeci)))
    }
    return CommonMatterSpecDefaults.minSetpointDeadBandCentidegrees
  }

  /// The minimum cooling setpoint limit in centidegrees (0.01°C).
  var minCoolSetpointLimit: Int16 {
    return self.attributes.minCoolSetpointLimit ?? self.attributes.absMinCoolSetpointLimit
      ?? CommonMatterSpecDefaults.minCoolSetpointLimitCentidegrees
  }

  /// The minimum heating setpoint limit in centidegrees (0.01°C).
  var minHeatSetpointLimit: Int16 {
    return self.attributes.minHeatSetpointLimit ?? self.attributes.absMinHeatSetpointLimit
      ?? CommonMatterSpecDefaults.minHeatSetpointLimitCentidegrees
  }

  /// The maximum cooling setpoint limit in centidegrees (0.01°C).
  var maxCoolSetpointLimit: Int16 {
    return self.attributes.maxCoolSetpointLimit ?? self.attributes.absMaxCoolSetpointLimit
      ?? CommonMatterSpecDefaults.maxCoolSetpointLimitCentidegrees
  }

  /// The maximum heating setpoint limit in centidegrees (0.01°C).
  var maxHeatSetpointLimit: Int16 {
    return self.attributes.maxHeatSetpointLimit ?? self.attributes.absMaxHeatSetpointLimit
      ?? CommonMatterSpecDefaults.maxHeatSetpointLimitCentidegrees
  }

  /// The current running mode of the thermostat (e.g., heating, cooling).
  var runningMode: Matter.ThermostatTrait.ThermostatRunningModeEnum {
    return self.attributes.thermostatRunningMode ?? .unrecognized_
  }

  /// The current target system mode of the thermostat (e.g., Heat, Cool, Off).
  var systemMode: Matter.ThermostatTrait.SystemModeEnum {
    return self.attributes.systemMode ?? .unrecognized_
  }

  /// A set of system modes supported by this thermostat based on its features.
  var supportedSystemModes: Set<Matter.ThermostatTrait.SystemModeEnum> {
    var modes: Set<Matter.ThermostatTrait.SystemModeEnum> = [.off]

    guard let features = self.attributes.featureMap else { return modes }

    // 'Auto' mode is supported only if the thermostat supports auto mode, heating, and cooling.
    if features.contains(.autoMode) && features.contains(.heating) && features.contains(.cooling) {
      modes.insert(.auto)
    }
    if features.contains(.heating) {
      modes.insert(.heat)
    }
    if features.contains(.cooling) {
      modes.insert(.cool)
    }
    return modes
  }

  // MARK: - Validation Logic

  /// Validates a potential new cooling setpoint against the thermostat's constraints.
  ///
  /// - Parameter coolSetPointCentiDegrees: The proposed new cooling setpoint in centi-degrees Celsius.
  /// - Returns: `true` if the update is valid, `false` otherwise.
  func isValidCoolingSetpointUpdate(coolSetPointCentiDegrees: Int16) -> Bool {
    guard coolSetPointCentiDegrees >= self.minCoolSetpointLimit,
      coolSetPointCentiDegrees <= self.maxCoolSetpointLimit
    else {
      return false
    }

    guard self.systemMode.isModeCoolingRelated else { return false }


    // Validate dead band distance.
    if let heatSetpoint = self.heatingSetpoint {
      return coolSetPointCentiDegrees >= (heatSetpoint + self.minSetpointDeadBand)
    }

    // Valid if no heating setpoint exists to compare against.
    return true
  }

  /// Validates a potential new heating setpoint against the thermostat's constraints.
  ///
  /// - Parameter heatSetPointCentiDegrees: The proposed new heating setpoint in centi-degrees Celsius.
  /// - Returns: `true` if the update is valid, `false` otherwise.
  func isValidHeatingSetpointUpdate(heatSetPointCentiDegrees: Int16) -> Bool {
    guard heatSetPointCentiDegrees >= self.minHeatSetpointLimit,
      heatSetPointCentiDegrees <= self.maxHeatSetpointLimit
    else {
      return false
    }

    guard self.systemMode.isModeHeatingRelated else { return false }


    // Validate dead band distance.
    if let coolSetpoint = self.coolingSetpoint {
      return heatSetPointCentiDegrees <= (coolSetpoint - self.minSetpointDeadBand)
    }

    // Valid if no cooling setpoint exists to compare against.
    return true
  }

  /// Checks if a given system mode is supported by this thermostat.
  ///
  /// - Parameter mode: The `SystemModeEnum` to check.
  /// - Returns: `true` if the mode is supported, `false` otherwise.
  func isModeSupported(_ mode: Matter.ThermostatTrait.SystemModeEnum) -> Bool {
    return supportedSystemModes.contains(mode)
  }

  // MARK: - Update Setpoints

  /// Sets the occupied cooling setpoint for the thermostat.
  ///
  /// - Parameter newValueCentiDegrees: The new temperature in centidegrees (0.01°C).
  func setOccupiedCoolingPoint(to newValueCentiDegrees: Int16) async throws {
    _ = try await self.update {
      $0.setOccupiedCoolingSetpoint(newValueCentiDegrees)
    }
  }

  /// Sets the occupied heating setpoint for the thermostat.
  ///
  /// - Parameter newValueCentiDegrees: The new temperature in centidegrees (0.01°C).
  func setOccupiedHeatingPoint(to newValueCentiDegrees: Int16) async throws {
    _ = try await self.update {
      $0.setOccupiedHeatingSetpoint(newValueCentiDegrees)
    }
  }
}

extension Matter.ThermostatTrait.SystemModeEnum {
  /// Checks if this system mode is related to cooling.
  var isModeCoolingRelated: Bool {
    switch self {
    case .auto, .cool, .precooling:
      return true
    default:
      return false
    }
  }

  /// Checks if this system mode is related to heating.
  var isModeHeatingRelated: Bool {
    switch self {
    case .auto, .heat, .emergencyHeat:
      return true
    default:
      return false
    }
  }
}
