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
import SwiftUI

/// A view of settings.
struct SettingsView: View {
  @EnvironmentObject private var structureViewModel: StructureViewModel
  private var structure: Structure

  init(
    structure: Structure
  ) {
    self.structure = structure
  }

  var body: some View {
    // The main container for the entire screen.
    VStack(alignment: .leading, spacing: 20) {
      // Title
      Text("Settings")
        .font(.title)
        .fontWeight(.bold)
      Divider()
        .padding(.bottom, 10)
      // Section for the user's existing rooms.
      Section {
        Text("Rooms")
          .font(.headline)
        ScrollView {
          LazyVStack {
            ForEach(structureViewModel.entries) { entry in
              NavigationLink(
                destination: RoomSettingsView(
                  entry: entry,
                  structure: structure
                )
              ) {
                RoomRow(
                  roomName: entry.roomName,
                  deviceCount: entry.deviceControls.count
                )
              }
            }
          }
        }
      }
      Spacer()
    }
    .padding()
  }

  /// A reusable view component for a single row in the room list.
  struct RoomRow: View {
    let roomName: String
    let deviceCount: Int

    var body: some View {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text(roomName)
            .font(.body)
            .foregroundColor(.black)
          Text("\(deviceCount) \(deviceCount == 1 ? "device" : "devices")")
            .font(.subheadline)
            .foregroundColor(.gray)
        }
        Spacer()
      }
      .padding(.vertical, 8)
      .padding(.horizontal, 16)
    }
  }
}
