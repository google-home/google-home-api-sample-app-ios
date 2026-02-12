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

import CoreFoundation
import Foundation
import GoogleHomeSDK
import SwiftUI

/// A view for listing the history events for all applicable devices within the structure.
///
/// This view includes filters for selecting events by date, device, and event type, and a pull to
/// refresh function to update the latest events within the structure.
public struct HistoryView: View {

  @State private var historyViewModel: HistoryViewModel

  private enum PresentedSheet: Identifiable {
    case datePicker, devicePicker, eventTypePicker
    var id: Self { self }
  }
  @State private var presentedSheet: PresentedSheet? = nil

  private let urlSession: URLSession = URLSession(configuration: .default)

  /// - Parameters:
  ///   - home: The HomeSDK home object.
  ///   - structureID: The structure ID to load history for.
  ///   - objectID: The object ID to filter the history view to, this can be a device, room, or structure.
  public init(home: Home, structureID: String, objectID: String? = nil) {
    self.historyViewModel =
      HistoryViewModel(home: home, structureID: structureID, objectID: objectID)
  }

  public var body: some View {
    VStack {
      List {
        filterButtonsSection
        dailyEventsSection

        if self.historyViewModel.dailyEvents.isEmpty {
          noEventsSection
        } else if !self.historyViewModel.hasNextPage {
          endOfHistorySection
        } else {
          loadingNextPageSection
        }
      }
      .refreshable {
        await self.historyViewModel.refreshEvents()
      }
    }
    .onAppear {
      Task {
        await self.historyViewModel.initialize()
      }
    }
    .sheet(item: $presentedSheet) { sheet in
      switch sheet {
      case .datePicker: self.datePickerSheet
      case .devicePicker: self.devicePickerSheet
      case .eventTypePicker: self.eventTypePickerSheet
      }
    }
  }

  private var filterButtonsSection: some View {
    Section {
      HStack {
        Button("Date") {
          self.presentedSheet = .datePicker
        }.buttonStyle(.bordered)
        if self.historyViewModel.objectID == nil {
          Button("Device") {
            self.presentedSheet = .devicePicker
          }
          .buttonStyle(.bordered)
        }
        Button("Event") {
          self.presentedSheet = .eventTypePicker
        }.buttonStyle(.bordered)
        Spacer()
        if self.historyViewModel.filtersApplied {
          Button("Clear Filters") {
            Task {
              await self.historyViewModel.clearFilters()
            }
          }.buttonStyle(.bordered)
        }
      }
    }
  }

  private var dailyEventsSection: some View {
    ForEach(self.historyViewModel.dailyEvents, id: \.dateString) { dayEvents in
      Section(header: Text(dayEvents.dateString)) {
        ForEach(dayEvents.events, id: \.id) { historyItem in
          HistoryItemView(historyItem: historyItem, urlSession: self.urlSession)
        }
      }
    }
  }

  private var noEventsSection: some View {
    Section {
      HStack {
        Spacer()
        Text("No history events found")
          .font(.body)
          .foregroundColor(.gray)
        Spacer()
      }
    }
  }

  private var endOfHistorySection: some View {
    Section {
      HStack {
        Spacer()
        Text("End of history")
          .font(.body)
          .foregroundColor(.gray)
        Spacer()
      }
    }
  }

  private var loadingNextPageSection: some View {
    Section {
      HStack {
        Spacer()
        ProgressView()
          .onAppear {
            Task {
              await self.historyViewModel.loadNextPage()
            }
          }
        Spacer()
      }
    }
  }

  private var datePickerSheet: some View {
    NavigationStack {
      VStack {
        DatePicker(
          "Start Date",
          selection: $historyViewModel.stagedFilterDateInterval.start,
          in: ...historyViewModel.stagedFilterDateInterval.end,
          displayedComponents: [.date]
        ).padding()
        DatePicker(
          "End Date",
          selection: $historyViewModel.stagedFilterDateInterval.end,
          in: historyViewModel.stagedFilterDateInterval.start...Date(),
          displayedComponents: [.date]
        ).padding()
        Spacer()
      }
      .padding()
      .presentationDetents([.fraction(0.3), .medium, .large])
      .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
          Button("Cancel") {
            self.historyViewModel.cancelStagedDateFilters()
            self.presentedSheet = nil
          }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
          Button("Apply") {
            Task {
              await self.historyViewModel.applyDateFilters()
              self.presentedSheet = nil
            }
          }
        }
      }
    }
  }

  private var devicePickerSheet: some View {
    FilterCheckboxView(
      filterableItems: self.historyViewModel.filterableDevices,
      selectedFilters: self.historyViewModel.stagedDeviceFilters,
      toggleFilter: self.historyViewModel.toggleStagedDeviceSelection,
      stringConverter: \.name,
      applyFilters: {
        Task {
          await self.historyViewModel.applyDeviceFilters()
          self.presentedSheet = nil
        }
      },
      cancelFilters: {
        self.historyViewModel.cancelStagedDeviceFilters()
        self.presentedSheet = nil
      }
    )
  }

  private var eventTypePickerSheet: some View {
    FilterCheckboxView(
      filterableItems: self.historyViewModel.filterableEventTypes,
      selectedFilters: self.historyViewModel.stagedEventTypeFilters,
      toggleFilter: self.historyViewModel.toggleStagedEventTypeSelection,
      stringConverter: \.eventTypeName,
      applyFilters: {
        Task {
          await self.historyViewModel.applyEventTypeFilters()
          self.presentedSheet = nil
        }
      },
      cancelFilters: {
        self.historyViewModel.cancelStagedEventTypeFilters()
        self.presentedSheet = nil
      }
    )
  }
}

