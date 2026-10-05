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
import Dispatch
import Foundation
import GoogleHomeSDK
import GoogleHomeTypes
import OSLog

class MainViewModel: ObservableObject {

  @Published var home: Home? {
    didSet {
      self.candidatesViewModel = nil
    }
  }

  @Published private(set) var structures: [Structure] = []

  var selectedStructure: Structure? {
    return self.structure(structureID: self.selectedStructureID)
  }

  @Published private(set) var selectedStructureID: String? {
    didSet {
      self.candidatesViewModel = nil
    }
  }
  // The presence state of the selected structure. `nil` unless the user currently consents to
  // presence sensing for that structure.
  @Published private(set) var areaPresenceState: Google.AreaPresenceStateTrait.PresenceState?

  private let selectedStructureStorage = SelectedStructureStorage()

  private var cancellables: Set<AnyCancellable> = []
  private var structuresCancellable: AnyCancellable?
  private var candidatesViewModel: CandidatesViewModel?
  private var areaPresenceStateCancellable: AnyCancellable?
  private var presenceConsentTask: Task<Void, Never>?
  // The most recent value pushed by the trait subscription, before consent gating is applied.
  private var lastReportedPresenceState: Google.AreaPresenceStateTrait.PresenceState?
  // Whether the user consents to presence sensing for the selected structure.
  private var isPresenceSensingConsented = false

  // MARK: - Initialization

  init(homePublisher: Published<Home?>.Publisher) {
    homePublisher.sink { [weak self] home in
      self?.home = home
      self?.fetchStructures()
    }.store(in: &cancellables)

    $structures.sink { [weak self] newStructures in
      guard let self, !newStructures.isEmpty else { return }
      // Read the previously user-selected structure ID from UserDefaults to find and display the
      // corresponding structure.
      if let selectedStructureID =
        self.selectedStructureStorage.read(identifier: self.home?.identifier),
        let selectedStructure = newStructures.first(where: { $0.id == selectedStructureID })
      {
        self.selectedStructureID = selectedStructure.id
        return
      }
      // If the stored selected structure can't be found (or there is no stored selection), default
      // to arbitrarily showing the first structure in the array.
      self.selectedStructureID = newStructures.first?.id
    }.store(in: &cancellables)

    Publishers.CombineLatest($selectedStructureID, $structures)
      .removeDuplicates { oldTuple, newTuple in
        let (oldSelectedID, oldStructures) = oldTuple
        let (newSelectedID, newStructures) = newTuple

        let isSameSelection = oldSelectedID == newSelectedID
        let isSameStructureList = oldStructures.map(\.id) == newStructures.map(\.id)

        return isSameSelection && isSameStructureList
      }
      .sink { [weak self] structureID, structures in
        self?.handleSelectedStructureChange(structureID: structureID, structures: structures)
      }
      .store(in: &cancellables)
  }

  deinit {
    // Prevent an idle consent stream from leaking the suspended task.
    self.presenceConsentTask?.cancel()
  }

  /// Handles resetting and re-subscribing when the selected structure changes.
  private func handleSelectedStructureChange(structureID: String?, structures: [Structure]) {
    self.areaPresenceStateCancellable?.cancel()
    self.presenceConsentTask?.cancel()
    self.presenceConsentTask = nil
    self.lastReportedPresenceState = nil
    self.isPresenceSensingConsented = false
    self.areaPresenceState = nil

    guard let structureID = structureID,
      let structure = structures.first(where: { $0.id == structureID })
    else {
      Logger().info("MainViewModel: No selected structure or structures not loaded yet.")
      return
    }

    self.monitorPresenceSensingConsent(for: structure)
    self.subscribeToAreaPresence(for: structure)
  }

