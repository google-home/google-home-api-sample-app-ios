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

import Combine
import Foundation
import GoogleHomeSDK
import OSLog
import SwiftUI

struct DeviceDetailView: View {
  @ObservedObject private var deviceControl: DeviceControl
  @ObservedObject private var structureViewModel: StructureViewModel
  @StateObject private var viewModel: DeviceDetailViewModel
  private var structure: Structure
  private var entry: StructureViewModel.StructureEntry

  @State private var showingPinEntry = false
  @State private var pinCode = ""
  @State private var isShowingDecommissionConfirmation = false
  @Environment(\.dismiss) var dismiss

  init(
    deviceControl: DeviceControl,
    structure: Structure,
    home: Home,
    deviceID: String,
    structureViewModel: StructureViewModel,
    entry: StructureViewModel.StructureEntry
  ) {
    let viewModel = DeviceDetailViewModel(
      home: home, device: deviceControl.device)

    self.deviceControl = deviceControl
    self.structure = structure
    self._viewModel = StateObject(
      wrappedValue: viewModel)
    self.structureViewModel = structureViewModel
    self.entry = entry
  }

  var body: some View {
    // The main container for the entire screen.
    ScrollView {
      VStack(alignment: .leading, spacing: .md) {

        self.titleSection

          VStack(alignment: .leading, spacing: .xl) {
          Text("General")
            .font(.headline)

          self.controlSection
          self.attributeSection
          self.locationSection
        }
        .padding(.top)

        Section("Decommission") {
          self.decommissionSection
        }

        // Pushes all the content to the top of the screen.
        Spacer()
      }
      // Adds padding around the entire screen content.
      .padding()
      .alert("Enter PIN", isPresented: $showingPinEntry) {
        SecureField("PIN Code", text: $pinCode)
          .keyboardType(.numberPad)
        Button("Submit") {
          self.deviceControl.setPINCode(self.pinCode)
          self.deviceControl.toggleControl?.action()
          self.pinCode = ""
        }
        Button("Cancel", role: .cancel) {
          self.pinCode = ""
        }
      } message: {
        Text("PIN is required to operate this lock.")
      }
      .confirmationDialog(
        "Are you sure you want to decommission this device? This action cannot be undone.",
        isPresented: self.$isShowingDecommissionConfirmation,
        titleVisibility: .visible
      ) {
        Button("Decommission", role: .destructive) {
          self.decommissionDevice()
        }
        Button("Cancel", role: .cancel) {}
      }
    }
  }

  /// Display device name and entry of name editing.
  @ViewBuilder
  var titleSection: some View {
    HStack(alignment: .center) {
      // Device name
      Text(self.deviceControl.tileInfo.title)
        .font(.title)
        .fontWeight(.bold)
      Spacer()
      // Edit button
      NavigationLink(
        destination: RenameView(
          viewModel: RenameViewModel(
            renameType: .Device,
            name: self.deviceControl.device.name,
            setName: self.deviceControl.device.setName
          )
        )
      ) {
        Image(systemName: "pencil.circle.fill")
          .font(.title)
          .foregroundStyle(.gray, Color(.systemGray5))
      }
    }
    .onAppear {
      // Only check the decommission eligibility when user open DeviceDetailView
      viewModel.checkDecommissionEligibility()
    }
    Divider()
          .padding(.bottom, .smd)
  }

  /// Display controls of device.
  @ViewBuilder
  var controlSection: some View {
    // Toggle Control
    if let toggleControl = self.deviceControl.toggleControl {
      Toggle(
        isOn: Binding(
          get: { toggleControl.isOn },
          set: {
            _ in
            if self.deviceControl.requiresPINCode {
              self.showingPinEntry = true
            } else {
              toggleControl.action()
            }
          }
        )
      ) {
          VStack(alignment: .leading, spacing: .xs) {
          Text(toggleControl.label)
            .font(.body)
          Text(toggleControl.description)
            .font(.subheadline)
            .foregroundColor(.gray)
        }
      }
      .disabled(self.deviceControl.tileInfo.isBusy)
      .toggleStyle(SwitchToggleStyle(tint: .blue))
    }

    // Dropdown Control
    if let dropdownControl = deviceControl.dropdownControl {
      DropdownView(dropdownControl: dropdownControl)
        .disabled(self.deviceControl.tileInfo.isBusy)
    }

    // Range Control
    if let rangeControl = deviceControl.rangeControl {
      RangeSlider(rangeControl: rangeControl)
        .disabled(self.deviceControl.tileInfo.isBusy)
    }

    // Range Control 2
    if let rangeControl = deviceControl.rangeControl2 {
      RangeSlider(rangeControl: rangeControl)
        .disabled(self.deviceControl.tileInfo.isBusy)
    }

    // Button Group Control
    if let buttonGroupControl = deviceControl.buttonGroupControl {
      ButtonGroupView(buttonGroupControl: buttonGroupControl)
        .disabled(self.deviceControl.tileInfo.isBusy)
    }
  }

  /// Display attributes' name and value.
  @ViewBuilder
  var attributeSection: some View {
    ForEach(self.deviceControl.tileInfo.attributes, id: \.self) {
      attribute in
      if let (key, value) = attribute.first {
          VStack(alignment: .leading, spacing: .xs) {
          Text(key)
            .font(.body)
          Text(value)
            .font(.subheadline)
            .foregroundColor(.gray)
        }
      }
    }
  }

