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
import GoogleHomeSDK
import GoogleHomeTypes
import OSLog
@MainActor
public class AutomationList: ObservableObject {
  /// Data models for UI display.
  @Published public var automationsAndUIModels = [(any Automation, AutomationUIDataModel)]()
  public var automationsUIModels: [AutomationUIDataModel] { automationsAndUIModels.map { $0.1 } }
  public var automations: [any Automation] { automationsAndUIModels.map { $0.0 } }
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
    } catch {
      Logger().error("ListAutomations error: \(error)")
      throw error
    }
  }

  /// Create automation command.
  public func createAutomation(_ automationObject: any DraftAutomation) async {
    do {
      let newAutomation = try await structure.createAutomation(automationObject)
      Logger().info("CreateCommand Response Automation name: \(newAutomation.name)")
      if newAutomation.validationIssues.count > 0 {
        Logger().error("Found issues in the automation: \(newAutomation.validationIssues)")
      }
    } catch {
      Logger().error("CreateCommand error: \(error)")
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

      throw HomeError.notFound("Automation not found with \(automationID)")
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
        Logger().error(
          "Unable to update automation list for automation: \(updatedAutomation.id)")
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
}
