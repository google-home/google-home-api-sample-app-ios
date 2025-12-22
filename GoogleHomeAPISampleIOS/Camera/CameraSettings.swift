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

import OSLog
import Observation
import SwiftUI

/// A camera setting that can be displayed.
///
/// This class manages the local values of a setting and it's ui state and binding, and handles the
/// logic for updating the remote value when the local value changes.
@Observable
@MainActor
public class CameraSetting<T> {

  public var binding: Binding<T> {
    Binding(
      get: { self.value },
      set: { value in
        self.value = value
        if !self.manualUpdate {
          Task {
            await self.remoteUpdateValue(value: value)
          }
        }
      }
    )
  }

  /// The current local value of the setting.
  public private(set) var value: T
  /// Whether there is a current request to the SDK in progress.
  public private(set) var isLoading: Bool = false
  /// Update function to be called when the setting value is updated.
  public var onUpdate: (@MainActor (T) async -> Void)?
  private var isInitialized: Bool = false
  private let manualUpdate: Bool

  /// Whether the setting is enabled and able to be changed.
  ///
  /// A setting is enabled if it is not loading, has an update function (to update the value in the
  /// SDK), and the setting value has been initialized with a value from the SDK.
  public var isEnabled: Bool {
    return !self.isLoading && self.onUpdate != nil && self.isInitialized
  }

  /// - Parameters:
  ///   - defaultValue: The default value of the setting, this will be displayed even if the setting
  ///     is not initialized.
  ///   - manualUpdate: Whether the value should be updated when the binding value changes.
  ///     - If true, the value will not be updated until `manualRemoteUpdateValue` is called.
  init(defaultValue: T, manualUpdate: Bool = false) {
    self.value = defaultValue
    self.manualUpdate = manualUpdate
  }

  private func remoteUpdateValue(value: T) async {
    guard self.isEnabled else {
      Logger().error("Setting controller is not initialized, cannot update setting.")
      return
    }

    self.isLoading = true
    await self.onUpdate?(value)
    self.isLoading = false
  }

  /// Updates the setting value manually, this takes no action if the setting controller was not
  /// initialized with the `manualUpdate` option, meaning the remote value is not updated when the
  /// binding value changes.
  public func manualRemoteUpdateValue() async {
    guard self.manualUpdate else {
      Logger().error("Setting controller is not configured for manual remote value updates.")
      return
    }
    await self.remoteUpdateValue(value: self.value)
  }

  /// Updates the setting value to a new value. This is typically only called when the remote value
  /// is updated and an update to the UI is needed to match this new value.
  public func updateValue(value: T?) {
    guard let value else {
      Logger().error("Setting controller received nil value, skipping update.")
      return
    }

    self.isInitialized = true

    // Only update the setting value if there is not a current call to the SDK in progress, else we
    // could end up reverting the settings to the previous state, flickering the UI.
    if !self.isLoading {
      self.value = value
    }
  }

}
