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
import OSLog

struct AutomationsView: View {
  @State private var isButtonTapped: Bool = false
  @State private var selectedAutomationIndex: Int? = nil
  @State private var navigationPath = NavigationPath()
  @EnvironmentObject private var mainViewModel: MainViewModel
  @EnvironmentObject var automationList: AutomationList
  public var body: some View {
    NavigationStack(path: $navigationPath) {
      VStack {
        headerView()

        List {
          if automationList.automationsUIModels.isEmpty {
            emptyStateSection()
          } else {
            userAutomationsSection()
          }

          if !automationList.suggestions.isEmpty {
            aiSuggestionsSection()
          }
        }
        .listStyle(PlainListStyle())

        Spacer()
        addButtonView()
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
      .navigationDestination(for: SuggestionDestination.self) { destination in
        if let suggestion = automationList.suggestions.first(where: { $0.id == destination.id }) {
          let viewModel = AutomationCreationViewModel(
            automationList: automationList,
            draftAutomation: suggestion.suggestionInstance
          )
          AutomationCreationView(
            viewModel: viewModel,
            navigationPath: $navigationPath
          )
        }
      }
      .navigationDestination(for: Destination.self) { destination in
        switch destination {
        case .AutomationSuggestionsView:
          if let home = mainViewModel.home {
            /// Pop up AutomationSuggestionsView when clicking on the 'Add' button
            AutomationSuggestionsView(
              viewModel: AutomationSuggestionsViewModel(
                home: home,
                structure: automationList.structure
              ),
              navigationPath: $navigationPath
            )
            .environmentObject(automationList)
            .environmentObject(mainViewModel)
          }
        case .GenericEditorView:
          if let candidatesViewModel = self.mainViewModel.getCandidatesViewModel(),
            let home = mainViewModel.home
          {
            GenericEditorView(
              viewModel: GenericEditorViewModel(automationList: automationList),
              candidatesViewModel: candidatesViewModel,
              automationRepository: AutomationsRepository(
                home: home,
                structure: automationList.structure
              ),
              navigationPath: $navigationPath
            )
          }
        case .NaturalLanguageEditorView:
          if let candidatesViewModel = self.mainViewModel.getCandidatesViewModel(),
            let home = mainViewModel.home
          {
            GenericEditorView(
              viewModel: GenericEditorViewModel(automationList: automationList),
              candidatesViewModel: candidatesViewModel,
              automationRepository: AutomationsRepository(
                home: home,
                structure: automationList.structure
              ),
              cameraOnly: true,
              editorTitle: "Nature Language Starter",
              navigationPath: $navigationPath
            )
          }
        case .StarterCandidatesView:
          if let candidatesViewModel = self.mainViewModel.getCandidatesViewModel() {
            StarterCandidatesView(
              viewModel: candidatesViewModel,
              cameraOnly: false,
              navigationPath: $navigationPath
            )
          }
        case .CameraStarterCandidatesView:
          if let candidatesViewModel = self.mainViewModel.getCandidatesViewModel() {
            StarterCandidatesView(
              viewModel: candidatesViewModel,
              cameraOnly: true,
              navigationPath: $navigationPath
            )
          }
        case .ActionCandidatesView:
          if let candidatesViewModel = self.mainViewModel.getCandidatesViewModel() {
            ActionCandidatesView(
              viewModel: candidatesViewModel,
              navigationPath: $navigationPath
            )
          }
        case .StarterCandidateDetailView:
          if let candidatesViewModel = self.mainViewModel.getCandidatesViewModel() {
            StarterCandidateDetailView(
              viewModel: candidatesViewModel,
              navigationPath: $navigationPath
            )
          }
        case .ActionCandidateDetailView:
          if let candidatesViewModel = self.mainViewModel.getCandidatesViewModel() {
            ActionCandidateDetailView(
              viewModel: candidatesViewModel,
              navigationPath: $navigationPath
            )
          }
        }
      }
    }
  }

  // MARK: - Subviews

  @ViewBuilder
  private func headerView() -> some View {
    HStack {
      Text("Automation")
        .font(.body)
        .padding(.leading, .xs)
      Spacer()
    }
  }

  @ViewBuilder
  private func emptyStateSection() -> some View {
    Section {
      VStack(alignment: .center) {
        Spacer()
        Text("Add an automation to get started.")
          .font(.body)
          .foregroundColor(.secondary)
          .frame(maxWidth: .infinity, alignment: .center)
        Spacer()
      }
      .frame(height: 120)
    }
    .listRowInsets(EdgeInsets())
    .listRowSeparator(.hidden)
  }

  @ViewBuilder
  private func userAutomationsSection() -> some View {
    Section("Your Automations") {
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
        .padding(.bottom, .sm)
      }
      .listRowInsets(EdgeInsets())
      .listRowSeparator(.hidden)
    }
  }

  @ViewBuilder
  private func aiSuggestionsSection() -> some View {
    Section("Suggested by AI") {
      ForEach(automationList.suggestions, id: \.id) { suggestion in
        AutomationSuggestionRowView(
          suggestion: suggestion,
          onSelect: {
            navigationPath.append(SuggestionDestination(id: suggestion.id))
          },
          onLike: {
            Task {
              if suggestion.suggestionMetadata.feedbackType == .like {
                try? await automationList.clearSuggestionFeedback(suggestion)
              } else {
                try? await automationList.likeSuggestion(suggestion)
              }
            }
          },
          onDislike: {
            Task {
              if suggestion.suggestionMetadata.feedbackType == .dislike {
                try? await automationList.clearSuggestionFeedback(suggestion)
              } else {
                try? await automationList.dislikeSuggestion(suggestion)
              }
            }
          }
        )
        .padding(.bottom, .sm)
      }
      .listRowInsets(EdgeInsets())
      .listRowSeparator(.hidden)
    }
  }

  @ViewBuilder
  private func addButtonView() -> some View {
    HStack {
      Spacer()
      NavigationLink(value: Destination.AutomationSuggestionsView) {
        Text("+ Add")
          .frame(
            width: Dimensions.buttonWidth,
            height: Dimensions.buttonHeight
          )
          .background(Color.blue)
          .foregroundColor(.white)
          .cornerRadius(.md)
          .padding(.trailing, .xs)
          .padding(.bottom, .xs)
      }
    }
  }
}

struct SuggestionDestination: Hashable {
  let id: String
}

enum Destination: Hashable {
  case AutomationSuggestionsView
  case GenericEditorView
  case NaturalLanguageEditorView
  case StarterCandidatesView
  case CameraStarterCandidatesView
  case ActionCandidatesView
  case StarterCandidateDetailView
  case ActionCandidateDetailView
}

enum Dimensions {
  static let buttonHeight = 40.0
  static let buttonWidth = 80.0

  enum CameraPicker {
    static let height: CGFloat = 150
    static let bottomPadding: CGFloat = -30
  }
}
