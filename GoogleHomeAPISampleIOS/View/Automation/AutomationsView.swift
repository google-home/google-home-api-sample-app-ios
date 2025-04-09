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
import SwiftUI
import GoogleHomeSDK

struct AutomationsView: View {
  @State private var isButtonTapped: Bool = false
  @State private var selectedAutomationIndex: Int? = nil
  @State private var navigationPath = NavigationPath()
  @EnvironmentObject var automationList: AutomationList
  public var body: some View {
    NavigationStack(path: $navigationPath) {
      VStack {
        HStack {
          Text("Automation")
            .font(.system(size: 14, weight: .bold, design: .default))
            .padding(.leading, 5)
          Spacer()
        }
        if automationList.automationsUIModels.isEmpty {
          Spacer()
          Text("Add an automation to get started.")
            .font(.system(size: 14, weight: .bold, design: .default))
          Spacer()
        } else {
          List {
            /// Display automation scripts
            ForEach(Array(automationList.automationsUIModels.enumerated()), id: \.offset) { index, uiModel in
              let startersText =
                "\(uiModel.starters.count) \(uiModel.starters.count == 1 ? "starter" : "starters")"
              let conditionsText =
                "\(uiModel.conditions.count) \(uiModel.conditions.count == 1 ? "condition" : "conditions")"
              let actionsText =
                "\(uiModel.actions.count) \(uiModel.actions.count == 1 ? "action" : "actions")"

              CreateButtonView(imageName: "wb_twilight_symbol", text1: "\(uiModel.name)",
                               text2: "\(startersText) · \(conditionsText) · \(actionsText)")
              {
                selectedAutomationIndex = index
              }
              .swipeActions(
                edge: .trailing, allowsFullSwipe: false,
                content: {
                  Button(role: .destructive) {
                    Task {
                      try await automationList.deleteAutomation(automationList.automations[index])
                    }
                  } label: {
                    Image("delete_symbol")
                  }
                }
              )
              .padding(.bottom, 8)
            }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
          }
          .listStyle(PlainListStyle())
        }

        Spacer()
        HStack {
          Spacer()
          NavigationLink(value: "AutomationSuggestionsView") {
            Text("+ Add")
              .frame(
                width: AutomationCreationView.Dimensions.buttonWidth,
                height: AutomationCreationView.Dimensions.buttonHeight
              )
              .background(Color.blue)
              .foregroundColor(.white)
              .cornerRadius(AutomationCreationView.Dimensions.cornerRadius)
          }
        }
      }
      .navigationDestination(item: $selectedAutomationIndex) { index in
        if automationList.automations.count > index {
          let viewModel = AutomationViewModel(
            automation: automationList.automations[index],
            automationModel: automationList.automationsUIModels[index],
            automationList: automationList
          ) {
            selectedAutomationIndex = nil
          }
          AutomationView(viewModel: viewModel)
        }
      }
      .navigationDestination(for: String.self) { _ in
        /// Pop up AutomationSuggestionsView when clicking on the 'Add' button
        AutomationSuggestionsView(
          viewModel: AutomationSuggestionsViewModel(
            home: automationList.structure.context,
            structure: automationList.structure
          ),
          navigationPath: $navigationPath
        )
        .environmentObject(automationList)
      }
    }
  }
}
