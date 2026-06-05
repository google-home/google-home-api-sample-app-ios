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

import Foundation
import GoogleHomeSDK
import OSLog
import Observation

/// A view model that manages the retrieval and state of home briefs for a specific structure.
@Observable
@MainActor
public class HomeBriefsViewModel {

  private let structureID: String
  private let home: Home
  private var structure: Structure?

  public private(set) var hasMoreBriefs = false
  public private(set) var isLoadingMoreBriefs = false
  public private(set) var briefs: [HomeBrief] = []

  private var briefsIterator: PagedHomeBriefsStream.AsyncIterator?
  private let fetchBatchSize: UInt = 10

  /// Initializes the view model with a home instance and structure ID.
  /// - Parameters:
  ///   - home: The `Home` instance.
  ///   - structureID: The ID of the structure to fetch briefs for.
  public init(home: Home, structureID: String) {
    self.home = home
    self.structureID = structureID
  }

  /// Initializes the view model by fetching the structure and loading the initial batch of briefs.
  public func initialize() async {
    do {
      self.structure =
        try await self.home.structures().list().first(where: { $0.id == self.structureID })
      await self.loadInitialBriefs()
    } catch {
      Logger().error("Error initializing structure or briefs: \(error)")
      self.briefs = []
    }
  }

  /// Initializes a new stream and loads the most recent batch of historical home briefs.
  public func loadInitialBriefs() async {
    guard let structure = self.structure else {
      Logger().error("Structure not initialized")
      return
    }

    self.hasMoreBriefs = true
    self.briefs = []
    do {
      let controller = try await structure.homeBriefs
      let stream = try controller.stream(pageSize: self.fetchBatchSize)
      self.briefsIterator = stream.makeAsyncIterator()
      await self.loadMoreHistoricalBriefs()
    } catch {
      Logger().error("Error loading initial briefs: \(error)")
    }
  }

  /// Fetches the next batch of historical briefs from the stream if available.
  public func loadMoreHistoricalBriefs() async {
    guard !self.isLoadingMoreBriefs, self.hasMoreBriefs else {
      return
    }

    self.isLoadingMoreBriefs = true
    defer { self.isLoadingMoreBriefs = false }

    do {
      if let batch = try await self.briefsIterator?.next() {
        let existingIDs = Set(self.briefs.map(\.id))
        let newBriefs = batch.filter { !existingIDs.contains($0.id) }
        self.briefs.append(contentsOf: newBriefs)
      } else {
        self.hasMoreBriefs = false
      }
    } catch {
      Logger().error("Error getting next briefs batch: \(error)")
    }
  }
}
