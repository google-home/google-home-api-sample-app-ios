// Copyright 2026 Google LLC
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
import SwiftUI
import UIKit

enum SearchableHomeConstraints {
  static let searchBarPadding: CGFloat = 10
  static let searchBarCornerRadius: CGFloat = 20
  static let sendButtonSize: CGFloat = 32
  static let messageSpacing: CGFloat = 16
  static let bubblePadding: CGFloat = 12
  static let bubbleCornerRadius: CGFloat = 16
  static let suggestionHorizontalPadding: CGFloat = 16
  static let suggestionVerticalPadding: CGFloat = 12
  static let suggestionTopPadding: CGFloat = 8
  static let eventSpacing: CGFloat = 8
  static let eventImageHeight: CGFloat = 150
  static let eventCornerRadius: CGFloat = 12
  static let eventShadowRadius: CGFloat = 3
  static let minUserSpacer: CGFloat = 40
  static let suggestionsMaxHeight: CGFloat = 200
  static let eventInnerCornerRadiusDivisor: CGFloat = 1.5
  static let innerEventCornerRadius: CGFloat = eventCornerRadius / eventInnerCornerRadiusDivisor
  static let photoIcon = "photo"
}

struct SearchableHomeView: View {
  @State private var viewModel: SearchableHomeViewModel
  @FocusState private var isTextFieldFocused: Bool
  let home: Home

  init(structure: Structure, home: Home) {
    self._viewModel = State(initialValue: SearchableHomeViewModel(structure: structure))
    self.home = home
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        messagesScrollView

        if isTextFieldFocused && !viewModel.suggestions.isEmpty {
          Divider()
          suggestionsList
            .frame(maxHeight: SearchableHomeConstraints.suggestionsMaxHeight)
            .background(Color(.systemBackground))
        }

        Divider()
        searchBar
      }
      .onTapGesture {
        isTextFieldFocused = false
      }
      .navigationTitle("Searchable Home")
      .task {
        await viewModel.fetchSuggestions()
      }
    }
  }

  private var searchBar: some View {
    HStack(alignment: .center) {
      TextField("Ask something...", text: $viewModel.query)
        .focused($isTextFieldFocused)
        .padding(SearchableHomeConstraints.searchBarPadding)
        .background(Color(.systemGray6))
        .cornerRadius(SearchableHomeConstraints.searchBarCornerRadius)
        .disabled(viewModel.isSearching)
        .onSubmit {
          performSearch()
        }

      sendButton
    }
    .padding()
  }

  private var sendButton: some View {
    Button(action: performSearch) {
      Image(systemName: "arrow.up.circle.fill")
        .resizable()
        .frame(
          width: SearchableHomeConstraints.sendButtonSize,
          height: SearchableHomeConstraints.sendButtonSize
        )
        .foregroundColor(canSubmit ? .blue : .gray)
    }
    .disabled(!canSubmit)
  }

  private var canSubmit: Bool {
    let isQueryEmpty = viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    return !isQueryEmpty && !viewModel.isSearching
  }

  private func performSearch() {
    isTextFieldFocused = false
    Task {
      await viewModel.submitQuery()
    }
  }

  private var suggestionsList: some View {
    ScrollView {
      if !viewModel.suggestions.isEmpty {
        VStack(alignment: .leading, spacing: 0) {
          suggestionsHeader

          ForEach(viewModel.suggestions, id: \.self) { suggestion in
            suggestionRow(for: suggestion)
            Divider()
              .padding(.leading, SearchableHomeConstraints.suggestionHorizontalPadding)
          }
        }
        .padding(.top, SearchableHomeConstraints.suggestionTopPadding)
      }
    }
    .transition(.move(edge: .bottom))
  }

  private var suggestionsHeader: some View {
    Text("Suggestions")
      .font(.subheadline)
      .fontWeight(.semibold)
      .foregroundColor(.secondary)
      .padding(.horizontal, SearchableHomeConstraints.suggestionHorizontalPadding)
      .padding(.vertical, SearchableHomeConstraints.suggestionVerticalPadding)
  }

  private func suggestionRow(for suggestion: String) -> some View {
    Button(action: {
      viewModel.query = suggestion
      performSearch()
    }) {
      HStack {
        Text(suggestion)
          .foregroundColor(.primary)
          .multilineTextAlignment(.leading)
        Spacer()
      }
      .padding(.horizontal, SearchableHomeConstraints.suggestionHorizontalPadding)
      .padding(.vertical, SearchableHomeConstraints.suggestionVerticalPadding)
      .contentShape(Rectangle())
    }
  }

  private var messagesScrollView: some View {
    ScrollViewReader { scrollView in
      ScrollView {
        VStack(spacing: SearchableHomeConstraints.messageSpacing) {
          ForEach(viewModel.messages) { message in
            MessageBubble(message: message, home: home)
              .id(message.id)
          }

          if viewModel.isSearching {
            loadingIndicator
              .id("loading")
          }
        }
        .padding()
      }
      .background(
        Color.clear
          .contentShape(Rectangle())
          .onTapGesture {
            isTextFieldFocused = false
          }
      )
      .onChange(of: viewModel.messages.count) {
        scrollToLastMessage(with: scrollView)
      }
      .onChange(of: viewModel.isSearching) { _, isSearching in
        if isSearching {
          scrollToLoading(with: scrollView)
        }
      }
    }
  }

  private var loadingIndicator: some View {
    HStack {
      ProgressView()
        .padding(SearchableHomeConstraints.bubblePadding)
        .background(Color(.systemGray6))
        .cornerRadius(SearchableHomeConstraints.bubbleCornerRadius)
      Spacer()
    }
  }

  private func scrollToLastMessage(with scrollView: ScrollViewProxy) {
    if let lastId = viewModel.messages.last?.id {
      withAnimation {
        scrollView.scrollTo(lastId, anchor: .bottom)
      }
    }
  }

  private func scrollToLoading(with scrollView: ScrollViewProxy) {
    withAnimation {
      scrollView.scrollTo("loading", anchor: .bottom)
    }
  }
}

