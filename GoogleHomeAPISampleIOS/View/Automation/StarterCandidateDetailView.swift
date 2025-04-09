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

import CoreFoundation
import GoogleHomeSDK
import GoogleHomeTypes
import SwiftUI

@MainActor
struct StarterCandidateDetailView: View {
  @State private var toggleValue = false
  @State private var selectedEntryForSheet: CandidatesViewModel.NodeEntry?
  @State private var selectedOperation: Operations = Operations.equalsTo
  @State private var levelValue: Float = 125

  /// Model for the selected device
  @ObservedObject private var viewModel: CandidatesViewModel
  @Binding var navigationPath: NavigationPath
  
  init(viewModel: CandidatesViewModel, navigationPath: Binding<NavigationPath>) {
    self.viewModel = viewModel
    self._navigationPath = navigationPath
  }
  public var body: some View {
    VStack{
      List {
        if let selectedStarterDevice = viewModel.selectedStarterDevice {
          deviceInfoSection(selectedStarterDevice: selectedStarterDevice)
          deviceNodeSection(selectedStarterDevice: selectedStarterDevice)
        }
        else {
          Text("No devcie selected. Please back to previous page.")
        }
      }
      .listStyle(.inset)
      .listRowSeparator(.hidden)
      .padding(.top, 20)
    }
    .sheet(item: $selectedEntryForSheet) { currentEntry in
      AnyView(self.constraintSheet(for: currentEntry))
    }
  }

  /// Display selected device info
  private func deviceInfoSection(selectedStarterDevice: CandidatesViewModel.DeviceEntry) -> some View {
    Section("Device") {
      CreateButtonView(imageName: selectedStarterDevice.iconName, text1: selectedStarterDevice.device.name, text2: "") {}
      .padding(.bottom, 8)
    }.listRowSeparator(.hidden)
  }

  /// Display corresponding selectable traits
  private func deviceNodeSection(selectedStarterDevice: CandidatesViewModel.DeviceEntry) -> some View {
    Section(selectedStarterDevice.typeName) {
      ForEach(selectedStarterDevice.nodes.filter { $0.isSupported && $0.node is TraitAttributesCandidate }) {
        entry in
        CreateButtonView(imageName: entry.iconName, text1: entry.description, text2: "") {
          selectedEntryForSheet = entry
        }
        .padding(.bottom, 8)
      }
      .listRowSeparator(.hidden)
    }
  }
  
  /// Display a sheet for trait condition selection
  private func constraintSheet(for entry: CandidatesViewModel.NodeEntry) -> any View {
    let trait = entry.node.trait
    
    guard let selectedStarterDevice = viewModel.selectedStarterDevice else {
      return VStack {
        Text("No device selected")
      }
      .presentationDetents([.fraction(CGFloat(0.5))])
      .presentationCornerRadius(20)
    }
    if trait == Matter.OnOffTrait.self || trait == Google.SimplifiedOnOffTrait.self {
      return VStack {
        Spacer()
        HStack {
          Text(entry.description).foregroundColor(Color("fontColor"))
          Spacer()
        }.padding(.horizontal, 50)
        Spacer()
        CreateToggleButtonView(isOn: $toggleValue, leftText: "On", rightText: "Off")
        Spacer()
        doneButtonView(for: entry, selectedStarterDevice: selectedStarterDevice)
      }
      .presentationDetents([.fraction(CGFloat(0.5))])
      .presentationCornerRadius(20)
    } else if trait == Matter.ColorControlTrait.self || trait == Matter.LevelControlTrait.self {
      return VStack {
        // Display operations and a slder for  selection
        Picker(selection: $selectedOperation, label: Text("Operation")) {
          Text("Eaquals to").tag(Operations.equalsTo)
          Text("Less than").tag(Operations.lessThan)
          Text("Greater than").tag(Operations.greaterThan)
        }
        .pickerStyle(SegmentedPickerStyle())
        Spacer()
        Text("Value: \(String(format: "%.0f", levelValue))")
        Slider(value: $levelValue, in : 1...254, step: 1) {
        } minimumValueLabel: {
            Text("1")
        } maximumValueLabel: {
            Text("254")
        }
        Spacer()
        doneButtonView(for: entry, selectedStarterDevice: selectedStarterDevice)
      }
      .presentationDetents([.fraction(CGFloat(0.5))])
      .presentationCornerRadius(20)
    } else {
      return VStack {
        Text("No supported trait")
      }
      .presentationDetents([.fraction(CGFloat(0.5))])
      .presentationCornerRadius(20)
    }
  }

  private func doneButtonView(for entry: CandidatesViewModel.NodeEntry, selectedStarterDevice: CandidatesViewModel.DeviceEntry) -> some View {
    HStack {
      Spacer()
      Button(action: {
        // Store the selected starter info to the 'selecettedStarters' array
        viewModel.addSelectedStarters(device: selectedStarterDevice.device, deviceType: selectedStarterDevice.deviceType, trait: entry.traitType, valueOnOff: toggleValue, operation: selectedOperation, levelValue: UInt8(levelValue))
        // Redirect back to GenericEditorView
        navigationPath.removeLast(2)
      }) {
        Text("Done")
          .frame(width: Dimensions.buttonWidth, height: Dimensions.buttonHeight)
          .background(Color.blue)
          .foregroundColor(.white)
          .cornerRadius(Dimensions.cornerRadius)
          .padding(.bottom, 20)
          .padding(.trailing, 10)
      }
      .alignmentGuide(.bottom) { $0[.bottom] }
      .background(Color.clear)
    }
  }
}
