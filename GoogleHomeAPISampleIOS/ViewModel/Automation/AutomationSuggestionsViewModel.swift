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
import OSLog

@MainActor
public class AutomationSuggestionsViewModel: ObservableObject {
  private let home: Home
  private let structure: Structure
  /// Predefined automation scripts
  private let automationsRepository: AutomationsRepository

  @Published public var automations: [any DraftAutomation] = []

  public init(home: Home, structure: Structure) {
    self.home = home
    self.structure = structure
    self.automationsRepository = AutomationsRepository(home: home, structure: structure)
    fetchAutomations()
  }

  public func makeCreationViewModel(
    automationList: AutomationList,
    automationIndex: Int
  ) -> AutomationCreationViewModel {
    return AutomationCreationViewModel(
      automationList: automationList,
      draftAutomation: automations[automationIndex]
    )
  }

  /// Fetch predefined automation scripts
  /// Note automations without sufficient devices prepared will not be included here.
  private func fetchAutomations() {
    Task { @MainActor in
      do {
        let automations = try await self.automationsRepository.list()
        self.automations = automations
      } catch {
        Logger().error("Failed to get automations: \(error.localizedDescription)")
      }
    }
  }
}
