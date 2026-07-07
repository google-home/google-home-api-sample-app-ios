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

import Combine
import GoogleHomeSDK
import GoogleHomeTypes
import OSLog

/// A view model of area presence state.
@MainActor
public class AreaPresenceStateViewModel: ObservableObject {
  static private let presenceHistoryEventTypeIds = [
    "home.platform.traits.AreaAttendanceStateTrait.AttendanceStateChangeEvent"
  ]
  @Published private(set) var optInStatus: Bool = false

  private let structure: Structure

  public init(currentStructure: Structure) {
    self.structure = currentStructure
  }

  /// Opts in the user to area presence for the given structure.
  public func optInToAreaPresence(optIn: Bool) async {
    do {
      try await self.structure.userStructure.setPresenceOptIn(optIn)
    } catch {
      Logger().error("Failed to \(optIn ? "opt in" : "opt out") to area presence: \(error)")
    }
  }

  /// Monitors the opt in status of the structure.
  public func monitorOptInStatus() async {
    do {
      let stream = await self.structure.userStructure.presenceOptInStatus()
      for try await status in stream {
        self.optInStatus = status
      }
    } catch {
      Logger().error("Failed to get presence opt-in status stream: \(error)")
    }
  }

  /// Deletes the presence history for the structure.
  public func deletePresenceHistory() async {
    do {
      try await self.structure.history.deleteAll(
        for: Self.presenceHistoryEventTypeIds)
      Logger().info("Presence history deleted.")
    } catch {
      Logger().error("Failed to delete presence history: \(error)")
    }
  }
}

extension Google.AreaPresenceStateTrait.PresenceState {
  var text: String? {
    switch self {
    case .presenceStateOccupied:
      return "Home"
    case .presenceStateVacant:
      return "Away"
    default:
      return nil
    }
  }
}
