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
  @State private var isShowingFamiliarFaces = false
  @State private var showPermissionErrorAlert = false

  private enum Constants {
    static let familiarFaceHeader = "Familiar Face"
    static let consentStatusLabel = "Consent Status: "
    static let consentedValue = "Consented (Enabled)"
    static let notConsentedValue = "Not Consented (Disabled)"
    static let unspecifiedValue = "Unspecified"
    static let unknownValue = "Unknown"
    static let manageFacesButton = "Manage Faces"
    static let revokeConsentButton = "Revoke Consent"
    static let enableFamiliarFaceButton = "Enable Familiar Face Detection"
    static let permissionRequiredAlertTitle = "Permission Required"
    static let permissionRequiredAlertMessage = "Familiar Face Detection consent was not granted."
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
    Section {
      Text(Constants.familiarFaceHeader)
        .font(.headline)
      HStack {
        VStack(alignment: .leading, spacing: .xs) {
          Text(Constants.consentStatusLabel)
            .font(.body)
            .foregroundColor(.primary)
          let consentStr: String = {
            switch structureViewModel.faceLibraryConsentStatus {
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
      if structureViewModel.faceLibraryConsentStatus == .consented {
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
      } else {
        Button(action: {
          Task {
            let granted = await structureViewModel.requestFaceLibraryConsent()
            if !granted {
              showPermissionErrorAlert = true
            }
          }
        }) {
          HStack {
            Text(Constants.enableFamiliarFaceButton)
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
        message: Text(Constants.permissionRequiredAlertMessage),
        dismissButton: .default(Text(Constants.okButton))
      )
    }
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
