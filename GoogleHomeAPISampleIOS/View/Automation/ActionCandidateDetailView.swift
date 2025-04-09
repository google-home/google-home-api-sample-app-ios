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
struct ActionCandidateDetailView: View {
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
        if let selectedActionDevice = viewModel.selectedActionDevice {
          deviceInfoSection(selectedActionDevice: selectedActionDevice)
          deviceNodeSection(selectedActionDevice: selectedActionDevice)
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
  private func deviceInfoSection(selectedActionDevice: CandidatesViewModel.DeviceEntry) -> some View {
    Section("Device") {
      CreateButtonView(imageName: selectedActionDevice.iconName, text1: selectedActionDevice.device.name, text2: "") {}
      .padding(.bottom, 8)
    }.listRowSeparator(.hidden)
  }

  /// Display corresponding selectable traits
  private func deviceNodeSection(selectedActionDevice: CandidatesViewModel.DeviceEntry) -> some View {
    Section(selectedActionDevice.typeName) {
      ForEach(selectedActionDevice.nodes.filter { $0.isSupported && $0.node is TraitAttributesCandidate }) {
        entry in
        CreateButtonView(imageName: entry.iconName, text1: entry.description, text2: "") {
          selectedEntryForSheet = entry
        }
        .padding(.bottom, 8)
      }
      .listRowSeparator(.hidden)
    }
  }

  /// Display a sheet for trait action selection
  private func constraintSheet(for entry: CandidatesViewModel.NodeEntry) -> any View {
    let trait = entry.node.trait

    guard let selectedActionDevice = viewModel.selectedActionDevice else {
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
        doneButtonView(for: entry, selectedActionDevice: selectedActionDevice)
      }
      .presentationDetents([.fraction(CGFloat(0.5))])
      .presentationCornerRadius(20)
    } else if trait == Matter.ColorControlTrait.self || trait == Matter.LevelControlTrait.self {
      return VStack {
        Text("Level Control not supported as action in this sample app")
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

  private func doneButtonView(for entry: CandidatesViewModel.NodeEntry, selectedActionDevice: CandidatesViewModel.DeviceEntry) -> some View {
    HStack {
      Spacer()
      Button(action: {
        // Store the selected action info to the 'selecettedActions' array
        viewModel.addSelectedActions(device: selectedActionDevice.device, deviceType: selectedActionDevice.deviceType, trait: entry.traitType, valueOnOff: toggleValue, operation: selectedOperation, levelValue: UInt8(levelValue))
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
