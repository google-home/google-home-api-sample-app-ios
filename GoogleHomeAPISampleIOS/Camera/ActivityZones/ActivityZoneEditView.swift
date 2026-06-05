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

import OSLog
import SwiftUI
import UIKit

/// A detailed form view for editing a single Activity Zone's settings: name, color, shape, and triggers.
/// Handles both custom zones and the non-deletable default (outside zones) zone.
struct ActivityZoneEditView: View {
  private enum Constants {
    static let mapCornerRadius: CGFloat = 12
    static let mapShadowRadius: CGFloat = 4
    static let mapCaptionPadding: CGFloat = 4
    static let colorIndicatorSize: CGFloat = 12
    static let deleteButtonAlignmentOffset: CGFloat = 0
  }
  private static let newZoneDefaultName = "New Zone"
  /// The presentation environment, used to programmatically pop back to the main list.
  @Environment(\.dismiss) private var dismiss
  /// Local state containing the draft copy of the edited zone details.
  @State private var viewModel: ActivityZoneEditViewModel
  /// Controls the visibility of the destructive delete alert confirmation.
  @State private var showDeleteZoneAlert = false
  private let allZones: [ActivityZone]
  private let backgroundImage: UIImage?
  private let zoneMaxSize: CGSize
  private let saveZoneCallback: (ActivityZone) async -> Void
  private let deleteZoneCallback: (ActivityZone) async -> Void
  /// Initializes the Activity Zone edit screen.
  ///
  /// - Parameters:
  ///   - zones: List of all currently configured zones on the device.
  ///   - editingZoneID: The ID of the active zone to edit, or `nil` if configuring a new zone.
  ///   - backgroundImage: Static background UIImage representing the camera view.
  ///   - zoneMaxSize: Maximum size of the SDK coordinate boundaries.
  ///   - saveZoneCallback: Async callback triggered when "Save" is pressed.
  ///   - deleteZoneCallback: Async callback triggered when "Delete" is confirmed.
  init(
    zones: [ActivityZone],
    editingZoneID: String?,
    backgroundImage: UIImage?,
    zoneMaxSize: CGSize,
    saveZoneCallback: @escaping ((ActivityZone) async -> Void),
    deleteZoneCallback: @escaping ((ActivityZone) async -> Void)
  ) {
    self.allZones = zones
    self.backgroundImage = backgroundImage
    self.zoneMaxSize = zoneMaxSize
    self.saveZoneCallback = saveZoneCallback
    self.deleteZoneCallback = deleteZoneCallback
    // 1. Resolve the correct active zone based on the ID.
    // If editingZoneID is nil, we extract the template zone (which is the last element added).
    let initialZone: ActivityZone
    if let editingZoneID {
      if let foundZone = zones.first(where: { $0.id == editingZoneID }) {
        initialZone = foundZone
      } else {
        Logger().warning(
          "Warning: Missing zone for editing ID \(editingZoneID). Initializing with empty values.")
        initialZone = ActivityZone(
          id: nil, name: Self.newZoneDefaultName, color: .salmon, vertices: [], uses: [])
      }
    } else {
      // New zone template was appended to the end of the array
      initialZone =
        zones.last
        ?? ActivityZone(id: nil, name: Self.newZoneDefaultName, color: .salmon, vertices: [], uses: [])
    }
    self._viewModel = State(
      initialValue: ActivityZoneEditViewModel(zone: initialZone)
    )
  }

