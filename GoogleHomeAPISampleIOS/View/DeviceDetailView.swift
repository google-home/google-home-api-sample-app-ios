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
  private enum Constants {
    static let generalSectionHeader = "General"
    static let decommissionSectionHeader = "Decommission"
    static let enterPinTitle = "Enter PIN"
    static let pinCodePlaceholder = "PIN Code"
    static let submitButtonTitle = "Submit"
    static let cancelButtonTitle = "Cancel"
    static let pinRequiredMessage = "PIN is required to operate this lock."
    static let decommissionConfirmationMessage =
      "Are you sure you want to decommission this device? This action cannot be undone."
    static let decommissionButtonTitle = "Decommission"
    static let locationLabel = "Location"
    static let softwareUpdateTitle = "Software Update"
    static let currentVersionLabel = "Current Version:"
    static let statusLabel = "Status:"
    static let versionNotAvailable = "N/A"
    static let cannotDecommissionText = "This device cannot be decommissioned."
    static let notAuthorizedText = "You are not authorized to decommission this device."
    static let nonMatterDeviceText = "This is not a Matter device."
    static let bridgedDeviceText =
      "This device is bridged, follow the bridge manufacturer's instructions to remove this device."
    static let multiSourceDeviceText =
      "The device is connected through multiple sources, to decommission the device, it needs to be disconnected from all non-matter sources."
    static let bridgeSideEffectsText =
      "This device is a bridge, decommissioning it will also decommission the following bridged devices:"
    static let multipleSideEffectsText =
      "Multiple devices will be decommissioned by decommissioning this device."
    static let unknownText = "Unknown"
    static let unknownReasonText = "Unknown reason."
    static let unknownSideEffectsText = "Unknown side effects."
    static let unknownEligibilityText = "Unknown decommission eligibility."
    static let reasonPrefix = "Reason: "

    static let editIcon = "pencil.circle.fill"
    static let warningIcon = "exclamationmark.triangle"

    static let progressPercentDivisor = 100.0
    static let progressBarTopPadding: CGFloat = 2

    static func versionDisplay(_ version: String) -> String {
      "v\(version)"
    }
  }

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
    self.deviceControl = deviceControl
    self.structure = structure
    self._viewModel = StateObject(
      wrappedValue: DeviceDetailViewModel(home: home, device: deviceControl.device))
    self.structureViewModel = structureViewModel
    self.entry = entry
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: .md) {
        self.titleSection
        VStack(alignment: .leading, spacing: .xl) {
          Text(Constants.generalSectionHeader)
            .font(.headline)
          self.controlSection
          self.attributeSection
          self.locationSection
          if self.viewModel.hasOtaSupport {
            self.otaSection
          }
        }
        .padding(.top)
        Section(Constants.decommissionSectionHeader) {
          self.decommissionSection
        }
        Spacer()
      }
      .padding()
      .alert(Constants.enterPinTitle, isPresented: $showingPinEntry) {
        SecureField(Constants.pinCodePlaceholder, text: $pinCode)
          .keyboardType(.numberPad)
        Button(Constants.submitButtonTitle) {
          self.deviceControl.setPINCode(self.pinCode)
          self.deviceControl.toggleControl?.action()
          self.pinCode = ""
        }
        Button(Constants.cancelButtonTitle, role: .cancel) {
          self.pinCode = ""
        }
      } message: {
        Text(Constants.pinRequiredMessage)
      }
      .confirmationDialog(
        Constants.decommissionConfirmationMessage,
        isPresented: self.$isShowingDecommissionConfirmation,
        titleVisibility: .visible
      ) {
        Button(Constants.decommissionButtonTitle, role: .destructive) {
          self.decommissionDevice()
        }
        Button(Constants.cancelButtonTitle, role: .cancel) {}
      }
    }
  }

  /// Display device name and entry of name editing.
  @ViewBuilder
  var titleSection: some View {
    HStack(alignment: .center) {
      Text(self.deviceControl.tileInfo.title)
        .font(.title)
        .fontWeight(.bold)
      Spacer()
      NavigationLink(
        destination: RenameView(
          viewModel: RenameViewModel(
            renameType: .Device,
            name: self.deviceControl.device.name,
            setName: self.deviceControl.device.setName
          )
        )
      ) {
        Image(systemName: Constants.editIcon)
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
    Group {
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
        .toggleStyle(SwitchToggleStyle(tint: .blue))
      }

      // Dropdown Control
      if let dropdownControl = deviceControl.dropdownControl {
        DropdownView(dropdownControl: dropdownControl)
      }

      // Range Control
      if let rangeControl = deviceControl.rangeControl {
        RangeSlider(rangeControl: rangeControl)
      }

      // Cool Range Control
      if let rangeControl = deviceControl.coolRangeControl {
        RangeSlider(rangeControl: rangeControl)
      }

      // Heat Range Control
      if let rangeControl = deviceControl.heatRangeControl {
        RangeSlider(rangeControl: rangeControl)
      }

      // Button Group Control
      if let buttonGroupControl = deviceControl.buttonGroupControl {
        ButtonGroupView(buttonGroupControl: buttonGroupControl)
      }
    }
    .disabled(self.deviceControl.tileInfo.isBusy)
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
    let currentEntry = self.structureViewModel.entries.first {
      $0.deviceControls.contains {
        $0.device.id == self.deviceControl.device.id
      }
    }

    NavigationLink(
      destination: RoomsView(
        deviceID: self.deviceControl.device.id,
        structure: self.structure,
        structureViewModel: self.structureViewModel,
        originalRoomID: currentEntry?.roomID ?? self.entry.roomID
      )
    ) {
      VStack(alignment: .leading, spacing: .xs) {
        Text(Constants.locationLabel)
          .font(.body)
          .foregroundColor(.black)
        // Display the dynamically found name
        Text(currentEntry?.roomName ?? self.entry.roomName)
          .font(.subheadline)
          .foregroundColor(.gray)
      }
    }
  }

  /// Display software version and OTA update status.
  @ViewBuilder
  var otaSection: some View {
    VStack(alignment: .leading, spacing: .xs) {
      Text(Constants.softwareUpdateTitle)
        .font(.body)

      // 1. Current Version
      HStack {
        Text(Constants.currentVersionLabel)
          .font(.subheadline)
          .foregroundColor(.gray)
        Text(self.viewModel.softwareVersion.map(Constants.versionDisplay) ?? Constants.versionNotAvailable)
          .font(.subheadline)
      }

      // 2. Status & Progress Description
      HStack {
        Text(Constants.statusLabel)
          .font(.subheadline)
          .foregroundColor(.gray)

        let text = self.viewModel.otaUiState.displayStatusText
        switch self.viewModel.otaUiState {
        case .loading, .checking, .upToDate:
          Text(text)
            .font(.subheadline)
            .foregroundColor(.gray)
        case .downloading, .installing:
          Text(text)
            .font(.subheadline)
            .foregroundColor(.blue)
        case .delayed:
          Text(text)
            .font(.subheadline)
            .foregroundColor(.orange)
        case .failed:
          Text(text)
            .font(.subheadline)
            .foregroundColor(.red)
        }
      }

      // 3. Linear Progress Bar during downloading
      if case .downloading(let percent, _) = self.viewModel.otaUiState, let percent {
        ProgressView(value: Double(percent) / Constants.progressPercentDivisor)
          .padding(.top, Constants.progressBarTopPadding)
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
      Text(Constants.cannotDecommissionText)
      switch reason {
      case .notAuthorized:
        Text(Constants.notAuthorizedText)
      case .nonMatterDevice:
        Text(Constants.nonMatterDeviceText)
      case .bridgedDevice:
        Text(Constants.bridgedDeviceText)
      case .other(let message):
        Text("\(Constants.reasonPrefix)\(message ?? Constants.unknownText)")
      case .multiSourceDevice:
        Text(Constants.multiSourceDeviceText)
      @unknown default:
        Text(Constants.unknownReasonText)
      }
    case .eligible:
      self.decommissionButton
    case .eligibleWithSideEffects(let sideEffects):
      HStack {
        Image(systemName: Constants.warningIcon)
        switch sideEffects {
        case .bridge(let bridgedDeviceIDs):
          VStack(alignment: .leading) {
            Text(Constants.bridgeSideEffectsText)
            ForEach(Array(bridgedDeviceIDs), id: \.self) {
              Text("• \($0)").font(.caption)
            }
          }
        case .multipleAffectedDevices(let affectedDeviceIDs):
          VStack(alignment: .leading) {
            Text(Constants.multipleSideEffectsText)
            ForEach(Array(affectedDeviceIDs), id: \.self) {
              Text("• \($0)").font(.caption)
            }
          }
        @unknown default:
          Text(Constants.unknownSideEffectsText)
        }
      }
      self.decommissionButton
    @unknown default:
      Text(Constants.unknownEligibilityText)
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
        Text(Constants.decommissionButtonTitle)
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

// A labeled level slider bound to a `RangeControl`.
struct RangeSlider: View {
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

      let binding = Binding(
        get: { sliderValue },
        set: { if rangeControl.validate(Int16($0)) { sliderValue = $0 } }
      )

      let onEditing: (Bool) -> Void = { editing in
        isEditing = editing
        if !editing { rangeControl.rangeValue = sliderValue }
      }

      let span = rangeControl.range.upperBound - rangeControl.range.lowerBound

      if span >= 50.0 {
        Slider(
          value: $rangeControl.rangeValue,
          in: rangeControl.range,
          step: 50.0,
          onEditingChanged: onEditing
        )
      } else {
        Slider(
          value: binding,
          in: rangeControl.range,
          onEditingChanged: onEditing
        )
      }
    }
    .onChange(of: rangeControl.rangeValue) { oldValue, newValue in
      if !isEditing {
        sliderValue = newValue
      }
    }
  }
}

private struct ButtonGroupView: View {
  private enum Constants {
    static let columnCount = 2
  }

  @ObservedObject var buttonGroupControl: ButtonGroupControl

  var body: some View {
    let displayedButtons = buttonGroupControl.buttons.filter({ $0.isDisplayed })
    let columnCount = Constants.columnCount
    let rowCount = (displayedButtons.count + columnCount - 1) / columnCount
    VStack {
      ForEach(0..<rowCount, id: \.self) { rowIndex in
        HStack {
          ForEach(0..<columnCount, id: \.self) { colIndex in
            if colIndex > 0 {
              Spacer()
            }
            let buttonIndex = rowIndex * Constants.columnCount + colIndex
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
