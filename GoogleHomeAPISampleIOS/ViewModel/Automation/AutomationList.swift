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
import GoogleHomeTypes
import OSLog

@MainActor
public class AutomationList: ObservableObject {
  /// Data models for UI display.
  @Published public var automationsAndUIModels = [(any Automation, AutomationUIDataModel)]()
  public var automationsUIModels: [AutomationUIDataModel] { automationsAndUIModels.map { $0.1 } }
  public var automations: [any Automation] { automationsAndUIModels.map { $0.0 } }
  @Published public var suggestions = [AutomationSuggestion]()
  public let structure: Structure
  public init(structure: Structure) {
    self.structure = structure
    Task { [self] in
      do {
        try await refresh()
      } catch {
      }
    }
  }

  /// Append fetched automations to data models
  public func add(_ automation: any Automation) {
    automationsAndUIModels.append((automation, AutomationUIDataModel(draftAutomation: automation)))
  }

  /// Read automation scripts from the structure. Call it after create any automation to refresh our data model.
  public func refresh() async throws {
    Logger().info("ListAutomations request for structure ID: \(self.structure.id)")
    automationsAndUIModels = []
    do {
      let automations = try await structure.listAutomations()
      for automation in automations {
        add(automation)
      }
      Logger().info("ListAutomations response: \(automations)")

      try await fetchSuggestions()
    } catch {
      Logger().error("ListAutomations error: \(error)")
      throw error
    }
  }

  /// Fetch automation suggestions from the structure.
  public func fetchSuggestions() async throws {
    Logger().info("Fetching suggestions for structure ID: \(self.structure.id)")
    do {
      let suggestionsList = try await structure.suggestions()
      self.suggestions = suggestionsList
      Logger().info("Fetch suggestions response: \(suggestionsList)")
    } catch {
      Logger().error("Fetch suggestions error: \(error)")
      throw error
    }
  }

  /// Likes an automation suggestion.
  public func likeSuggestion(_ suggestion: AutomationSuggestion) async throws {
    do {
      try await structure.likeSuggestion(suggestionID: suggestion.id)
      Logger().info("Liked suggestion: \(suggestion.id)")
      try await fetchSuggestions()
    } catch {
      Logger().error("Like suggestion error: \(error)")
      throw error
    }
  }

  /// Dislikes an automation suggestion.
  public func dislikeSuggestion(_ suggestion: AutomationSuggestion) async throws {
    do {
      try await structure.dislikeSuggestion(suggestionID: suggestion.id)
      Logger().info("Disliked suggestion: \(suggestion.id)")
      try await fetchSuggestions()
    } catch {
      Logger().error("Dislike suggestion error: \(error)")
      throw error
    }
  }

  /// Clears the feedback for an automation suggestion.
  public func clearSuggestionFeedback(_ suggestion: AutomationSuggestion) async throws {
    do {
      try await structure.clearSuggestionFeedback(suggestionID: suggestion.id)
      Logger().info("Cleared suggestion feedback: \(suggestion.id)")
      try await fetchSuggestions()
    } catch {
      Logger().error("Clear suggestion feedback error: \(error)")
      throw error
    }
  }

  /// Creates an automation on the structure and rolls it back if validation fails.
  ///
  /// - Parameter draftAutomation: The draft automation to create.
  /// - Throws: `AutomationListError` if validation fails, or an underlying SDK error.
  public func createAutomation(_ draftAutomation: any DraftAutomation) async throws {
    do {
      let newAutomation = try await structure.createAutomation(draftAutomation)
      Logger().info("CreateCommand Response Automation name: \(newAutomation.name)")
      if newAutomation.validationIssues.count > 0 {
        Logger().error("Found issues in the automation: \(newAutomation.validationIssues)")
        do {
          try await structure.deleteAutomation(newAutomation)
        } catch {
          Logger().error("Failed to delete invalid automation during rollback: \(error)")
        }
        if let correction = Self.rewordableCameraQuery(in: newAutomation.validationIssues) {
          throw AutomationListError.cameraQueryNeedsRewording(correction)
        }
        throw AutomationListError.validationFailed(newAutomation.validationIssues)
      }
    } catch {
      Logger().error("CreateCommand error: \(error)")
      throw error
    }
  }

  /// Get automation command.
  public func fetchAutomation(for automationID: String) async throws
    -> any Automation
  {
    Logger().info("Fetch automation request for automation ID: \(automationID)")
    do {
      let automationList = try await structure.listAutomations()
      for automation in automationList {
        if automation.id == automationID {
          Logger().info("Fetch Response Automation Object: \(automation.name)")
          return automation
        }
      }

      throw AutomationListError.automationNotFound(automationID)
    } catch {
      Logger().error("Fetch error \(error)")
      throw error
    }
  }

