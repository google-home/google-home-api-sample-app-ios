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

import SwiftUI
import GoogleHomeSDK

/// A view that displays a suggested automation card with interactive like and dislike buttons.
public struct AutomationSuggestionRowView: View {
  let suggestion: AutomationSuggestion
  let onSelect: () -> Void
  let onLike: () -> Void
  let onDislike: () -> Void

  public init(
    suggestion: AutomationSuggestion,
    onSelect: @escaping () -> Void,
    onLike: @escaping () -> Void,
    onDislike: @escaping () -> Void
  ) {
    self.suggestion = suggestion
    self.onSelect = onSelect
    self.onLike = onLike
    self.onDislike = onDislike
  }

  public var body: some View {
    HStack {
      Button(action: onSelect) {
        HStack {
          Image(Constants.aiSparkleIcon)
            .renderingMode(.template)
            .foregroundColor(.purple)

          VStack(alignment: .leading) {
            Text(suggestion.suggestionMetadata.name)
              .foregroundColor(Color(Constants.fontColor))
              .lineLimit(1)

            if !suggestion.suggestionMetadata.description.isEmpty {
              Text(suggestion.suggestionMetadata.description)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .buttonStyle(.plain)

      Spacer()

      HStack(spacing: Constants.buttonSpacing) {
        Button(action: onLike) {
          Image(systemName: suggestion.suggestionMetadata.feedbackType == .like ? Constants.thumbsUpFill : Constants.thumbsUp)
            .foregroundColor(suggestion.suggestionMetadata.feedbackType == .like ? .blue : .secondary)
        }
        .buttonStyle(.borderless)

        Button(action: onDislike) {
          Image(systemName: suggestion.suggestionMetadata.feedbackType == .dislike ? Constants.thumbsDownFill : Constants.thumbsDown)
            .foregroundColor(suggestion.suggestionMetadata.feedbackType == .dislike ? .red : .secondary)
        }
        .buttonStyle(.borderless)
      }
    }
    .padding()
    .background(Color(uiColor: .secondarySystemBackground))
    .cornerRadius(Constants.cardCornerRadius)
  }
}

private enum Constants {
  // Images & Icons
  static let aiSparkleIcon = "astrophotography_mode_symbol"
  static let thumbsUp = "hand.thumbsup"
  static let thumbsUpFill = "hand.thumbsup.fill"
  static let thumbsDown = "hand.thumbsdown"
  static let thumbsDownFill = "hand.thumbsdown.fill"
  static let fontColor = "fontColor"

  // Layout Spacing
  static let buttonSpacing: CGFloat = 16
  static let cardCornerRadius: CGFloat = 12
}