/// A view that allows the user to select and deselect filters from a list of items.
public struct FilterCheckboxView<T: Identifiable & Hashable>: View {

  /// The array of items that can be filtered.
  let filterableItems: [T]
  /// The array of items that are currently selected.
  let selectedFilters: Set<T>
  /// Called when the user taps a filter checkbox.
  let toggleFilter: (T) -> Void
  /// Converts the item to a string to display in the list.
  let stringConverter: (T) -> String
  /// Called when the user taps the apply button.
  let applyFilters: () -> Void
  /// Called when the user taps the cancel button.
  let cancelFilters: () -> Void

  public var body: some View {
    NavigationStack {
      List {
        HStack {
          Button("Deselect All") {
            self.toggleAllFilters(false)
          }.buttonStyle(.bordered)
          Spacer()
          Button("Select All") {
            self.toggleAllFilters(true)
          }.buttonStyle(.bordered)
        }
        ForEach(filterableItems) { item in
          HStack {
            Image(systemName: self.selectedFilters.contains(item) ? "checkmark.square" : "square")
            Text(self.stringConverter(item))
          }
          .onTapGesture {
            self.toggleFilter(item)
          }
        }
      }
      .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
          Button("Cancel") {
            self.cancelFilters()
          }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
          Button("Apply") {
            self.applyFilters()
          }
        }
      }
    }
  }

  /// Toggles all filters to the given state.
  func toggleAllFilters(_ selected: Bool) {
    for item in filterableItems {
      if selected && !self.selectedFilters.contains(item) {
        self.toggleFilter(item)
      } else if !selected && self.selectedFilters.contains(item) {
        self.toggleFilter(item)
      }
    }
  }

}

/// A view that displays the details of a single history event.
///
/// This view presents the event's metadata, including the event title, device name, and timestamp.
/// It also handles loading and displaying associated media, such as a static thumbnail and an
/// animated preview clip if available.
public struct HistoryItemView: View {

  private let historyItem: HistoryItemViewModel
  private let urlSession: URLSession

  private let placeholderThumbnail: some View = {
    Image(systemName: "photo")
      .resizable()
      .scaledToFit()
      .frame(width: 40, height: 40)
      .foregroundColor(.gray)
  }()

  /// - Parameters:
  ///   - historyItem: The ViewModel handling the data for the specific history event to display.
  ///   - urlSession: The url used to fetch the WebP image assets.
  public init(historyItem: HistoryItemViewModel, urlSession: URLSession) {
    self.historyItem = historyItem
    self.urlSession = urlSession
  }

  public var body: some View {
    HStack {
      Image(systemName: "video").padding(.trailing, 10)
      VStack(alignment: .leading) {
        Text(self.historyItem.eventTitle).font(.body)
        Text(self.historyItem.deviceName).font(.caption).foregroundColor(.gray)
        Text(self.historyItem.timestampString).font(.caption).foregroundColor(.gray)
      }
      Spacer()
      ZStack {
        AsyncImage(url: URL(string: self.historyItem.thumbnailURL)) { phase in
          switch phase {
          case .empty:
            ProgressView()
              .frame(width: 80, height: 80)
          case .success(let image):
            image
              .resizable()
              .scaledToFill()
              .frame(width: 80, height: 80)
              .clipped()
          case .failure:
            placeholderThumbnail
          @unknown default:
            placeholderThumbnail
          }
        }
        if let previewClipURL = self.historyItem.previewClipURL {
          WebPImageView(url: previewClipURL, urlSession: self.urlSession)
            .frame(width: 80, height: 80)
        }
      }
    }
  }
}
