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

/// Helper for storing and reading the ID of the currently selected structure across app launches.
struct SelectedStructureStorage {

  private let userDefaults = UserDefaults(suiteName: "com.google.homeplatform.selectedStructure")

  init() {}

  /// Returns the selected structure ID for the given identifier.
  func read(identifier: String?) -> String? {
    guard let identifier else { return nil }
    return userDefaults?.string(forKey: identifier)
  }

  /// Updates the selected structure ID stored for the specified identifier.
  func update(structureID: String, identifier: String?) {
    guard let identifier else { return }
    userDefaults?.set(structureID, forKey: identifier)
  }

}