  var body: some View {
    List {
      visualBoundariesSection()
      metadataSection()
      eventTriggersSection()
      deleteSection()
    }
    .listStyle(.insetGrouped)
    .navigationBarTitleDisplayMode(.inline)
    .navigationTitle(viewModel.isDefaultZone ? "Default Zone" : "Edit: \(viewModel.zone.name)")
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") {
          Task {
            await saveZoneCallback(self.viewModel.zone)
            dismiss()
          }
        }
        .fontWeight(.bold)
        // Enforce that a custom zone must have a name before saving
        .disabled(
          !viewModel.isDefaultZone
            && viewModel.zone.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .alert(
      "Permanently Delete Zone?",
      isPresented: $showDeleteZoneAlert,
      actions: {
        Button("Delete", role: .destructive) {
          Task {
            await deleteZoneCallback(self.viewModel.zone)
            dismiss()
          }
        }
        Button("Cancel", role: .cancel) {}
      },
      message: {
        Text(
          "This action cannot be undone. You will stop receiving selective alerts for '\(viewModel.zone.name)'."
        )
      }
    )
  }

  @ViewBuilder
  private func visualBoundariesSection() -> some View {
    Section {
      ActivityZoneOverlayView(
        zones: viewModel.isDefaultZone ? allZones : [viewModel.zone],
        backgroundImage: backgroundImage,
        zoneMaxSize: zoneMaxSize,
        inverse: viewModel.isDefaultZone
      )
      .listRowInsets(EdgeInsets())
      .listRowBackground(Color.clear)
      .cornerRadius(Constants.mapCornerRadius)
      .shadow(radius: Constants.mapShadowRadius)
      if viewModel.isDefaultZone {
        // Default zone is non-editable and covers the inverse canvas
        Text(
          "The Default Zone triggers events outside of all defined custom zones. Its shape is calculated automatically and cannot be edited."
        )
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.vertical, Constants.mapCaptionPadding)
      } else {
        // Custom zones navigate to the interactive vertex editor
        NavigationLink {
          ActivityZoneShapeEditView(
            zone: $viewModel.zone,
            backgroundImage: backgroundImage,
            zoneMaxSize: zoneMaxSize
          )
        } label: {
          Label("Adjust Boundary Shape", systemImage: "pencil.and.outline")
            .foregroundColor(.accentColor)
        }
      }
    } header: {
      Text("Visual Boundaries")
    }
  }

  @ViewBuilder
  private func metadataSection() -> some View {
    if !viewModel.isDefaultZone {
      Section {
        TextField("Zone Name", text: $viewModel.zone.name)
          .font(.body)
          .submitLabel(.done)
      } header: {
        Text("Name")
      }
      Section {
        Picker("Theme Color", selection: $viewModel.zone.color) {
          ForEach(ZoneColor.settableColors(), id: \.self) { color in
            HStack {
              Circle()
                .fill(color.swiftUIColor)
                .frame(width: Constants.colorIndicatorSize, height: Constants.colorIndicatorSize)
              Text(color.displayName)
            }
            .tag(color)
          }
        }
        .pickerStyle(.menu)
      } header: {
        Text("Appearance")
      }
    }
  }

  @ViewBuilder
  private func eventTriggersSection() -> some View {
    Section {
      ForEach($viewModel.zone.uses, id: \.use) { $zoneUse in
        Toggle(isOn: $zoneUse.isSelected) {
          Label {
            Text(zoneUse.displayName)
              .font(.body)
          } icon: {
            zoneUse.icon
              .foregroundColor(viewModel.zone.color.swiftUIColor)
          }
        }
      }
    } header: {
      Text("Event Triggers")
    } footer: {
      Text(
        "Select which motion events you want this specific zone to detect and alert you about.")
    }
  }

  @ViewBuilder
  private func deleteSection() -> some View {
    if !viewModel.isNewZone && !viewModel.isDefaultZone {
      Section {
        Button(role: .destructive) {
          self.showDeleteZoneAlert = true
        } label: {
          Label("Delete Zone", systemImage: "trash")
            .frame(maxWidth: .infinity)
            .alignmentGuide(.leading) { _ in Constants.deleteButtonAlignmentOffset }
        }
        .buttonStyle(.bordered)
        .tint(.red)
        .listRowBackground(Color.clear)
      }
    }
  }
}
