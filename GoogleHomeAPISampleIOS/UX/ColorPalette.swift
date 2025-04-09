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

/// Color palette for UX elements.
struct ColorPalette {
  let activeContainerColor: Color
  let activeContainerDarkColor: Color
  let activeContainerVariantColor: Color
  let activeContainerVariantDarkColor: Color
  let onActiveContainerColor: Color
  let onActiveContainerDarkColor: Color
  let inactiveContainerColor: Color
  let inactiveContainerDarkColor: Color
  let onInactiveContainerColor: Color
  let onInactiveContainerDarkColor: Color

  static let `default` = ColorPalette(
    activeContainerColor: .defaultActiveContainer,
    activeContainerDarkColor: .defaultActiveContainerDark,
    activeContainerVariantColor: .defaultActiveContainerVariant,
    activeContainerVariantDarkColor: .defaultActiveContainerVariantDark,
    onActiveContainerColor: .onDefaultActiveContainer,
    onActiveContainerDarkColor: .onDefaultActiveContainerDark,
    inactiveContainerColor: .inactiveContainer,
    inactiveContainerDarkColor: .inactiveContainerDark,
    onInactiveContainerColor: .onInactiveContainer,
    onInactiveContainerDarkColor: .onInactiveContainerDark
  )

  static let light = ColorPalette(
    activeContainerColor: .lightActiveContainer,
    activeContainerDarkColor: .lightActiveContainerDark,
    activeContainerVariantColor: .lightActiveContainerVariant,
    activeContainerVariantDarkColor: .lightActiveContainerVariantDark,
    onActiveContainerColor: .onLightActiveContainer,
    onActiveContainerDarkColor: .onLightActiveContainerDark,
    inactiveContainerColor: .inactiveContainer,
    inactiveContainerDarkColor: .inactiveContainerDark,
    onInactiveContainerColor: .onInactiveContainer,
    onInactiveContainerDarkColor: .onInactiveContainerDark
  )

  init(
    activeContainerColor: Color,
    activeContainerDarkColor: Color,
    activeContainerVariantColor: Color,
    activeContainerVariantDarkColor: Color,
    onActiveContainerColor: Color,
    onActiveContainerDarkColor: Color,
    inactiveContainerColor: Color,
    inactiveContainerDarkColor: Color,
    onInactiveContainerColor: Color,
    onInactiveContainerDarkColor: Color
  ) {
    self.activeContainerColor = activeContainerColor
    self.activeContainerDarkColor = activeContainerDarkColor
    self.activeContainerVariantColor = activeContainerVariantColor
    self.activeContainerVariantDarkColor = activeContainerVariantDarkColor
    self.onActiveContainerColor = onActiveContainerColor
    self.onActiveContainerDarkColor = onActiveContainerDarkColor
    self.inactiveContainerColor = inactiveContainerColor
    self.inactiveContainerDarkColor = inactiveContainerDarkColor
    self.onInactiveContainerColor = onInactiveContainerColor
    self.onInactiveContainerDarkColor = onInactiveContainerDarkColor
  }

  func containerColor(
    colorScheme: ColorScheme = .light, isActive: Bool = true
  ) -> Color {
    guard isActive else { return self.inactiveContainerColor(colorScheme: colorScheme) }
    switch colorScheme {
    case .light: return self.activeContainerColor
    case .dark: return self.activeContainerDarkColor
    @unknown default: return self.activeContainerColor
    }
  }

  func containerVariantColor(
    colorScheme: ColorScheme = .light, isActive: Bool = true
  ) -> Color {
    guard isActive else { return self.inactiveContainerColor(colorScheme: colorScheme) }
    switch colorScheme {
    case .light: return self.activeContainerVariantColor
    case .dark: return self.activeContainerVariantDarkColor
    @unknown default: return self.activeContainerVariantColor
    }
  }

  func onContainerColor(
    colorScheme: ColorScheme = .light, isActive: Bool = true
  ) -> Color {
    guard isActive else { return self.onInactiveContainerColor(colorScheme: colorScheme) }
    switch colorScheme {
    case .light: return self.onActiveContainerColor
    case .dark: return self.onActiveContainerDarkColor
    @unknown default: return self.onActiveContainerColor
    }
  }

  func inactiveContainerColor(colorScheme: ColorScheme = .light) -> Color {
    switch colorScheme {
    case .light: return self.inactiveContainerColor
    case .dark: return self.inactiveContainerDarkColor
    @unknown default: return self.inactiveContainerColor
    }
  }

  func onInactiveContainerColor(colorScheme: ColorScheme = .light) -> Color {
    switch colorScheme {
    case .light: return self.onInactiveContainerColor
    case .dark: return self.onInactiveContainerDarkColor
    @unknown default: return self.onInactiveContainerColor
    }
  }
}
