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

extension Color {
  static let defaultActiveContainerVariant = Color(
    red: 217.0 / 255.0, green: 226.0 / 255.0, blue: 1.0)
  // #404658
  static let defaultActiveContainerVariantDark = Color(
    red: 64.0 / 255.0, green: 70.0 / 255.0, blue: 88.0 / 255.0)
  static let defaultActiveContainer = Color(
    red: 237.0 / 255.0, green: 240.0 / 255.0, blue: 1.0)

  static let inactiveContainer = Color(
    red: 31.0 / 255.0, green: 31.0 / 255.0, blue: 31.0 / 255.0, opacity: 0.12)
  static let onInactiveContainer = Color(
    red: 31.0 / 255.0, green: 31.0 / 255.0, blue: 31.0 / 255.0, opacity: 0.78)
  static let inactiveContainerDark = Color(
    red: 227.0 / 227.0, green: 227.0 / 255.0, blue: 227.0 / 255.0, opacity: 0.12)
  static let onInactiveContainerDark = Color(
    red: 227.0 / 227.0, green: 227.0 / 255.0, blue: 227.0 / 255.0, opacity: 0.78)

  // #303033
  static let defaultActiveContainerDark = Color(
    red: 48.0 / 255.0, green: 48.0 / 255.0, blue: 51.0 / 255.0)
  static let onDefaultActiveContainer = Color(red: 0.0, green: 99.0 / 255.0, blue: 1.0)
  // #D9E2FF
  static let onDefaultActiveContainerDark = Color(
    red: 217.0 / 255.0, green: 226.0 / 255.0, blue: 1.0)

  // #FFEFC9
  static let lightActiveContainer = Color(
    red: 1.0, green: 240.0 / 255.0, blue: 201.0 / 255.0)
  // #33302A
  static let lightActiveContainerDark = Color(
    red: 51.0 / 255.0, green: 48.0 / 255.0, blue: 42.0 / 255.0)
  // #FFE082
  static let lightActiveContainerVariant = Color(
    red: 1.0, green: 224.0 / 255.0, blue: 130.0 / 255.0)
  // #50462A
  static let lightActiveContainerVariantDark = Color(
    red: 80.0 / 255.0, green: 70.0 / 255.0, blue: 42.0 / 255.0)
  // #745B00
  static let onLightActiveContainer = Color(
    red: 116.0 / 255.0, green: 91.0 / 255.0, blue: 0.0)
  // #F1C100
  static let onLightActiveContainerDark = Color(
    red: 240.0 / 255.0, green: 193.0 / 255.0, blue: 0.0)
}
