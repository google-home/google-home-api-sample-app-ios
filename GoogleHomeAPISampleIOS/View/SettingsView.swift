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
import GoogleHomeTypes
import SwiftUI

/// A view of settings.
struct SettingsView: View {
  @EnvironmentObject private var structureViewModel: StructureViewModel
  @EnvironmentObject private var mainViewModel: MainViewModel
  private var structure: Structure
  @State private var isShowingFamiliarFaces = false
  @State private var isShowingAreaPresence = false
  @State private var showPermissionErrorAlert = false
  @State private var permissionAlertMessage = Constants.permissionRequiredAlertMessage

  private enum Constants {
    static let familiarFaceHeader = "Familiar Face"
    static let presenceHeader = "Presence"
    static let consentStatusLabel = "Consent Status: "
    static let consentedValue = "Consented (Enabled)"
    static let notConsentedValue = "Not Consented (Disabled)"
    static let unspecifiedValue = "Unspecified"
    static let unknownValue = "Unknown"
    static let fetchingValue = "Loading..."
    static let manageFacesButton = "Manage Faces"
    static let manageAreaPresenceButton = "Manage Area Presence"
    static let revokeConsentButton = "Revoke Consent"
    static let enableFamiliarFaceButton = "Enable Familiar Face Detection"
    static let enablePresenceSensingButton = "Enable Presence Sensing"
    static let permissionRequiredAlertTitle = "Permission Required"
    static let permissionRequiredAlertMessage = "Familiar Face Detection consent was not granted."
    static let presencePermissionRequiredAlertMessage = "Presence Sensing consent was not granted."
    static let okButton = "OK"
    // System Icons
    static let chevronRightIcon = "chevron.right"
  }

  init(
    structure: Structure
  ) {
    self.structure = structure
  }

  var body: some View {
    VStack(alignment: .leading, spacing: .md) {
      titleSection
      roomsSection
      Divider()
        .padding(.vertical, .sm)
      familiarFaceSection
      Divider()
        .padding(.vertical, .sm)
      presenceSection
      Spacer()
    }
    .padding()
    .onAppear {
      Task {
        await structureViewModel.refreshFaceLibraryConsentStatus()
      }
    }
  }

  @ViewBuilder
  private var titleSection: some View {
    Text("Settings")
      .font(.title)
      .fontWeight(.bold)
    Divider()
      .padding(.bottom, .smd)
  }

  @ViewBuilder
  private var roomsSection: some View {
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
  }

  @ViewBuilder
  private var familiarFaceSection: some View {
    featureConsentSection(
      header: Constants.familiarFaceHeader,
      status: structureViewModel.faceLibraryConsentStatus,
      isFetching: structureViewModel.isFetchingConsentStatus,
      enableButtonTitle: Constants.enableFamiliarFaceButton,
      consentedActions: {
        Button(action: {
          isShowingFamiliarFaces = true
        }) {
          HStack {
            Text(Constants.manageFacesButton)
              .font(.body)
              .foregroundColor(.primary)
            Spacer()
            Image(systemName: Constants.chevronRightIcon)
              .foregroundColor(.secondary)
          }
        }
        .padding(.vertical, .sm)
        .padding(.horizontal, .md)
        Button(action: {
          Task {
            await structureViewModel.presentFaceLibraryConsentFlow()
          }
        }) {
          HStack {
            Text(Constants.revokeConsentButton)
              .font(.body)
              .foregroundColor(.red)
          }
        }
        .padding(.vertical, .sm)
        .padding(.horizontal, .md)
      },
      onEnable: {
        Task {
          let granted = await structureViewModel.requestFaceLibraryConsent()
          if !granted {
            permissionAlertMessage = Constants.permissionRequiredAlertMessage
            showPermissionErrorAlert = true
          }
        }
      }
    )
    .background(
      NavigationLink(
        destination: FamiliarFacesView(home: structureViewModel.home, structure: structure),
        isActive: $isShowingFamiliarFaces
      ) {
        EmptyView()
      }
      .hidden()
    )
    .alert(isPresented: $showPermissionErrorAlert) {
      Alert(
        title: Text(Constants.permissionRequiredAlertTitle),
        message: Text(permissionAlertMessage),
        dismissButton: .default(Text(Constants.okButton))
      )
    }
  }

