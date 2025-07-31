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

/// A view to select room
struct RoomsView: View {
  @ObservedObject private var structureViewModel: StructureViewModel
  @State private var selectedRoomID: String
  private var deviceID: String
  private var structure: Structure

  init(
    deviceID: String,
    structure: Structure,
    structureViewModel: StructureViewModel,
    originalRoomID: String
  ) {
    self.deviceID = deviceID
    self.structure = structure
    self.structureViewModel = structureViewModel
    _selectedRoomID = State(initialValue: originalRoomID)
  }

  var body: some View {
    ZStack(alignment: .bottom) {
      // The main container for the entire screen.
      VStack(alignment: .leading, spacing: 20) {
        // Title
        Text("Room")
          .font(.title)
          .fontWeight(.bold)
        Divider()
          .padding(.bottom, 10)
        // Section for the user's existing rooms.
        Section{
          Text("My rooms")
            .font(.headline)
          ScrollView {
            LazyVStack {
              ForEach(self.structureViewModel.entries) { entry in
                RoomRow(
                  title: entry.roomName,
                  id: entry.roomID,
                  isSelected: selectedRoomID == entry.roomID,
                  action: { selectedRoomID = entry.roomID }
                )
              }
            }
          }
        }
        Spacer()
      }

      // Save button at the bottom of the screen.
      HStack {
        Spacer()
        Button(action: self.moveDeivce) {
          Text("Save")
            .frame(
              width: Dimensions.buttonWidth, height: Dimensions.buttonHeight
            )
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(Dimensions.cornerRadius)
        }
      }
      .padding([.horizontal, .bottom])
    }
    .padding()
  }

  /// Moves the device with the given ID to the room with given ID.
  private func moveDeivce() {
    Task {
      do {
        try await self.structure.move(
          device: self.deviceID, to: self.selectedRoomID)
      } catch {
        Logger().error("Failed to move device: \(error)")
      }
    }
  }

  /// A reusable view component for a single row in the room list.
  struct RoomRow: View {
    let title: String
    let id: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
      Button(action: action) {
        HStack {
          Text(title)
          Spacer()
          // The radio button icon changes based on the selection state.
          Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
            .font(.title2)
            .foregroundColor(.blue)
        }
      }
      .padding(.vertical, 8)
      .padding(.horizontal, 24)
      .buttonStyle(.plain)  // Ensures the row looks like text, not a default styled button.
      .foregroundColor(.primary)
    }
  }
}
