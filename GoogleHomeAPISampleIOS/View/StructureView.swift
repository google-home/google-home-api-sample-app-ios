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
import GoogleHomeTypes
import OSLog
import SwiftUI

struct StructureView: View {
  private enum Tab {
    case devices
    case automations
    case history
    case search
    case settings
  }

  static let columns = [
    GridItem(.flexible(), alignment: .leading)
  ]

  @EnvironmentObject private var mainViewModel: MainViewModel
  @ObservedObject private var viewModel: StructureViewModel
  @State private var selectedTab: Tab = .devices
  @State private var oobeDevice: HomeDevice?
  @State private var isShowingCodeScanner: Bool = false
  @State private var scannerAdd3PFabricFirst: Bool = false
  @State private var automationList: AutomationList? = nil
  @State private var authorizationCodeInput: String = ""
  @State private var showAuthorizationCodeInput: Bool = false
  @State private var sampleError: HomeSampleError?
  @State private var isShowingErrorAlert = false

  var structureID: String { self.viewModel.structureID }

  init(viewModel: StructureViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    if let structure = self.mainViewModel.structure(
      structureID: self.structureID
    ) {
      actualStructureView(structure: structure)
        .onChange(of: structure.id) {
          self.automationList = nil
        }
        .onChange(of: selectedTab) { _, selectedTab in
          guard selectedTab == .automations else { return }

          // Initialize the automation list if it hasn't been already.
          if self.automationList == nil || self.automationList?.structure.id != structure.id {
            self.automationList = AutomationList(structure: structure)
          } else {
            Task {
              do {
                try await self.automationList?.refresh()
              } catch {
                Logger().error("Failed to refresh automations: \(error)")
              }
            }
          }
        }
        .sheet(item: $oobeDevice) { device in
          if device.types.contains(GoogleCameraDeviceType.self) {
            NavigationStack {
              CameraOOBEView<GoogleCameraDeviceType>(
                home: self.viewModel.home, device: device)
            }
          } else if device.types.contains(GoogleDoorbellDeviceType.self) {
            NavigationStack {
              CameraOOBEView<GoogleDoorbellDeviceType>(
                home: self.viewModel.home, device: device)
            }
          }
        }
        .sheet(isPresented: self.$isShowingCodeScanner) {
          CodeScannerView(isPresented: self.$isShowingCodeScanner) { payload in
            self.addDevice(
              structure: structure,
              add3PFabricFirst: self.scannerAdd3PFabricFirst,
              setupPayload: payload
            )
          }
        }
    } else {
      Text("Structure not found.")
    }
  }