  /// Renders the presence sensing configuration section.
  ///
  /// - Note: Demonstrates feature status display alongside conditional consent grant and revocation controls.
  @ViewBuilder
  private var presenceSection: some View {
    featureConsentSection(
      header: Constants.presenceHeader,
      status: structureViewModel.presenceSensingConsentStatus,
      isFetching: structureViewModel.isFetchingPresenceConsentStatus,
      enableButtonTitle: Constants.enablePresenceSensingButton,
      consentedActions: {
        Button(action: {
          isShowingAreaPresence = true
        }) {
          HStack {
            Text(Constants.manageAreaPresenceButton)
              .font(.body)
              .foregroundColor(.primary)
            Spacer()
            if let presenceState = mainViewModel.areaPresenceState {
              Text(presenceState.text ?? "")
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
            Image(systemName: Constants.chevronRightIcon)
              .foregroundColor(.secondary)
          }
        }
        .padding(.vertical, .sm)
        .padding(.horizontal, .md)
        Button(action: {
          Task {
            await structureViewModel.presentPresenceSensingConsentFlow()
          }
        }) {
          HStack {
            Text(Constants.revokeConsentButton)
              .font(.body)
              .foregroundColor(.red)
          }
        }
        .padding(.vertical, .sm)
        .padding(.horizontal, .md)
      },
      onEnable: {
        Task {
          let granted = await structureViewModel.requestPresenceSensingConsent()
          if !granted {
            permissionAlertMessage = Constants.presencePermissionRequiredAlertMessage
            showPermissionErrorAlert = true
          }
        }
      }
    )
    .background(
      NavigationLink(
        destination: AreaPresenceStateView(
          viewModel: AreaPresenceStateViewModel(currentStructure: structure)
        ),
        isActive: $isShowingAreaPresence
      ) {
        EmptyView()
      }
      .hidden()
    )
  }

  @ViewBuilder
  private func featureConsentSection<Actions: View>(
    header: String,
    status: StructureScopedPermissionsController.ConsentStatus,
    isFetching: Bool,
    enableButtonTitle: String,
    @ViewBuilder consentedActions: () -> Actions,
    onEnable: @escaping () -> Void
  ) -> some View {
    Section {
      Text(header)
        .font(.headline)
      consentStatusRow(status: status, isFetching: isFetching)
      if !isFetching {
        if status == .consented {
          consentedActions()
        } else {
          Button(action: onEnable) {
            HStack {
              Text(enableButtonTitle)
                .font(.body)
                .foregroundColor(.blue)
              Spacer()
              Image(systemName: Constants.chevronRightIcon)
                .foregroundColor(.blue)
            }
          }
          .padding(.vertical, .sm)
          .padding(.horizontal, .md)
        }
      }
    }
  }

  @ViewBuilder
  private func consentStatusRow(
    status: StructureScopedPermissionsController.ConsentStatus,
    isFetching: Bool
  ) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: .xs) {
        Text(Constants.consentStatusLabel)
          .font(.body)
          .foregroundColor(.primary)
        let consentStr: String = {
          if isFetching {
            return Constants.fetchingValue
          }
          switch status {
          case .consented:
            return Constants.consentedValue
          case .notConsented:
            return Constants.notConsentedValue
          case .unspecified:
            return Constants.unspecifiedValue
          @unknown default:
            return Constants.unknownValue
          }
        }()
        Text("\(consentStr)")
          .font(.subheadline)
          .foregroundColor(.secondary)
      }
      Spacer()
    }
    .padding(.vertical, .sm)
    .padding(.horizontal, .md)
  }

  /// A reusable view component for a single row in the room list.
  struct RoomRow: View {
    let roomName: String
    let deviceCount: Int
    var body: some View {
      HStack {
          VStack(alignment: .leading, spacing: .xs) {
          Text(roomName)
            .font(.body)
            .foregroundColor(.black)
          Text("\(deviceCount) \(deviceCount == 1 ? "device" : "devices")")
            .font(.subheadline)
            .foregroundColor(.gray)
        }
        Spacer()
      }
      .padding(.vertical, .sm)
      .padding(.horizontal, .md)
    }
  }
}