  /// Update automation command.
  public func updateAutomation(_ automation: any DraftAutomation)
    async throws
    -> any Automation
  {
    Logger().info("UpdateCommand Request Automation Object: \(automation.name)")
    do {
      let originalAutomation = try await fetchAutomation(for: automation.id)
      let updatedAutomation = try await originalAutomation.update({
        $0.name = automation.name
        $0.description = automation.description
        $0.isActive = automation.isActive
        $0.automationGraph = automation.automationGraph
      })

      if let index = automations.firstIndex(where: {
        $0.id == updatedAutomation.id
      }) {
        /// Ensure publishing update is on main thread.
        await MainActor.run {
          self.automationsAndUIModels[index] =
            (updatedAutomation, AutomationUIDataModel(draftAutomation: updatedAutomation))
        }
      } else {
        Logger().error("Unable to update automation list for automation: \(updatedAutomation.id)")
      }
      return updatedAutomation
    } catch {
      Logger().error("Update error \(error)")
      throw error
    }
  }

  /// Delete automation command.
  public func deleteAutomation(_ automation: any Automation)
    async throws
  {
    do {
      try await structure.deleteAutomation(automation)
      /// Delete automation in data models.
      if let index = automations.firstIndex(where: {
        $0.id == automation.id
      }) {
        self.automationsAndUIModels.remove(at: index)
        Logger().info("Automation deleted: \(automation.name)")
      } else {
        Logger().error("Failed to find an automation in the list.")
      }
    } catch {
      Logger().error("DeleteCommand error: \(error)")
      throw error
    }
  }

  /// Extracts a camera query correction when it is the only blocking validation issue.
  ///
  /// - Parameter issues: The validation issues returned for the automation.
  /// - Returns: The rejected and suggested queries, or `nil` if not rewordable.
  private static func rewordableCameraQuery(
    in issues: [AutomationValidationIssue]
  ) -> CameraQueryCorrection? {
    let blockingIssues = issues.filter { $0.severity != .warning }
    guard
      blockingIssues.count == 1,
      let issue = blockingIssues.first,
      case .invalidCustomCameraEventQuery(let query, let reason, let suggestions, _) =
        issue.issueType,
      reason == .hasCorrectionSuggestion,
      let suggestion = suggestions.first(where: {
        let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != query.trimmingCharacters(in: .whitespacesAndNewlines)
      })
    else {
      return nil
    }
    return CameraQueryCorrection(rejectedQuery: query, suggestedQuery: suggestion)
  }
}

/// A camera activity query the backend refused, paired with the wording it offered instead.
public struct CameraQueryCorrection: Equatable, Sendable {
  /// The query as the user submitted it.
  public let rejectedQuery: String
  /// The wording the backend indicated it would accept.
  public let suggestedQuery: String

  /// Creates a camera query correction pair.
  ///
  /// - Parameters:
  ///   - rejectedQuery: The query as the user submitted it.
  ///   - suggestedQuery: The replacement wording offered by the backend.
  public init(rejectedQuery: String, suggestedQuery: String) {
    self.rejectedQuery = rejectedQuery
    self.suggestedQuery = suggestedQuery
  }
}

/// Errors thrown by `AutomationList` operations.
public enum AutomationListError: LocalizedError {
  /// The save failed only because of the camera query, and a replacement wording is available.
  ///
  /// - Parameter correction: The rejected camera query and its suggested replacement.
  case cameraQueryNeedsRewording(CameraQueryCorrection)
  /// The created automation failed validation and was deleted.
  ///
  /// - Parameter issues: The validation issues returned for the automation.
  case validationFailed([AutomationValidationIssue])
  /// No automation matched the given identifier.
  ///
  /// - Parameter automationID: The identifier of the missing automation.
  case automationNotFound(String)

  /// A localized message describing what error occurred.
  public var errorDescription: String? {
    switch self {
    case .cameraQueryNeedsRewording(let correction):
      return "Invalid camera query '\(correction.rejectedQuery)'. "
        + "Try '\(correction.suggestedQuery)' instead."
    case .validationFailed(let issues):
      let issueDescriptions = issues.map(Self.description(for:)).joined(separator: "; ")
      return "Automation has validation issues: \(issueDescriptions)"
    case .automationNotFound(let automationID):
      return "Automation not found with \(automationID)"
    }
  }

  /// Formats a single validation issue into a human-readable summary.
  ///
  /// - Parameter issue: The validation issue to format.
  /// - Returns: A formatted description of the validation issue.
  private static func description(for issue: AutomationValidationIssue) -> String {
    if case .invalidCustomCameraEventQuery(let query, let reason, let suggestions, _) =
      issue.issueType
    {
      let detailsSuffix = issue.details.isEmpty ? "" : " (\(issue.details))"
      let suggestionsSuffix =
        suggestions.isEmpty ? "" : " (Suggestions: \(suggestions.joined(separator: ", ")))"
      return "Invalid camera query '\(query)': \(reason)\(detailsSuffix)\(suggestionsSuffix)"
    }
    return issue.details.isEmpty ? String(describing: issue.issueType) : issue.details
  }
}