  private func actualStructureView(structure: Structure) -> some View {
    ZStack {
      TabView(selection: $selectedTab) {
        deviceGrid(structure: structure)
          .tabItem {
            Label("Devices", image: "devices_other_symbol")
              .font(.title)
          }
          .tag(Tab.devices)
        automationsTabContent(structure: structure)
          .tabItem {
            Label("Automations", image: "astrophotography_mode_symbol")
          }
          .tag(Tab.automations)
        HistoryView(home: self.viewModel.home, structureID: self.structureID)
          .id(self.structureID)
          .tabItem {
            Label("History", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
              .font(.title)
          }
          .tag(Tab.history)
        SearchableHomeView(structure: structure)
          .id(structure.id)
          .tabItem {
            Label("Search", systemImage: "magnifyingglass")
          }
          .tag(Tab.search)
        SettingsView(structure: structure)
          .environmentObject(viewModel)
          .tabItem {
            Label("Settings", systemImage: "gearshape")
              // make the icon un-filled
              .environment(\.symbolVariants, .none)
          }
          .tag(Tab.settings)
      }
      if self.viewModel.isDiscoveringHubs {
        Color.black.opacity(0.4)
          .ignoresSafeArea()
        ProgressView("Discovering hubs...")
          .progressViewStyle(CircularProgressViewStyle())
          .foregroundColor(.white)
      }
    }
    .toolbar {
      ToolbarItemGroup(placement: .navigationBarLeading) {
        if self.selectedTab == .devices {
          Menu {
            Button("Add Device to Google Fabric") {
              self.scannerAdd3PFabricFirst = false
              self.isShowingCodeScanner = true
            }
            Button("Add Device to Google & 3P Fabric") {
              self.scannerAdd3PFabricFirst = true
              self.isShowingCodeScanner = true
            }
            Button("Add Room") { self.viewModel.showRoomNameInput = true }
            Button("Setup Hub") {
              Task {
                await self.viewModel.discoverAvailableHubs()
              }
            }
            Button("Link Cloud Account") {
              self.authorizationCodeInput = ""
              self.showAuthorizationCodeInput = true
            }
            Button("Sync Cloud Linked Devices") {
              self.syncCloudLinkedDevices()
            }
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
    .errorAlert(isPresented: self.$viewModel.showNoHubFoundDialog, error: .noHubFound)
    .alert("Enter Authorization Code", isPresented: self.$showAuthorizationCodeInput) {
      TextField("Authorization Code", text: self.$authorizationCodeInput)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
      Button("Cancel", role: .cancel) {}
      Button("Link") {
        guard !self.authorizationCodeInput.isEmpty else { return }
        self.linkCloudAccount(
          structure: structure, authorizationCode: self.authorizationCodeInput)
      }
    }
    .errorAlert(isPresented: self.$isShowingErrorAlert, error: self.sampleError)
  }

  @ViewBuilder
  private func automationsTabContent(structure: Structure) -> some View {
    if let automationList = self.automationList {
      AutomationsView()
        .environmentObject(mainViewModel)
        .environmentObject(automationList)
        .padding()
    } else {
      // Shown initially until the automations tab is selected for the first time
      // and the viewModel.automationList is created.
      VStack {
        Text("Loading Automations...")
        ProgressView()
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
                  let uniqueID = "\(deviceControl.id)-\(String(describing: type(of: deviceControl)))"
                  NavigationLink(destination: {
                    if let home = self.mainViewModel.home {
                      switch deviceControl {
                      case is CameraControl:
                        CameraDetailView<GoogleCameraDeviceType>(
                          home: home, deviceControl: deviceControl)
                      case is DoorbellControl:
                        CameraDetailView<GoogleDoorbellDeviceType>(
                          home: home, deviceControl: deviceControl)
                      default:
                        DeviceDetailView(
                          deviceControl: deviceControl,
                          structure: structure,
                          home: home,
                          deviceID: deviceControl.id,
                          structureViewModel: self.viewModel,
                          entry: entry
                        )
                      }
                    } else {
                      Text("Home object is missing. Please try again later.")
                    }
                  }) {
                    DeviceRow(
                      deviceControl: deviceControl
                    )
                  }
                  .id(uniqueID)
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

  private func addDevice(
    structure: Structure, add3PFabricFirst: Bool, setupPayload: String? = nil
  ) {
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
    Task {
      do {
        let devices = try await self.viewModel.addMatterDevice(
          to: structure, add3PFabricFirst: add3PFabricFirst, setupPayload: setupPayload)
        self.showCameraOOBEIfNeeded(devices: devices)
      } catch {
        Logger().error("Failed to add Matter device: \(error)")
      }
    }
  }

  /// Shows the Camera OOBE flow if the device is a camera / doorbell.
  ///
  /// - Parameters:
  ///   - devices: The devices that were just commissioned.
  private func showCameraOOBEIfNeeded(devices: Set<HomeDevice>) {
    guard devices.count == 1, let device = devices.first else {
      Logger().debug("Camera OOBE is only available when a single device is commissioned.")
      return
    }
    if device.types.contains(GoogleCameraDeviceType.self) ||
       device.types.contains(GoogleDoorbellDeviceType.self) {
        self.oobeDevice = device
    }
  }

  /// Links the cloud account for the structure with the provided authorization code.
  ///
  /// - Parameters:
  ///   - structure: The structure to link the cloud account to.
  ///   - authorizationCode: The authorization code obtained from the cloud provider.
  private func linkCloudAccount(structure: Structure, authorizationCode: String) {
    Task {
      do {
        try await structure.linkCloudAccount(authorization: authorizationCode)
        Logger().info("Cloud account linked successfully.")
      } catch {
        Logger().error("Failed to link cloud account: \(error)")
        self.sampleError = .unableToLinkCloudAccount(error: error.localizedDescription)
        self.isShowingErrorAlert = true
      }
    }
  }

  /// Syncs cloud linked devices for the current home.
  private func syncCloudLinkedDevices() {
    Task {
      do {
        try await self.mainViewModel.home?.syncLinkedDevices()
        Logger().info("Cloud linked devices synced successfully.")
      } catch {
        Logger().error("Failed to sync cloud linked devices: \(error)")
        self.sampleError = .unableToSyncLinkedDevices(error: error.localizedDescription)
        self.isShowingErrorAlert = true
      }
    }
  }
}
