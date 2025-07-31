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
import Foundation
import GoogleHomeSDK
import GoogleHomeTypes
import OSLog

// An 'add-on' to the DeviceControl that handles range functions like brightness.
class RangeControl: ObservableObject {
  // A label displayed in DeviceDetailView
  let label: String

  // A static range for the slider.
  @Published var range: ClosedRange<Float>

  // Published value that should be bound to a slider in the UI. Will update the LevelControlTrait
  // in core when the bound value updates.
  @Published var rangeValue: Float

  init(
    range: ClosedRange<Float> = 0.0...1.0, rangeValue: Float = 0.0,
    label: String
  ) {
    self.range = range
    self.rangeValue = rangeValue
    self.label = label
  }
}

extension Matter.LevelControlTrait {
  // Default values for the LevelControlTrait per matter spec.
  static var defaultMinLevel: UInt8 { 0 }
  static var defaultMaxLevel: UInt8 { 254 }

  /// Calculates the current level as a percentage.
  func currentLevelFromPercentage(_ percentage: Float) -> UInt8 {
    let min = self.attributes.minLevel ?? Self.defaultMinLevel
    let max = self.attributes.maxLevel ?? Self.defaultMaxLevel
    return UInt8(
      truncating: NSNumber(value: percentage * (Float(max) - Float(min)))) + min
  }

  func makeRangeControl() -> RangeControl {
    let min = self.attributes.minLevel ?? Self.defaultMinLevel
    let max = self.attributes.maxLevel ?? Self.defaultMaxLevel
    let currentLevel =
      self.attributes.currentLevel?.clamped(to: min...max) ?? min
    let rangeValue = Float((currentLevel - min)) / (Float(max) - Float(min))
    return RangeControl(rangeValue: rangeValue, label: "Current level")
  }
}

extension Matter.FanControlTrait {
  func makeRangeControl() -> RangeControl? {
    guard let rangeValue = self.calculateRangeValue() else {
      return nil
    }
    return RangeControl(rangeValue: rangeValue, label: "Percent setting")
  }

  func calculateRangeValue() -> Float? {
    guard let percentSetting = self.attributes.percentSetting else {
      return nil
    }

    return Float(percentSetting) / 100.0
  }
}
