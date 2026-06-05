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

import Observation

/// A lightweight, non-persistent view model that manages the active mutable state
/// of the ActivityZoneEditView during modifications.
@Observable
@MainActor
public class ActivityZoneEditViewModel {

  /// The draft copy of the zone being edited. Changes are local and only persistent once the user taps 'Save'.
  public var zone: ActivityZone

  /// Flag representing if the current zone has never been synchronized with the GHP cloud before.
  public let isNewZone: Bool

  /// Flag representing if this is the default background zone.
  public let isDefaultZone: Bool

  /// Initializes the edit view model with the reference zone.
  ///
  /// - Parameter zone: The active zone being configured.
  public init(zone: ActivityZone) {
    self.zone = zone
    self.isNewZone = zone.id == nil
    self.isDefaultZone = zone.isDefaultZone
  }
}
