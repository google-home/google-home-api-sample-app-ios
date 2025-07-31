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
import OSLog
import SwiftUI

struct StructureView: View {
  private enum Tab {
    case devices
    case automations
    case settings
  }

  static let columns = [
    GridItem(.flexible(), alignment: .leading)
  ]

  @EnvironmentObject private var mainViewModel: MainViewModel
  @ObservedObject private var viewModel: StructureViewModel
  @State private var selectedTab: Tab = .devices

  var structureID: String { self.viewModel.structureID }

  init(viewModel: StructureViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    if let structure = self.mainViewModel.structure(
      structureID: self.structureID)
    {
      actualStructureView(structure: structure)
    } else {
      Text("Structure not found.")
    }
  }

  private func actualStructureView(structure: Structure) -> some View {
    TabView(selection: $selectedTab) {
      deviceGrid(structure: structure)
        .tabItem {
          Label("Devices", image: "devices_other_symbol")
            .font(.title)
        }
        .tag(Tab.devices)
      AutomationsView()
        .environmentObject(mainViewModel)
        .environmentObject(AutomationList(structure: structure))
        .padding()
        .tabItem {
          Label("Automations", image: "astrophotography_mode_symbol")
        }
        .tag(Tab.automations)
      SettingsView(structure: structure)
        .environmentObject(viewModel)
        .tabItem {
          Label("Settings", systemImage: "gearshape")
            // make the icon un-filled
            .environment(\.symbolVariants, .none)
        }
        .tag(Tab.settings)
    }
    .toolbar {
      ToolbarItemGroup(placement: .navigationBarLeading) {
        if self.selectedTab == .devices {
          Menu {
            Button("Add Device to Google Fabric") {
              self.addDevice(structure: structure, add3PFabricFirst: false)
            }
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
        self.addRoom(name: roomName, structure: structure)
      }
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
                  NavigationLink(destination: {
                    if let home = self.mainViewModel.home {
                      DeviceDetailView(
                        deviceControl: deviceControl,
                        structure: structure,
                        home: home,
                        deviceID: deviceControl.id,
                        structureViewModel: self.viewModel,
                        entry: entry
                      )
                    } else {
                      Text("Home object is missing. Please try again later.")
                    }
                  }) {
                    DeviceRow(
                      deviceControl: deviceControl
                    )
                  }
                }
              }
            } header: {
              HStack {
                Text(entry.roomName)
                  .foregroundColor(Color("fontColor"))
                  .font(.headline)
                Spacer()
              }
            }
          }
        }
        .padding()
      }
    }
  }

  private func addRoom(name: String, structure: Structure) {
    Task {
      do {
        // The view will be updated with the values from the devices publisher.
        _ = try await structure.createRoom(name: name)
      } catch {
        Logger().error("Failed to create room: \(error)")
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
    self.viewModel.addMatterDevice(
      to: structure, add3PFabricFirst: add3PFabricFirst)
  }
}
