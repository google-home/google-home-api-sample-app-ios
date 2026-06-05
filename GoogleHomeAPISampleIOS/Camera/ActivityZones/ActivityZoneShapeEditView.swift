// Copyright 2026 Google LLC
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

/// A full-screen dedicated canvas view for adjusting the physical boundaries of an Activity Zone.
/// Implements a transactional draft cycle: modifications are stored in a local copy,
/// and only synced back to the parent binder upon explicit user confirmation.
struct ActivityZoneShapeEditView: View {
  private enum Constants {
    static let outerSpacing: CGFloat = 0
    static let bannerTextSpacing: CGFloat = 4
    static let canvasShadowRadius: CGFloat = 8
    static let canvasPadding: CGFloat = 16
  }
  /// Binding referencing the persistent parent zone model.
  @Binding var zone: ActivityZone
  /// Transient state holding details of the zone shape currently being adjusted.
  /// Changes are discarded if the user exits without saving.
  @State var zoneCopy: ActivityZone
  /// Static background UIImage snapshot of the camera viewport.
  let backgroundImage: UIImage?
  /// Maximum boundaries of the Cartesian coordinate system.
  let zoneMaxSize: CGSize
  @Environment(\.dismiss) private var dismiss
  /// Initializes the shape editor view.
  ///
  /// - Parameters:
  ///   - zone: Reference binding to the target parent zone.
  ///   - backgroundImage: Live snapshot background image.
  ///   - zoneMaxSize: Absolute bounds limits.
  init(
    zone: Binding<ActivityZone>,
    backgroundImage: UIImage?,
    zoneMaxSize: CGSize
  ) {
    self._zone = zone
    self._zoneCopy = State(initialValue: zone.wrappedValue)
    self.backgroundImage = backgroundImage
    self.zoneMaxSize = zoneMaxSize
  }
  var body: some View {
    VStack(spacing: Constants.outerSpacing) {
      // Instruction Banner giving helpful ergonomic advice
      VStack(alignment: .leading, spacing: Constants.bannerTextSpacing) {
        Text("Drag the round handles to adjust the zone's shape.")
          .font(.subheadline)
          .fontWeight(.medium)
          .foregroundColor(.primary)
        Text(
          "Ensure the polygon covers only the critical area where you want motion events detected."
        )
        .font(.caption)
        .foregroundColor(.secondary)
      }
      .padding()
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color(uiColor: .secondarySystemBackground))
      Spacer()
      // Interactive Overlay canvas containing vertex drag controls
      ActivityZoneOverlayView(
        zone: $zoneCopy,
        backgroundImage: backgroundImage,
        zoneMaxSize: zoneMaxSize,
        editable: true
      )
      .shadow(radius: Constants.canvasShadowRadius)
      .padding(Constants.canvasPadding)
      Spacer()
    }
    .navigationTitle("Edit Zone Shape")
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarBackButtonHidden(true)  // Force user to explicitly use custom save/cancel buttons
    .background(Color(uiColor: .systemGroupedBackground))
    .toolbar {
      // Exit and discard draft changes
      ToolbarItem(placement: .cancellationAction) {
        Button {
          dismiss()
        } label: {
          Image(systemName: "xmark")
            .font(.body.bold())
            .foregroundColor(.primary)
        }
      }
      // Apply changes and propagate draft values back to the parent binder
      ToolbarItem(placement: .confirmationAction) {
        Button {
          zone = zoneCopy
          dismiss()
        } label: {
          Image(systemName: "checkmark")
            .font(.body.bold())
            .foregroundColor(.accentColor)
        }
      }
    }
  }
}
