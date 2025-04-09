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
import Matter

/// An in-memory implementation of the Matter storage API.
///
/// This information is not persisted across app launches because the "3P" Fabric Commissioning
/// functionality in the Sample App is only intended to be used for testing during the commissioning
/// flow and does not need to actually be functional or allow the device to be controlled.
class InMemoryMatterStorage: NSObject, MTRStorage {

  private var storage: [String: Data] = [:]

  // MARK: - MTRStorage

  func storageData(forKey key: String) -> Data? {
    return self.storage[key]
  }

  func setStorageData(_ value: Data, forKey key: String) -> Bool {
    self.storage[key] = value
    return true
  }

  func removeStorageData(forKey key: String) -> Bool {
    self.storage.removeValue(forKey: key)
    return true
  }
}
