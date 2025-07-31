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

import GoogleHomeSDK
import OSLog
import SwiftUI

/// A view of settings.
struct RoomSettingsView: View {
  @EnvironmentObject var structureViewModel: StructureViewModel
  @State private var showDeleteConfirmation = false
  private var entry: StructureViewModel.StructureEntry
  private var structure: Structure
  @Environment(\.dismiss) var dismiss

  init(
    entry: StructureViewModel.StructureEntry,
    structure: Structure
  ) {
    self.entry = entry
    self.structure = structure
  }

  var body: some View {
    // The main container for the entire screen.
    VStack(alignment: .leading, spacing: 20) {
      // Title
      Text("Room settings")
        .font(.title)
        .fontWeight(.bold)
      Divider()
        .padding(.bottom, 10)
      // Section for the user's existing rooms.
      Text("General")
        .font(.headline)
      NavigationLink(
        destination: RenameView(
          viewModel: RenameViewModel(
            renameType: .Room,
            name: self.entry.roomName,
            setName: self.entry.room.setName
          )
        )
      ) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Name")
            .font(.body)
            .foregroundColor(.black)
          Text(entry.roomName)
            .font(.subheadline)
            .foregroundColor(.gray)
        }
      }

      Text("Device settings")
        .font(.headline)
      ScrollView {
        LazyVStack {
          ForEach(entry.deviceControls) { deviceControl in
            DeviceRow(
              deviceName: deviceControl.device.name,
              deviceTypeName: deviceControl.tileInfo.typeName
            )
          }
        }
      }

      // Button to delete room
      Button(action: {
        showDeleteConfirmation = true
      }) {
        Text("Delete room")
          .font(.body)
          .foregroundColor(Color.red)
      }
      .padding(.vertical, 16)
      .alert(isPresented: $showDeleteConfirmation) {
        Alert(
          title: Text("Remove this room"),
          message: Text(
            "Devices will be removed from this room and the room will be deleted."
          ),
          primaryButton: .destructive(Text("Remove")) {
            self.deleteRoom()
          },
          secondaryButton: .cancel(Text("Cancel"))
        )
      }

      Spacer()
    }
    .padding()
  }

  /// A reusable view component for a single row in the room list.
  struct DeviceRow: View {
    let deviceName: String
    let deviceTypeName: String

    var body: some View {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text(deviceName)
            .font(.body)
            .foregroundColor(.black)
          Text(deviceTypeName)
            .font(.subheadline)
            .foregroundColor(.gray)
        }
        Spacer()
      }
      .padding(.vertical, 8)
      .padding(.horizontal, 16)
    }
  }

  /// Delete current room.
  private func deleteRoom() {
    Task {
      do {
        _ = try await self.structure.deleteRoom(self.entry.room)
        self.dismiss()
      } catch {
        Logger().error("Failed to remove room: \(error)")
      }
    }
  }

}
