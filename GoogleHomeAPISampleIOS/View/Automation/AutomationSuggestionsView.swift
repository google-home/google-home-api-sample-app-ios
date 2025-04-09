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
import SwiftUI

@MainActor
public struct AutomationSuggestionsView: View {
  @EnvironmentObject var automationList: AutomationList
  @StateObject var viewModel: AutomationSuggestionsViewModel
  @State private var selectedAutomationIndex: Int? = nil
  @Binding var navigationPath: NavigationPath

  public var body: some View {

    /// Generic editor button
    CreateButtonView(imageName: "astrophotography_mode_symbol", text1: "Generic Automation", text2: "") {
      navigationPath.append(Destination.GenericEditorView)
    }
    .padding(.bottom, 8)

    List {
      Section("Predefined Automations") {
        /// Display automations that are able to be created.
        /// Note automations without sufficient devices prepared will not be displayed here.
        ForEach(Array(viewModel.automations.enumerated()), id: \.offset) { index, automation in
          CreateButtonView(imageName: "astrophotography_mode_symbol", text1: automation.name, text2: automation.description) {
            navigationPath.append(index)
            selectedAutomationIndex = index
          }
          .padding(.bottom, 8)
        }
      }
      .listRowSeparator(.hidden)
      .listRowInsets(EdgeInsets())
    }
    .listStyle(PlainListStyle())
    .navigationTitle("Automation Suggestions")
    .navigationBarTitleDisplayMode(.inline)
    .navigationDestination(item: $selectedAutomationIndex) { index in
      /// Pop up AutomationCreationView when selecting an automation to create
      AutomationCreationView(
        viewModel: viewModel.makeCreationViewModel(
          automationList: automationList, automationIndex: index),
        navigationPath: $navigationPath
      )
    }
  }
}
