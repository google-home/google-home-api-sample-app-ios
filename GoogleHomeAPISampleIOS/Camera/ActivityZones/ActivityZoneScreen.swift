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

import GoogleHomeSDK
import SwiftUI
import UIKit

/// The primary entry screen for the Activity Zones feature.
/// It displays a live visual preview overlay of defined zones over the camera background
/// and lists each configured zone for selective editing or creation of new ones.
public struct ActivityZoneScreen: View {
  /// Handles subscriptions and coordinate mappings for GHP traits.
  @State private var viewModel: ActivityZoneViewModel
  private let home: Home
  private let deviceID: String
  private let backgroundImage: UIImage?
  private enum Constants {
    static let maxZoneCount = 4
    static let mapCornerRadius: CGFloat = 12
    static let mapShadowRadius: CGFloat = 4
    static let colorIndicatorSize: CGFloat = 12
    static let colorIndicatorTrailingPadding: CGFloat = 4
    static let listRowTextSpacing: CGFloat = 4
    static let listRowVerticalPadding: CGFloat = 4
    static let emptyStateVerticalSpacing: CGFloat = 16
    static let emptyStateIconSize: CGFloat = 48
  }
  /// The GHP specification defines a maximum of 4 custom zones per camera.
  private let maxZoneCount: Int = Constants.maxZoneCount
  /// Initializes the activity zones screen.
  /// - Parameters:
  ///   - home: The Google Home SDK instance.
  ///   - deviceID: The ID of the active camera or doorbell.
  ///   - backgroundImage: An optional static snapshot of the camera feed to draw shapes over.
  public init(
    home: Home,
    deviceID: String,
    backgroundImage: UIImage?
  ) {
    self.home = home
    self.deviceID = deviceID
    self.backgroundImage = backgroundImage
    self._viewModel = State(
      initialValue: ActivityZoneViewModel(home: home, deviceID: deviceID, backgroundImage: backgroundImage)
    )
  }
  public var body: some View {
    // 1. Render loading spinner until trait subscription resolves and extracts data
    if !viewModel.activityZonesInitialized {
      ProgressView("Loading Activity Zones...")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    } else if let zones = viewModel.zones {
      let customZones = zones.filter { !$0.isDefaultZone }
      // 2. Render the primary zones list and visual preview
      List {
        // Section 1: Live Visual Preview Overlay
        Section {
          ActivityZoneOverlayView(
            zones: zones,
            backgroundImage: viewModel.backgroundImage,
            zoneMaxSize: viewModel.zoneMaxSize,
            inverse: false
          )
          .listRowInsets(EdgeInsets())
          .listRowBackground(Color.clear)
          .cornerRadius(Constants.mapCornerRadius)
          .shadow(radius: Constants.mapShadowRadius)
        } header: {
          Text("Zone Map")
        }
        // Section 2: Defined Zones List & Editing Flow
        Section {
          ForEach(zones) { zone in
            NavigationLink {
              ActivityZoneEditView(
                zones: zones,
                editingZoneID: zone.id,
                backgroundImage: viewModel.backgroundImage,
                zoneMaxSize: viewModel.zoneMaxSize,
                saveZoneCallback: { updatedZone in
                  await viewModel.updateActivityZone(zone: updatedZone)
                },
                deleteZoneCallback: { targetZone in
                  await viewModel.deleteActivityZone(zone: targetZone)
                }
              )
            } label: {
              HStack {
                // Small color dot indicating zone color assignment
                Circle()
                  .fill(zone.color.swiftUIColor)
                  .frame(width: Constants.colorIndicatorSize, height: Constants.colorIndicatorSize)
                  .padding(.trailing, Constants.colorIndicatorTrailingPadding)

                VStack(alignment: .leading, spacing: Constants.listRowTextSpacing) {
                  Text(zone.isDefaultZone ? ActivityZone.defaultZoneName : zone.name)
                    .font(.headline)

                  // Render summary of enabled triggers (Person, Motion, etc.) for this zone
                  let activeTriggers = zone.uses.filter { $0.isSelected }
                  if !activeTriggers.isEmpty {
                    Text(activeTriggers.map { $0.displayName }.joined(separator: ", "))
                      .font(.caption)
                      .foregroundColor(.secondary)
                  } else {
                    Text("No triggers configured")
                      .font(.caption)
                      .foregroundColor(.secondary)
                  }
                }
              }
              .padding(.vertical, Constants.listRowVerticalPadding)
            }
          }
          // Section 3: Add Zone Entry point (visible only if limit has not been reached)
          if customZones.count < maxZoneCount {
            NavigationLink {
              ActivityZoneEditView(
                zones: zones + [viewModel.getNewActivityZoneTemplate()],
                editingZoneID: nil,  // Passing nil triggers creation state
                backgroundImage: viewModel.backgroundImage,
                zoneMaxSize: viewModel.zoneMaxSize,
                saveZoneCallback: { newZone in
                  await viewModel.addActivityZone(zone: newZone)
                },
                deleteZoneCallback: { _ in }  // No deletion callback needed for unsaved zones
              )
            } label: {
              Label("Add Custom Zone", systemImage: "plus.circle.fill")
                .foregroundColor(.accentColor)
                .font(.body)
            }
          }
        } header: {
          Text("Configured Zones (\(customZones.count)/\(maxZoneCount))")
        } footer: {
          Text(
            "You can configure up to \(maxZoneCount) custom activity zones to trigger events in specific areas of interest."
          )
        }
      }
      .listStyle(.insetGrouped)
      .navigationTitle("Activity Zones")
    } else {
      // Fallback state if traits are missing or incompatible
      VStack(spacing: Constants.emptyStateVerticalSpacing) {
        Image(systemName: "video.slash.fill")
          .font(.system(size: Constants.emptyStateIconSize))
          .foregroundColor(.secondary)
        Text("Activity Zones are not supported on this device.")
          .font(.headline)
          .foregroundColor(.secondary)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color(uiColor: .systemGroupedBackground))
    }
  }
}
