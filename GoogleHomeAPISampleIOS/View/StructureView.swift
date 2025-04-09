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

import Foundation
import GoogleHomeSDK
import SwiftUI
import OSLog

struct StructureView: View {
  private enum Tab {
    case devices
    case automations
  }

  static let columns = [
    GridItem(.flexible(), alignment: .leading),
    GridItem(.flexible(), alignment: .leading),
  ]

  @EnvironmentObject private var mainViewModel: MainViewModel
  @ObservedObject private var viewModel: StructureViewModel
  @State private var selectedTab: Tab = .devices

  var structureID: String { self.viewModel.structureID }

  init(viewModel: StructureViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    if let structure = self.mainViewModel.structure(structureID: self.structureID) {
      actualStructureView(structure: structure)
    } else {
      Text("Structure not found.")
    }
  }

  private func actualStructureView(structure: Structure) -> some View {
    TabView(selection: $selectedTab) {
      deviceGrid(structure: structure)
        .tabItem {
          Label("Devices", image: "devices_symbol")
            .font(.title)
        }
        .tag(Tab.devices)
      AutomationsView()
        .environmentObject(AutomationList(structure: structure))
        .padding()
        .tabItem {
          Label("Automations", image: "astrophotography_mode_symbol")
        }
        .tag(Tab.automations)
    }
    .toolbar {
      ToolbarItemGroup(placement: .navigationBarLeading) {
        if self.selectedTab == .devices {
          Menu {
            Button("Add Device to Google Fabric") {
              self.addDevice(structure: structure, add3PFabricFirst: false)
            }
            .disabled(self.viewModel.isCommissioningInProgress)
            Button("Add Device to Google & 3P Fabric") {
              self.addDevice(structure: structure, add3PFabricFirst: true)
            }
            Button("Add Room") { self.viewModel.showRoomNameInput = true }
          } label: {
            Image(systemName: "plus")
          }
        }
      }
    }
    .alert("Enter Room Name", isPresented: self.$viewModel.showRoomNameInput) {
      TextField("Room Name...", text: self.$viewModel.roomNameInput)
      Button("Cancel", role: .cancel) {}
      Button("Create Room") {
        guard !self.viewModel.roomNameInput.isEmpty else {
          return
        }
        let roomName = self.viewModel.roomNameInput
        self.viewModel.roomNameInput = ""
        self.viewModel.addRoom(name: roomName, structure: structure)
      }
    }
    .confirmationDialog("", isPresented: self.$viewModel.isConfirmingRoomDeletion) {
      Button("Delete", role: .destructive) {
        self.viewModel.removeRoom(id: self.viewModel.roomIDToBeDeleted!, structure: structure)
      }
      Button("Cancel", role: .cancel) {}
    }
  }

  private func deviceGrid(structure: Structure) -> some View {
    ScrollView {
      if self.viewModel.hasLoaded && self.viewModel.entries.isEmpty {
        Text("No devices in '\(structure.name)'")
          .font(.caption)
          .padding()
      } else if self.viewModel.hasLoaded {
        LazyVGrid(columns: Self.columns) {
          ForEach(self.viewModel.entries) { entry in
            Section {
              // Devices
              if entry.deviceControls.isEmpty {
                Text("No devices in this room")
                  .font(.caption)
                  .padding(.vertical)
              } else {
                ForEach(entry.deviceControls, id: \.id) { deviceControl in
                  DeviceView(
                    deviceControl: deviceControl,
                    roomID: entry.roomID,
                    structure: structure,
                    structureViewModel: self.viewModel
                  )
                }
              }
            } header: {
              HStack {
                Text(entry.roomName)
                  .foregroundColor(Color("fontColor"))
                  .font(.subheadline)
                Spacer()
                if entry.deviceControls.isEmpty {
                  Button(role: .destructive) {
                    self.viewModel.roomIDToBeDeleted = entry.roomID
                  } label: {
                    Image(systemName: "trash")
                  }
                }
              }
            }

          }
        }
        .padding()
      }
    }
  }

  private func addDevice(structure: Structure, add3PFabricFirst: Bool) {
#if targetEnvironment(simulator)
    Logger().error("Cannot add device on simulator.")
    return
#endif

    if add3PFabricFirst {
      guard #available(iOS 17.6, *) else {
        Logger().error("iOS 17.6+ required to add 3P Fabric.")
        return
      }
    }
    self.viewModel.addMatterDevice(to: structure, add3PFabricFirst: add3PFabricFirst)
  }
}
