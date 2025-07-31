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

import Foundation
import GoogleHomeSDK
import OSLog

enum RenameType {
  case Device
  case Room
}
/// The viewModel handling deivce or room renaming.
@MainActor
class RenameViewModel: ObservableObject {
  @Published var name: String

  let title: String
  let subtitle: String
  let textFieldLabel: String
  private let setName: (String) async throws -> Any

  init(
    renameType: RenameType,
    name: String,
    setName: @escaping (String) async throws -> Any
  ) {
    switch renameType {
    case .Device:
      self.title = "Name your device"
      self.subtitle = "Choose a name for this device to help identify it better"
      self.textFieldLabel = "Device Nickname"
    case .Room:
      self.title = "Edit name"
      self.subtitle = "Change the name of your room"
      self.textFieldLabel = "Edit room name"
    }
    self.name = name
    self.setName = setName
  }

  func save() async -> Bool {
    let trimmedName = name.trimmingCharacters(in: .whitespaces)
    guard !trimmedName.isEmpty else {
      Logger().warning("Attempted to save an empty name.")
      return false
    }

    do {
      _ = try await self.setName(name)
      return true
    } catch {
      Logger().error("Failed to rename: \(error)")
      return false
    }
  }
}
