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

import CoreFoundation
import SwiftUI

/// An adjustable background view to control ranged devices.
struct RangeView: View {
  @State private var currentRangeValue: Float = 0
  @ObservedObject private var rangeControl: RangeControl
  private var colorPalette: ColorPalette
  @Environment(\.colorScheme) var colorScheme: ColorScheme

  init(rangeControl: RangeControl, colorPalette: ColorPalette = .default) {
    self.rangeControl = rangeControl
    self.colorPalette = colorPalette
    self.currentRangeValue = rangeControl.rangeValue
  }

  var body: some View {
    GeometryReader { metrics in
      ZStack(alignment: .leading) {
        self.colorPalette.containerColor(colorScheme: self.colorScheme)
        self.colorPalette.containerVariantColor(colorScheme: self.colorScheme)
          .frame(width: metrics.size.width * self.fillPercentage)
      }
      .gesture(
        DragGesture()
          .onChanged { value in
            let dragPercentage = Float(value.location.x / metrics.size.width)
            self.currentRangeValue =
              (dragPercentage
              * (self.rangeControl.range.upperBound - self.rangeControl.range.lowerBound)
              + self.rangeControl.range.lowerBound)
              .clamped(to: rangeControl.range)
          }
          .onEnded { value in
            self.rangeControl.rangeValue = self.currentRangeValue
          }
      )
      .clipShape(RoundedRectangle(cornerRadius: .deviceTileCornerRadius))
    }
  }

  private var fillPercentage: CGFloat {
    return CGFloat(
      (self.currentRangeValue - self.rangeControl.range.lowerBound)
        / (self.rangeControl.range.upperBound - self.rangeControl.range.lowerBound)
    ).clamped(to: 0...1)
  }
}