  /// Monitors whether the user consents to presence sensing for the given structure.
  ///
  /// - Parameter structure: The structure whose presence sensing consent is observed.
  private func monitorPresenceSensingConsent(for structure: Structure) {
    let permissions = structure.permissions
    // The trait subscription keeps delivering presence updates for as long as the app holds the
    // structure scope, so consent is what determines whether that state may be presented. Watching
    // the stream lets a revocation take effect immediately instead of on the next launch.
    self.presenceConsentTask = Task { [weak self] in
      do {
        let consentStates = permissions.featureConsentStateStream(features: [.presenceSensing])
        for try await consentState in consentStates {
          guard let self, !Task.isCancelled else { return }
          await self.updatePresenceSensingConsent(
            isConsented: consentState[.presenceSensing] == .consented)
        }
      } catch {
        guard let self, !Task.isCancelled else { return }
        Logger().error("Presence sensing consent stream failed: \(error)")
        // Withhold the presence state rather than risk displaying it without valid consent.
        await self.updatePresenceSensingConsent(isConsented: false)
      }
    }
  }

  /// Subscribes to the AreaPresenceStateTrait for the given structure.
  private func subscribeToAreaPresence(for structure: Structure) {
    self.areaPresenceStateCancellable =
      structure
      .traits
      .subscribe(Google.AreaPresenceStateTrait.self)
      .receive(on: DispatchQueue.main)
      .sink(
        receiveCompletion: { [weak self] completion in
          guard case .failure(let error) = completion else { return }
          Logger().error("AreaPresenceStateTrait subscription failed: \(error)")
          self?.lastReportedPresenceState = nil
          self?.applyPresenceConsentGate()
        },
        receiveValue: { [weak self] trait in
          self?.lastReportedPresenceState = trait.attributes.presenceState
          self?.applyPresenceConsentGate()
        })
  }

  /// Records the latest presence sensing consent status and re-applies the gate.
  @MainActor
  private func updatePresenceSensingConsent(isConsented: Bool) {
    self.isPresenceSensingConsented = isConsented
    self.applyPresenceConsentGate()
  }

  /// Publishes the reported presence state only while presence sensing consent is granted.
  private func applyPresenceConsentGate() {
    self.areaPresenceState = self.isPresenceSensingConsented ? self.lastReportedPresenceState : nil
  }

  func structure(structureID: String?) -> Structure? {
    guard let structureID else { return nil }
    return structures.first { $0.id == structureID }
  }

  @MainActor
  func structureViewModel(structureID: String?) -> StructureViewModel? {
    guard let structureID else { return nil }

    guard let home else { return nil }
    let newViewModel = StructureViewModel(home: home, structureID: structureID)
    return newViewModel
  }

  @MainActor
  public func getCandidatesViewModel() -> CandidatesViewModel? {
    // If the there's no candidatesViewMode, create one, otherwise return the existing one
    if self.candidatesViewModel == nil {
      guard let home else { return nil }
      guard let selectedStructure = self.selectedStructure else { return nil }
      self.candidatesViewModel = CandidatesViewModel(home: home, structure: selectedStructure)
    }
    return self.candidatesViewModel
  }

  /// Updates the current selected structure and stores the information in persistent storage.
  func updateSelectedStructureID(_ selectedStructureID: String) {
    /// Reset the candidateViewModel
    self.candidatesViewModel = nil
    self.selectedStructureID = selectedStructureID
    self.selectedStructureStorage
      .update(structureID: selectedStructureID, identifier: self.home?.identifier)
  }

  // MARK: - Private

  /// Fetches the structures for the current home.
  private func fetchStructures() {
    guard let home = self.home else {
      Logger().info("Removing structure data.")
      self.structuresCancellable = nil
      self.structures = []
      self.selectedStructureID = nil
      return
    }

    Logger().info("Loading structure data for Home(\(home.identifier)).")
    self.structures = []
    self.selectedStructureID = nil

    /// batched() returns a publisher, and assign() to publisher structures
    self.structuresCancellable =
      home
      .structures()
      .batched()
      .receive(on: DispatchQueue.main)
      .map { Array($0) }
      .catch {
        Logger().error("Failed to load structures: \($0)")
        return Just([Structure]())
      }
      .assign(to: \.structures, on: self)
  }
}