struct MessageBubble: View {
  let message: SearchMessage
  let home: Home

  var body: some View {
    HStack {
      if message.isUser {
        Spacer(minLength: SearchableHomeConstraints.minUserSpacer)
      }

      VStack(
        alignment: message.isUser ? .trailing : .leading,
        spacing: SearchableHomeConstraints.eventSpacing
      ) {
        textBubble

        ForEach(message.cameraEvents, id: \.self) { event in
          CameraEventCard(event: event, home: home)
        }
      }

      if !message.isUser {
        Spacer(minLength: SearchableHomeConstraints.minUserSpacer)
      }
    }
  }

  @ViewBuilder
  private var textBubble: some View {
    if !message.text.isEmpty {
      Text(message.text)
        .padding(SearchableHomeConstraints.bubblePadding)
        .background(message.isUser ? Color.blue : Color(.systemGray6))
        .foregroundColor(message.isUser ? .white : .primary)
        .cornerRadius(SearchableHomeConstraints.bubbleCornerRadius)
    }
  }
}

struct CameraEventCard: View {
  let event: Google.SearchableHomeTrait.BasicCameraEventDetails
  let home: Home

  var body: some View {
    VStack(alignment: .leading, spacing: SearchableHomeConstraints.eventSpacing) {
      eventThumbnail

      if let shortCaption = event.shortCaption, !shortCaption.isEmpty {
        Text(shortCaption)
          .font(.subheadline)
          .foregroundColor(.primary)
      }

      if let sessionId = event.sessionId {
        Text("Session ID: \(sessionId)")
          .font(.caption2)
          .foregroundColor(.secondary)
      }
    }
    .padding(SearchableHomeConstraints.eventSpacing)
    .background(Color(.systemBackground))
    .cornerRadius(SearchableHomeConstraints.eventCornerRadius)
    .shadow(
      color: Color.black.opacity(0.1),
      radius: SearchableHomeConstraints.eventShadowRadius,
      x: 0,
      y: 1
    )
  }

  @ViewBuilder
  private var eventThumbnail: some View {
    if let urlString = event.thumbnailUrl, !urlString.isEmpty,
      let url = URL(string: urlString)
    {
      AuthenticatedAsyncImage(url: url, home: home) { phase in
        if let image = phase.image {
          image
            .resizable()
            .scaledToFit()
            .frame(maxHeight: SearchableHomeConstraints.eventImageHeight)
            .cornerRadius(SearchableHomeConstraints.innerEventCornerRadius)
        } else {
          Color.gray
            .frame(height: SearchableHomeConstraints.eventImageHeight)
            .cornerRadius(SearchableHomeConstraints.innerEventCornerRadius)
            .overlay {
              if phase.error != nil {
                Image(systemName: SearchableHomeConstraints.photoIcon)
                  .foregroundColor(.white)
              } else {
                ProgressView()
              }
            }
        }
      }
    }
  }
}
