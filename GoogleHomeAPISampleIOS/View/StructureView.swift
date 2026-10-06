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

  private enum Constants {
    static let devicesTabTitle = "Devices"
    static let automationsTabTitle = "Automations"
    static let historyTabTitle = "History"
    static let searchTabTitle = "Search"
    static let settingsTabTitle = "Settings"

    static let devicesIconName = "devices_other_symbol"
    static let automationsIconName = "astrophotography_mode_symbol"
    static let historyIconName = "clock.arrow.trianglehead.counterclockwise.rotate.90"
    static let searchIconName = "magnifyingglass"
    static let settingsIconName = "gearshape"
    static let plusIconName = "plus"

    static let discoveringHubsText = "Discovering hubs..."
    static let addDeviceGoogleFabric = "Add Device to Google Fabric"
    static let addDeviceGoogleAnd3PFabric = "Add Device to Google & 3P Fabric"
    static let addRoomButtonTitle = "Add Room"
    static let setupHubButtonTitle = "Setup Hub"
    static let linkCloudAccountButtonTitle = "Link Cloud Account"
    static let syncCloudLinkedDevicesButtonTitle = "Sync Cloud Linked Devices"

    static let enterRoomNameAlertTitle = "Enter Room Name"
    static let roomNamePlaceholder = "Room Name..."
    static let cancelButtonTitle = "Cancel"
    static let createRoomButtonTitle = "Create Room"
    static let enterAuthCodeAlertTitle = "Enter Authorization Code"
    static let authCodePlaceholder = "Authorization Code"
    static let linkButtonTitle = "Link"

    static let loadingAutomationsText = "Loading Automations..."
    static let noDevicesInRoomText = "No devices in this room"
    static func noDevicesInStructureText(name: String) -> String {
      "No devices in '\(name)'"
    }
    static let structureNotFoundText = "Structure not found."
    static let homeObjectMissingText = "Home object is missing. Please try again later."
    static let fontColorName = "fontColor"
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
              CameraOOBEView<GoogleCameraDeviceType>(home: self.viewModel.home, device: device)
            }
          } else if device.types.contains(GoogleDoorbellDeviceType.self) {
            NavigationStack {
              CameraOOBEView<GoogleDoorbellDeviceType>(home: self.viewModel.home, device: device)
            }
          } else {
            OtaUpdateScreenView(home: self.viewModel.home, device: device)
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
      Text(Constants.structureNotFoundText)
    }
  }

  private func actualStructureView(structure: Structure) -> some View {
    ZStack {
      TabView(selection: $selectedTab) {
        deviceGrid(structure: structure)
          .tabItem {
            Label(Constants.devicesTabTitle, image: Constants.devicesIconName)
              .font(.title)
          }
          .tag(Tab.devices)
        automationsTabContent(structure: structure)
          .tabItem {
            Label(Constants.automationsTabTitle, image: Constants.automationsIconName)
          }
          .tag(Tab.automations)
        HistoryView(home: self.viewModel.home, structureID: self.structureID)
          .id(self.structureID)
          .tabItem {
            Label(Constants.historyTabTitle, systemImage: Constants.historyIconName)
              .font(.title)
          }
          .tag(Tab.history)
        SearchableHomeView(structure: structure, home: self.viewModel.home)
          .id(structure.id)
          .tabItem {
            Label(Constants.searchTabTitle, systemImage: Constants.searchIconName)
          }
          .tag(Tab.search)
        SettingsView(structure: structure)
          .environmentObject(viewModel)
          .tabItem {
            Label(Constants.settingsTabTitle, systemImage: Constants.settingsIconName)
              // make the icon un-filled
              .environment(\.symbolVariants, .none)
          }
          .tag(Tab.settings)
      }
      if self.viewModel.isDiscoveringHubs {
        Color.black.opacity(0.4)
          .ignoresSafeArea()
        ProgressView(Constants.discoveringHubsText)
          .progressViewStyle(CircularProgressViewStyle())
          .foregroundColor(.white)
      }
    }
    .toolbar {
      ToolbarItemGroup(placement: .navigationBarLeading) {
        if self.selectedTab == .devices {
          Menu {
            Button(Constants.addDeviceGoogleFabric) {
              self.scannerAdd3PFabricFirst = false
              self.isShowingCodeScanner = true
            }
            Button(Constants.addDeviceGoogleAnd3PFabric) {
              self.scannerAdd3PFabricFirst = true
              self.isShowingCodeScanner = true
            }
            Button(Constants.addRoomButtonTitle) { self.viewModel.showRoomNameInput = true }
            Button(Constants.setupHubButtonTitle) {
              Task {
                await self.viewModel.discoverAvailableHubs()
              }
            }
            Button(Constants.linkCloudAccountButtonTitle) {
              self.authorizationCodeInput = ""
              self.showAuthorizationCodeInput = true
            }
            Button(Constants.syncCloudLinkedDevicesButtonTitle) {
              self.syncCloudLinkedDevices()
            }
          } label: {
            Image(systemName: Constants.plusIconName)
          }
        }
      }
    }
    .alert(Constants.enterRoomNameAlertTitle, isPresented: self.$viewModel.showRoomNameInput) {
      TextField(Constants.roomNamePlaceholder, text: self.$viewModel.roomNameInput)
      Button(Constants.cancelButtonTitle, role: .cancel) {}
      Button(Constants.createRoomButtonTitle) {
        guard !self.viewModel.roomNameInput.isEmpty else {
          return
        }
        let roomName = self.viewModel.roomNameInput
        self.viewModel.roomNameInput = ""
        self.addRoom(name: roomName, structure: structure)
      }
    }
    .errorAlert(isPresented: self.$viewModel.showNoHubFoundDialog, error: .noHubFound)
    .alert(Constants.enterAuthCodeAlertTitle, isPresented: self.$showAuthorizationCodeInput) {
      TextField(Constants.authCodePlaceholder, text: self.$authorizationCodeInput)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
      Button(Constants.cancelButtonTitle, role: .cancel) {}
      Button(Constants.linkButtonTitle) {
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
        Text(Constants.loadingAutomationsText)
        ProgressView()
      }
    }
  }

  private func deviceGrid(structure: Structure) -> some View {
    ScrollView {
      if self.viewModel.hasLoaded && self.viewModel.entries.isEmpty {
        Text(Constants.noDevicesInStructureText(name: structure.name))
          .font(.caption)
          .padding()
      } else if self.viewModel.hasLoaded {
        LazyVGrid(columns: Self.columns) {
          ForEach(self.viewModel.entries) { entry in
            Section {
              // Devices
              if entry.deviceControls.isEmpty {
                Text(Constants.noDevicesInRoomText)
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
                      Text(Constants.homeObjectMissingText)
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
                  .foregroundColor(Color(Constants.fontColorName))
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
    #else
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
        self.handlePostCommissioning(devices: devices)
      } catch {
        Logger().error("Failed to add Matter device: \(error)")
      }
    }
    #endif
  }

  /// Handles post-commissioning workflow (Matter OTA update check and OOBE).
  ///
  /// - A single camera / doorbell opens `CameraOOBEView` (OTA -> Settings -> Done).
  /// - Any other Matter device opens `OtaUpdateScreenView`, which waits for the OTA trait
  ///   to arrive.
  /// - If no devices are found, an error alert is shown.
  ///
  /// - Parameter devices: The devices that were just commissioned.
  private func handlePostCommissioning(devices: Set<HomeDevice>) {
    guard let primaryDevice = devices.first else {
      Logger().warning("No device returned after commissioning.")
      self.sampleError = .noDeviceFoundAfterCommissioning
      self.isShowingErrorAlert = true
      return
    }

    // Match on "exactly one camera / doorbell" rather than "exactly one device", so extra
    // endpoints returned by commissioning do not silently skip the camera OOBE.
    let cameraDevices = devices.filter {
      $0.types.contains(GoogleCameraDeviceType.self) || $0.types.contains(GoogleDoorbellDeviceType.self)
    }
    if cameraDevices.count == 1, let cameraDevice = cameraDevices.first {
      Logger().info("Post-commissioning selected camera device '\(cameraDevice.id)' (\(cameraDevice.name))")
      self.oobeDevice = cameraDevice
      return
    }
    let targetDevice = devices.first(where: { $0.types.contains(OtaRequestorDeviceType.self) })
      ?? devices.first(where: { $0.types.contains(RootNodeDeviceType.self) })
      ?? primaryDevice

    Logger().info("Post-commissioning selected target device '\(targetDevice.id)' (\(targetDevice.name))")

    if targetDevice.isMatterDevice {
      self.oobeDevice = targetDevice
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
