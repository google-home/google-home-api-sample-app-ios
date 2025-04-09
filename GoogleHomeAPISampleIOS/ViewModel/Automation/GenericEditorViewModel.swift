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

import GoogleHomeSDK
import SwiftUICore
import Combine

public class GenericEditorViewModel: ObservableObject {
  /// Name of the automation.
  @Published public var name: String
  /// Automation description.
  @Published public var description: String
  private let automationList: AutomationList

  public init(automationList: AutomationList) {
    self.name = "Test Automation Name"
    self.description = "This is a test automation description"
    self.automationList = automationList
  }

  /// Create automation command.
  public func createAutomation(draftAutomation: any DraftAutomation) async throws {
    await automationList.createAutomation(draftAutomation)
    try await automationList.refresh()
  }
}
