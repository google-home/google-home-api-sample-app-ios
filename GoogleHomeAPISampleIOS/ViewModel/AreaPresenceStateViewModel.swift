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
  @Published private(set) var areaPresenceState: Google.AreaPresenceStateTrait.PresenceState? = nil

  private let structure: Structure
  private var cancellable: AnyCancellable?

  public init(currentStructure: Structure) {
    self.structure = currentStructure
  }

  /// Opts in the user to area presence for the given structure.
  ///
  /// - Parameter optIn: `true` to participate in presence detection; `false` to opt out.
  /// - Note: Controls whether this user's device contributes to structure Home/Away determination.
  public func optInToAreaPresence(optIn: Bool) async {
    do {
      try await self.structure.userStructure.setPresenceOptIn(optIn)
    } catch {
      Logger().error("Failed to \(optIn ? "opt in" : "opt out") to area presence: \(error)")
    }
  }

  /// Monitors the opt in status of the structure.
  ///
  /// - Note: Runs as a structured child of the SwiftUI `.task` that calls it,
  ///   so it is automatically cancelled when the view disappears.
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
  ///
  /// - Note: Deletes history targeted at `AreaAttendanceStateTrait` event type IDs.
  public func deletePresenceHistory() async {
    do {
      try await self.structure.history.deleteAll(
        for: Self.presenceHistoryEventTypeIds)
      Logger().info("Presence history deleted.")
    } catch {
      Logger().error("Failed to delete presence history: \(error)")
    }
  }

  /// Subscribes to real-time area presence state updates.
  ///
  /// - Note: Observes structure occupancy (`Home`/`Away`) via Combine on the main thread.
  public func monitorAreaPresenceState() {
    self.cancellable?.cancel()
    self.cancellable = structure.traits
      .subscribe(Google.AreaPresenceStateTrait.self)
      .receive(on: DispatchQueue.main)
      .sink(
        receiveCompletion: { [weak self] completion in
          if case .failure(let error) = completion {
            Logger().error("AreaPresenceStateTrait subscription failed: \(error)")
            self?.areaPresenceState = nil
          }
        },
        receiveValue: { [weak self] trait in
          self?.areaPresenceState = trait.attributes.presenceState
        }
      )
  }

  deinit {
    cancellable?.cancel()
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
