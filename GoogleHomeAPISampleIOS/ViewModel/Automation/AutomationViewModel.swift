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
import OSLog

/// View model for the AutomationView.
@MainActor
public final class AutomationViewModel: ObservableObject {
  /// The current automation name.
  @Published public var automationName = ""
  /// The current automation description.
  @Published public var automationDescription = ""
  /// Indicates whether or not the view is busy.
  @Published public var isBusy = false
  /// Indicates failure to update the automation.
  @Published public var saveError: (any Error)?
  /// Indicates whether the automation being displayed is manually executable
  @Published public var isManuallyExecutable: Bool = false
  /// Indicates whether the automation execution attempt failed
  @Published public var executionError: (any Error)?

  public let automationModel: AutomationUIDataModel

  /// The selected automation object
  private let automation: any Automation
  private let automationList: AutomationList

  public init(
    automation: any Automation,
     automationModel: AutomationUIDataModel,
     automationList: AutomationList,
     dismissAction: @escaping () -> Void
   ) {
     self.automation = automation
     self.automationModel = automationModel
     self.automationList = automationList
     self.automationName = automationModel.name
     self.automationDescription = automationModel.description
     self.isManuallyExecutable = automation.manuallyExecutable
  }

  /// Saves the automation with the updated name and description.
  public func saveAutomation() async throws {
    Task { @MainActor in
      guard let updatedAutomation = self.updatedAutomation() else { return }
      self.isBusy = true
      do {
        _ = try await automationList.updateAutomation(updatedAutomation)
      } catch {
        Logger().error("Save automation failed: \(error)")
        saveError = error
        throw error
      }
      isBusy = false
    }
  }

  public func executeAutomation() async throws {
    Task { @MainActor in
      do {
        try await automation.execute()
      } catch {
        Logger().error("Execute automation failed: \(error)")
        executionError = error
        throw error
      }
    }
  }

  /// Update the name and the desciption.
  private func updatedAutomation() -> (any DraftAutomation)? {
    return GoogleHomeSDK.automation(
       id: automation.id,
       structureID: automation.structureID,
       name: automationName,
       description: automationDescription
     ) {
       automation.automationGraph?.nodes ?? []
     }
  }
}
