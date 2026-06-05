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

import Combine
import Foundation
import GoogleHomeSDK
import GoogleHomeTypes
import OSLog
import Observation

/// Represents a single message in the search history, either from the user or the system.
struct SearchMessage: Identifiable {
  /// The unique identifier for the message.
  let id = UUID()
  /// A boolean indicating if the message was sent by the user.
  let isUser: Bool
  /// The text content of the message.
  let text: String
  /// An array of camera event details associated with the message, if any.
  let cameraEvents: [Google.SearchableHomeTrait.BasicCameraEventDetails]
}

/// A view model that manages the state and logic for the Searchable Home feature.
@Observable
@MainActor
final class SearchableHomeViewModel {
  private let structure: Structure

  /// The current search query string.
  var query: String = ""

  /// The history of search messages and responses.
  private(set) var messages: [SearchMessage] = []

  /// A list of suggested search queries.
  private(set) var suggestions: [String] = []

  /// A boolean indicating whether a search is currently in progress.
  private(set) var isSearching: Bool = false

  /// Initializes the view model with the given structure.
  /// - Parameter structure: The structure to perform searches on.
  init(structure: Structure) {
    self.structure = structure
  }

  /// Fetches search suggestions for the current structure.
  func fetchSuggestions() async {
    guard let trait = await structure.traits.get(Google.SearchableHomeTrait.self) else {
      Logger().error(
        """
        SearchableHomeTrait not found on structure. \
        Structure details: \(String(describing: self.structure)) | \
        Traits dump: \(String(describing: self.structure.traits))
        """
      )
      return
    }

    do {
      let result = try await trait.getSearchSuggestions()
      self.suggestions = result.suggestionsArray
    } catch {
      Logger().error("Error fetching suggestions: \(error.localizedDescription)")
    }
  }

  /// Submits the current query and fetches the search response.
  func submitQuery() async {
    let currentQuery = self.query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !currentQuery.isEmpty else { return }

    self.messages.append(SearchMessage(isUser: true, text: currentQuery, cameraEvents: []))
    self.query = ""
    self.isSearching = true

    do {
      if let trait = await structure.traits.get(Google.SearchableHomeTrait.self) {
        let result = try await trait.search(query: currentQuery)
        self.messages.append(
          SearchMessage(
            isUser: false,
            text: result.queryResponse ?? "Error getting response.",
            cameraEvents: result.cameraEventsArray
          )
        )
      } else {
        Logger().error(
          """
          SearchableHomeTrait not found on structure. \
          Structure details: \(String(describing: self.structure)) | \
          Traits dump: \(String(describing: self.structure.traits))
          """
        )
        self.messages.append(
          SearchMessage(
            isUser: false,
            text:
              """
              SearchableHomeTrait not found on structure. \
              Check if the account has a premium subscription.
              """,
            cameraEvents: []
          )
        )
      }
    } catch {
      Logger().error("Search failed with error: \(error.localizedDescription)")
      self.messages.append(
        SearchMessage(
          isUser: false,
          text:
            """
            There was an error getting a response. \
            Make sure the account has a premium subscription.
            """,
          cameraEvents: []
        )
      )
    }

    self.isSearching = false
  }
}