  /// Display which room the device located and entry of moving to other room.
  @ViewBuilder
  var locationSection: some View {
    NavigationLink(
      destination: RoomsView(
        deviceID: self.deviceControl.device.id,
        structure: self.structure,
        structureViewModel: self.structureViewModel,
        originalRoomID: self.entry.roomID
      )
    ) {
      VStack(alignment: .leading, spacing: .xs) {
        Text("Location")
          .font(.body)
          .foregroundColor(.black)
        Text(self.entry.roomName)
          .font(.subheadline)
          .foregroundColor(.gray)
      }
    }
  }

  /// A view that displays the decommission eligibility of the device.
  ///
  /// This view shows the user whether the device can be decommissioned, and if so, what the
  /// side effects of decommissioning are.
  @ViewBuilder
  private var decommissionSection: some View {
    switch self.viewModel.decommissionEligibility {
    case .ineligible(let reason):
      Text("This device cannot be decommissioned.")
      switch reason {
      case .notAuthorized:
        Text("You are not authorized to decommission this device.")
      case .nonMatterDevice:
        Text("This is not a Matter device.")
      case .bridgedDevice:
        Text(
          "This device is bridged, follow the bridge manufacturer's instructions to remove this device."
        )
      case .other(let message):
        Text("Reason: \(message ?? "Unknown")")
      case .multiSourceDevice:
        Text(
          "The device is connected through multiple sources, to decommission the device, it needs to be disconnected from all non-matter sources."
        )
      @unknown default:
        Text("Unknown reason.")
      }
    case .eligible:
      self.decommissionButton
    case .eligibleWithSideEffects(let sideEffects):
      HStack {
        Image(systemName: "exclamationmark.triangle")
        switch sideEffects {
        case .bridge(let bridgedDeviceIDs):
          VStack(alignment: .leading) {
            Text(
              "This device is a bridge, decommissioning it will also decommission the following bridged devices:"
            )
            ForEach(Array(bridgedDeviceIDs), id: \.self) {
              Text("• \($0)").font(.caption)
            }
          }
        case .multipleAffectedDevices(let affectedDeviceIDs):
          VStack(alignment: .leading) {
            Text(
              "Multiple devices will be decommissioned by decommissioning this device."
            )
            ForEach(Array(affectedDeviceIDs), id: \.self) {
              Text("• \($0)").font(.caption)
            }
          }
        @unknown default:
          Text("Unknown side effects.")
        }
      }
      self.decommissionButton
    @unknown default:
      Text("Unknown decommission eligibility.")
    }
  }

  /// A button that, when tapped, shows a confirmation dialog to decommission the device.
  @ViewBuilder
  private var decommissionButton: some View {
    Button(role: .destructive) {
      self.isShowingDecommissionConfirmation = true
    } label: {
      HStack {
        Spacer()
        Text("Decommission")
        Spacer()
      }
    }
  }

  private func decommissionDevice() {
    Task { @MainActor in
      do {
        let decommissionedDeviceIDs = try await self.viewModel
          .decommissionDevice()
        let message =
          "Devices decommissioned successfully.\n\n"
          + decommissionedDeviceIDs.map { "• \($0)" }.joined(separator: "\n")
        Logger().info("\(message)")
        self.dismiss()
      } catch {
        Logger().error("Failed to decommission device: \(error)")
      }
    }
  }
}

private struct DropdownView: View {
  @ObservedObject var dropdownControl: DropdownControl

  var body: some View {
    VStack(alignment: .leading, spacing: .xs) {
      Text(dropdownControl.label)
        .font(.body)
      Picker(dropdownControl.label, selection: $dropdownControl.selection) {
        ForEach(dropdownControl.options, id: \.self) { option in
          Text(option)
        }
      }
    }
  }
}

private struct RangeSlider: View {
  @ObservedObject var rangeControl: RangeControl
  @State private var sliderValue: Float
  @State private var isEditing = false

  init(rangeControl: RangeControl) {
    self.rangeControl = rangeControl
    _sliderValue = State(initialValue: rangeControl.rangeValue)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: .xs) {
      Text(rangeControl.label)
        .font(.body)
      Slider(
        value: Binding(
          get: { sliderValue },
          set: { if rangeControl.validate(Int16($0)) { sliderValue = $0 } }
        ),
        in: rangeControl.range,
        onEditingChanged: { editing in
          isEditing = editing
          if !editing {
            rangeControl.rangeValue = sliderValue
          }
        }
      )
    }
    .onChange(of: rangeControl.rangeValue) { oldValue, newValue in
      if !isEditing {
        sliderValue = newValue
      }
    }
  }
}

private struct ButtonGroupView: View {
  @ObservedObject var buttonGroupControl: ButtonGroupControl

  var body: some View {
    let displayedButtons = buttonGroupControl.buttons.filter({ $0.isDisplayed })
    let columnCount = 2
    let rowCount = (displayedButtons.count + columnCount - 1) / columnCount
    VStack {
      ForEach(0..<rowCount, id: \.self) { rowIndex in
        HStack {
          ForEach(0..<columnCount, id: \.self) { colIndex in
            if colIndex == 1 {
              Spacer()
            }
            let buttonIndex = rowIndex * 2 + colIndex
            if buttonIndex < displayedButtons.count {
              let button = displayedButtons[buttonIndex]
              Button(action: button.action) {
                Text(button.label)
              } .disabled(button.disabled)
              .buttonStyle(.bordered)
            }
          }
        }
      }
    }
  }
}
