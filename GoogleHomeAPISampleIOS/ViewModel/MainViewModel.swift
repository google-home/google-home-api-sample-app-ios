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
import OSLog

class MainViewModel: ObservableObject {

  @Published var home: Home?

  @Published private(set) var structures: [Structure] = []

  var selectedStructure: Structure? {
    return self.structure(structureID: self.selectedStructureID)
  }

  @Published private(set) var selectedStructureID: String?

  private let selectedStructureStorage = SelectedStructureStorage()

  private var cancellables: Set<AnyCancellable> = []
  private var structuresCancellable: AnyCancellable?

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
  }

  func structure(structureID: String?) -> Structure? {
    guard let structureID else { return nil }
    return structures.first { $0.id == structureID }
  }

  func structureViewModel(structureID: String?) -> StructureViewModel? {
    guard let structureID else { return nil }

    guard let home else { return nil }
    let newViewModel = StructureViewModel(home: home, structureID: structureID)
    return newViewModel
  }

  /// Updates the current selected structure and stores the information in persistent storage.
  func updateSelectedStructureID(_ selectedStructureID: String) {
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
