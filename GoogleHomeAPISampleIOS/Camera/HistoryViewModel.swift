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
import GoogleHomeTypes
import OSLog
import Observation

/// A ViewModel for handling different event types, applying filters, and event queries.
@Observable
@MainActor
public class HistoryViewModel {

  /// A list of Trait Type Identifiers that should be ignored (filtered out) from the history log.
  /// 3P partners can easily append custom/noisy Type Identifiers here.
  public static var ignoredTypeIdentifiers: Set<String> = [
    "clusters.0204",      // Thermostat UI configuration
    "clusters.fc42"       // Google/Nest private cluster
  ]

  private let home: Home
  private let structureID: String
  private var structure: Structure?
  /// The object ID the history view is filtered to, if this is non-nil, the history will not be
  /// filtered.
  public let objectID: String?
  /// Whether the view model is currently loading the next page of events.
  public private(set) var loadingNextPage = false
  /// List of history sections to display in the UI, each section is a day of events.
  public private(set) var dailyEvents: [HistorySection] = []
  /// Whether there are more events to load.
  public private(set) var hasNextPage = false

  // MARK: - Filter properties

  /// The dates used for the date filter.
  private var appliedFilterDateInterval: DateInterval?

  /// The dates displayed for the date filter.
  public var stagedFilterDateInterval = DateInterval(start: Date(), end: Date())

  /// The list of devices in the structure, containing booleans for if they are selected.
  public private(set) var filterableDevices: [DeviceFilterSelection] = []
  /// The list of devices that are currently staged for the device filter.
  public private(set) var stagedDeviceFilters: Set<DeviceFilterSelection> = []
  /// The list of device filters that are currently applied to the history query.
  private var appliedDeviceFilters: Set<DeviceFilterSelection>?

  /// The list of possible event types that can be filtered on.
  public let eventTypeFilters: Set<EventType> = [
    EventType(.motion, "Motion", "EVENT_TYPE_MOTION"),
    EventType(.person, "Person", "EVENT_TYPE_PERSON"),
    EventType(.doorbell, "Doorbell Pressed", "EVENT_TYPE_DOORBELL"),
    EventType(.packageDelivered, "Package Delivered", "EVENT_TYPE_PACKAGE_DELIVERED"),
    EventType(.packageRetrieved, "Package Retrieved", "EVENT_TYPE_PACKAGE_RETRIEVED"),
    EventType(.packageInTransit, "Package In Transit", "EVENT_TYPE_PACKAGE_IN_TRANSIT"),
    EventType(.animal, "Animal", "EVENT_TYPE_ANIMAL"),
    EventType(.vehicle, "Vehicle", "EVENT_TYPE_VEHICLE"),
    EventType(.smokeAlarm, "Smoke Alarm", "EVENT_TYPE_SMOKE_ALARM"),
    EventType(.coAlarm, "CO Alarm", "EVENT_TYPE_CO_ALARM"),
    EventType(.dogBark, "Dog Bark", "EVENT_TYPE_DOG_BARK"),
    EventType(.personTalking, "Person Talking", "EVENT_TYPE_PERSON_TALKING"),
    EventType(.glassBreak, "Glass Break", "EVENT_TYPE_GLASS_BREAK"),
    EventType(.garageDoorOpened, "Garage Door Opened", "EVENT_TYPE_GARAGE_DOOR_OPENED"),
    EventType(.garageDoorClosed, "Garage Door Closed", "EVENT_TYPE_GARAGE_DOOR_CLOSED"),
    EventType(.familiarFace, "Familiar Face", "EVENT_TYPE_FAMILIAR_FACE"),
    EventType(.unfamiliarFace, "Unfamiliar Face", "EVENT_TYPE_UNFAMILIAR_FACE"),
  ]

  /// The list of event types that are available for filtering history.
  public private(set) var filterableEventTypes: [EventType] = []
  /// The list of event types that are currently staged for the event type filter.
  public private(set) var stagedEventTypeFilters: Set<EventType> = []
  /// The list of event types that are currently applied to the history query.
  private var appliedEventTypeFilters: Set<EventType>?

  /// Whether any filters are currently applied
  ///
  /// This should take into account all individual filter types.
  public var filtersApplied: Bool {
    return self.appliedFilterDateInterval != nil
      || self.appliedDeviceFilters != nil
      || self.appliedEventTypeFilters != nil
  }

  /// The priority list of event types that will determine what is shown in the UI, lower numbered
  /// priorities are more significant.
  private static let eventTypePriorityList: [Google.CameraHistoryTrait.EventType] = [
    .smokeAlarm,
    .coAlarm,
    .glassBreak,
    .packageDelivered,
    .packageRetrieved,
    .packageInTransit,
    .familiarFace,
    .unfamiliarFace,
    .doorbell,
    .person,
    .garageDoorOpened,
    .garageDoorClosed,
    .animal,
    .vehicle,
    .motion,
    .dogBark,
    .personTalking,
    .unknown,
  ]

  /// Pre-computed map for O(1) priority lookups. Initialized once on first use.
  private static let eventTypePriorityMap: [Google.CameraHistoryTrait.EventType: Int] = {
    var map = [Google.CameraHistoryTrait.EventType: Int]()
    for (index, eventType) in eventTypePriorityList.enumerated() {
      if map[eventType] == nil {
        map[eventType] = index
      }
    }
    return map
  }()

  /// Returns the priority of the given event type. Lower numbered priorities are more significant.
  private func priority(for eventType: Google.CameraHistoryTrait.EventType) -> Int {
    return HistoryViewModel.eventTypePriorityMap[eventType] ?? Int.max
  }

  // MARK: - Properties

  private var historyIterator: PagedHistoryStream.AsyncIterator?

  private let historyItemVisitor: HistoryItemVisitor<HistoryItemViewModel>

  /// Helper date formatter for formatting the history item timestamps to strings for history items.
  private static let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "dd/MM/yyyy - HH:mm"
    return formatter
  }()

  /// Formatter for section headers (e.g., "Mon, Oct 26")
  private static let sectionDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "E, MMM d"
    return formatter
  }()

  private let pageSize: UInt = 10

  /// - Parameters:
  ///   - home: The HomeSDK home object.
  ///   - structureID: The structure ID to load history for.
  ///   - objectID: The object ID to filter the history view to, this can be a device, room, or structure.
  public init(home: Home, structureID: String, objectID: String? = nil) {
    self.objectID = objectID
    self.home = home
    self.structureID = structureID
    self.historyItemVisitor = HistoryItemVisitor<HistoryItemViewModel>()
    self.historyItemVisitor.registerDefault(self.handleUnknownEvent)
    self.historyItemVisitor.register(
      Google.CameraHistoryTrait.HistoryItemEvent.self,
      handler: self.handleCameraEvent
    )
    // Register Matter Door Lock events for SDK resolution.
    self.historyItemVisitor.register(
      StateChangeEvent<Matter.DoorLockTrait>.self,
      handler: self.handleLockStateChange
    )
    self.historyItemVisitor.register(
      Matter.DoorLockTrait.LockOperationEvent.self,
      handler: self.handleLockOperationEvent
    )
    self.historyItemVisitor.register(
      Matter.DoorLockTrait.DoorLockAlarmEvent.self,
      handler: self.handleDoorLockAlarmEvent
    )
    // Register Matter Thermostat events for SDK resolution.
    self.historyItemVisitor.register(
      StateChangeEvent<Matter.ThermostatTrait>.self,
      handler: self.handleThermostatStateChange
    )

    // Register Relative Humidity Measurement events.
    self.historyItemVisitor.register(
      StateChangeEvent<Matter.RelativeHumidityMeasurementTrait>.self,
      handler: self.handleRelativeHumidityMeasurementStateChange
    )
    // Register Matter Power Source events to discard them from the log.
    self.historyItemVisitor.register(
      StateChangeEvent<Matter.PowerSourceTrait>.self,
      handler: self.handlePowerSourceStateChange
    )
    // Register Connectivity events to discard them from the log.
    self.historyItemVisitor.register(
      StateChangeEvent<Google.ConnectivityTrait>.self,
      handler: self.handleConnectivityStateChange
    )
  }

  /// Initializes the structure object and then initializes the events array.
  ///
  /// This function should be called when the view appears.
  public func initialize() async {
    do {
      self.structure =
        try await self.home.structures().list().first(where: { $0.id == self.structureID })
      await self.initializeDeviceList()
      await self.refreshEvents()
      await self.initializeEventTypeList()
    } catch {
      Logger().error("Error initializing structure or events: \(error)")
      self.dailyEvents = []
    }
  }

  /// Initializes the list of devices in the structure that are available for filtering history.
  private func initializeDeviceList() async {
    do {
      self.filterableDevices = try await self.home.devices().list().filter {
        $0.structureID == self.structureID
      }.map { DeviceFilterSelection(id: $0.id, name: $0.name) }
    } catch {
      Logger().error("Error initializing device list: \(error)")
      self.filterableDevices = []
    }
  }

  /// Initializes the list of event types that are available for filtering history.
  private func initializeEventTypeList() async {
    guard let structure = self.structure else {
      Logger().error("Structure not initialized")
      return
    }
    self.filterableEventTypes = []
    do {
      let filters = try await structure.history.fetchApplicableFilters()
      for filter in filters {
        for event in filter.supportedValues {
          if let eventTypeFilter =
            self.eventTypeFilters.first(where: { $0.filterEventTypeString == event })
          {
            self.filterableEventTypes.append(eventTypeFilter)
          }
        }
      }
    } catch {
      Logger().error("Error initializing event type list: \(error)")
    }
  }

  /// Toggles the staged selection state of the device with the given ID.
  public func toggleStagedDeviceSelection(_ device: DeviceFilterSelection) {
    if self.stagedDeviceFilters.contains(device) {
      self.stagedDeviceFilters.remove(device)
    } else {
      self.stagedDeviceFilters.insert(device)
    }
  }

  /// Cancels the staged device filters and resets the staged device list to the applied device
  /// list.
  public func cancelStagedDeviceFilters() {
    self.stagedDeviceFilters = self.appliedDeviceFilters ?? []
  }

  /// Applies the device filters based on the isSelected state of the devices and reloads the events.
  public func applyDeviceFilters() async {
    self.appliedDeviceFilters = self.stagedDeviceFilters
    await self.refreshEvents()
  }

  /// Initializes the events array by generating the history stream and then loading the first page
  /// of events.
  public func refreshEvents() async {
    guard let structure = self.structure else {
      Logger().error("Structure not initialized")
      return
    }

    self.hasNextPage = true
    self.dailyEvents = []
    do {
      var historyQuery = try await structure.history.query()
      if let objectID = self.objectID {
        historyQuery = historyQuery.objects([objectID])
      } else if let appliedDeviceFilters = self.appliedDeviceFilters {
        historyQuery = historyQuery.objects(appliedDeviceFilters.map { $0.id })
      }
      if let appliedEventTypeFilters = self.appliedEventTypeFilters {
        for eventType in appliedEventTypeFilters {
          historyQuery = historyQuery.cameraEvents(eventType.filterEventTypeString)
        }
      }
      if let filterDateInterval = self.appliedFilterDateInterval {

        let calendar = Calendar.current

        // Ensure the dateTimes are inclusive of the entire day by including the start of the day
        // for the start date and the end of the day for the end date (start of the next day).
        let lowerBoundDate = calendar.startOfDay(for: filterDateInterval.start)
        let upperBoundDate = calendar.date(
          byAdding: .day,
          value: 1,
          to: calendar.startOfDay(for: filterDateInterval.end)
        )

        historyQuery = historyQuery.date(
          start: lowerBoundDate,
          end: upperBoundDate ?? filterDateInterval.end
        )
      }
      let historyStream = try historyQuery.execute(pageSize: self.pageSize)
      self.historyIterator = historyStream.makeAsyncIterator()
      await self.loadNextPage()
    } catch {
      Logger().error("Error: \(error)")
    }
  }

  /// Loads the next page of events into the events array.
  /// If this function is called without calling refreshEvents() first, it will return early.
  public func loadNextPage() async {
    guard let historyIterator = self.historyIterator, !self.loadingNextPage, self.hasNextPage
    else { return }

    let calendar = Calendar.current

    self.loadingNextPage = true
    defer { self.loadingNextPage = false }
    do {
      var page = try await historyIterator.next()
      var newEvents = try self.historyItemVisitor.collect(page?.items ?? [])
      var fetchCount = 0

      while newEvents.isEmpty && fetchCount < 5 {
        guard let currentPage = page, !currentPage.items.isEmpty else {
          self.hasNextPage = false
          break
        }
        fetchCount += 1
        page = try await historyIterator.next()
        newEvents = try self.historyItemVisitor.collect(page?.items ?? [])
      }

      if let page = page {
        guard !newEvents.isEmpty || !page.items.isEmpty else {
          self.hasNextPage = false
          return
        }

        for event in newEvents {
          let eventDate = event.timestamp
          let dateString: String
          if calendar.isDateInToday(eventDate) {
            dateString = "Today"
          } else if calendar.isDateInYesterday(eventDate) {
            dateString = "Yesterday"
          } else {
            dateString = HistoryViewModel.sectionDateFormatter.string(from: eventDate)
          }

          let sectionIndex = self.dailyEvents.firstIndex { $0.dateString == dateString }
          if let sectionIndex = sectionIndex {
            self.dailyEvents[sectionIndex].events.append(event)
          } else {
            self.dailyEvents.append(
              HistorySection(
                dateString: dateString,
                date: eventDate,
                events: [event]
              )
            )
          }
        }
      } else {
        self.hasNextPage = false
      }
    } catch {
      Logger().error("Error getting history page: \(error)")
    }
  }

  private func resolveDeviceName(for source: HistoryItem.Source) -> String {
    let objectID = source.objectID
    if let match = self.filterableDevices.first(where: { $0.id == objectID }) {
      return match.name
    }
    return source.deviceName
  }

  /// Handles an unknown event type by returning a HistoryItemViewModel with the default event
  /// title.
  private func handleUnknownEvent(historyItem: HistoryItem) -> HistoryItemViewModel? {
    let timestampString = HistoryViewModel.dateFormatter.string(from: historyItem.timestamp)
    let deviceName = self.resolveDeviceName(for: historyItem.source)

    let typeIdentifier: String
    switch historyItem.value {
    case .event(let data):
      typeIdentifier = data.id
    case .stateChange(let change):
      typeIdentifier = change.typeID
    @unknown default:
      typeIdentifier = ""
    }

    // Filter out ignored Type Identifiers
    if HistoryViewModel.ignoredTypeIdentifiers.contains(where: { typeIdentifier.contains($0) }) {
      return nil
    }

    let eventTitle = "Unknown event"
    return HistoryItemViewModel(
      id: historyItem.id,
      eventTitle: eventTitle,
      captionTitle: nil,
      deviceName: deviceName,
      timestampString: timestampString,
      thumbnailURL: "",
      previewClipURL: nil,
      historicalPlaybackURL: nil,
      timestamp: historyItem.timestamp,
      iconName: "questionmark.circle",
      eventTypeIdentifier: "Unknown"
    )
  }

  /// Handles a camera event type by returning a HistoryItemViewModel with the camera event title.
  /// Will utilize the camera event type string map to get the event tile. If the event type is not
  /// found, it will return "Unknown camera event".
  private func displayTitle(for eventType: Google.CameraHistoryTrait.EventType) -> String {
    switch eventType {
    case .motion: return "Motion"
    case .person: return "Person"
    case .doorbell: return "Doorbell Pressed"
    case .packageDelivered: return "Package Delivered"
    case .packageRetrieved: return "Package Retrieved"
    case .packageInTransit: return "Package In Transit"
    case .animal: return "Animal"
    case .vehicle: return "Vehicle"
    case .smokeAlarm: return "Smoke Alarm"
    case .coAlarm: return "CO Alarm"
    case .dogBark: return "Dog Bark"
    case .personTalking: return "Person Talking"
    case .glassBreak: return "Glass Break"
    case .garageDoorOpened: return "Garage Door Opened"
    case .garageDoorClosed: return "Garage Door Closed"
    case .familiarFace: return "Familiar Face"
    case .unfamiliarFace: return "Unfamiliar Face"
    default: return "Unknown camera event"
    }
  }

  private func handleCameraEvent(
    _ cameraEvent: Google.CameraHistoryTrait.HistoryItemEvent,
    historyItem: HistoryItem
  ) -> HistoryItemViewModel {
    let timestamp = HistoryViewModel.dateFormatter.string(from: historyItem.timestamp)
    let deviceName = self.resolveDeviceName(for: historyItem.source)

    let eventTypeFilters = self.appliedEventTypeFilters ?? self.eventTypeFilters

    // When multiple event types are present within a single history event, the most significant one
    // is displayed.
    let eventTypes = Set(cameraEvent.payload.eventTracks?.flatMap { $0.eventTypes } ?? [])
    let bestEventType = eventTypes.min(by: { self.priority(for: $0) < self.priority(for: $1) })

    let eventTitle: String

    // When a short AI caption is available, use it as the event title.
    if let shortCaption = cameraEvent.payload.shortCaption {
      eventTitle = shortCaption
    } else if let bestEventType = bestEventType {
      let baseTitle = self.displayTitle(for: bestEventType)

      // If the event is a familiar face, add the face name to the title if it is available.
      if bestEventType == .familiarFace,
        let familiarFaceTrack = cameraEvent.payload.eventTracks?.first(where: {
          $0.eventTypes.contains(.familiarFace) && !$0.face.name.isEmpty
        })
      {
        eventTitle = "\(baseTitle) (\(familiarFaceTrack.face.name))"
      } else {
        eventTitle = baseTitle
      }
    } else {
      eventTitle = "Unknown camera event"
    }
    // Show the long AI caption when applicable.
    let captionTitle = cameraEvent.payload.longCaption

    let thumbnailURL = cameraEvent.payload.mediaUrl?.thumbnail_url ?? ""

    var previewClipURL: URL? = nil
    if let previewURL = cameraEvent.payload.mediaUrl?.preview_url,
      var components = URLComponents(string: previewURL)
    {
      var queryItems = components.queryItems ?? []
      queryItems.append(URLQueryItem(name: "format", value: "webp"))
      queryItems.append(URLQueryItem(name: "width", value: "80"))
      components.queryItems = queryItems
      previewClipURL = components.url
    }

    var historicalPlaybackURL: URL? = nil
    if let historyPlaybackURLString = cameraEvent.payload.mediaUrl?.hls_master_playlist_url {
      historicalPlaybackURL = URL(string: historyPlaybackURLString)
    }

    return HistoryItemViewModel(
      id: historyItem.id,
      eventTitle: eventTitle,
      captionTitle: captionTitle,
      deviceName: deviceName,
      timestampString: timestamp,
      thumbnailURL: thumbnailURL,
      previewClipURL: previewClipURL,
      historicalPlaybackURL: historicalPlaybackURL,
      timestamp: historyItem.timestamp,
      iconName: "video",
      eventTypeIdentifier: "Camera"
    )
  }

  /// Applies the staged date filters and reloads the events.
  public func applyDateFilters() async {
    self.appliedFilterDateInterval = self.stagedFilterDateInterval
    await self.refreshEvents()
  }

  /// Cancels the staged date filters and resets the staged date interval to the applied filter or
  /// the default date interval if no filters are applied.
  public func cancelStagedDateFilters() {
    self.stagedFilterDateInterval =
      self.appliedFilterDateInterval ?? DateInterval(start: Date(), end: Date())
  }

  /// Toggles the staged selection state of the event type with the given string.
  public func toggleStagedEventTypeSelection(_ eventType: EventType) {
    if self.stagedEventTypeFilters.contains(eventType) {
      self.stagedEventTypeFilters.remove(eventType)
    } else {
      self.stagedEventTypeFilters.insert(eventType)
    }
  }

  /// Applies the staged event type filters and reloads the events.
  public func applyEventTypeFilters() async {
    self.appliedEventTypeFilters = self.stagedEventTypeFilters
    await self.refreshEvents()
  }

  /// Cancels the staged event type filters and resets the staged event type filters to the applied
  /// filter or the empty array if no filters are applied.
  public func cancelStagedEventTypeFilters() {
    self.stagedEventTypeFilters = self.appliedEventTypeFilters ?? []
  }

  /// Clears all applied history filters and reloads the events.
  public func clearFilters() async {
    self.appliedFilterDateInterval = nil
    self.cancelStagedDateFilters()
    self.appliedEventTypeFilters = nil
    self.cancelStagedEventTypeFilters()
    self.appliedDeviceFilters = nil
    self.cancelStagedDeviceFilters()
    await self.refreshEvents()
  }

  private func handleLockStateChange(
    _ stateChange: StateChangeEvent<Matter.DoorLockTrait>,
    historyItem: HistoryItem
  ) -> HistoryItemViewModel {
    let timestampString = HistoryViewModel.dateFormatter.string(from: historyItem.timestamp)
    let deviceName = self.resolveDeviceName(for: historyItem.source)

    var stateString = "changed state"
    if let lockState = stateChange.newValue.attributes.lockState {
      switch lockState {
      case .locked:
        stateString = "locked"
      case .unlocked:
        stateString = "unlocked"
      case .notFullyLocked:
        stateString = "not fully locked"
      case .unlatched:
        stateString = "unlatched"
      default:
        stateString = "changed state"
      }
    }

    return HistoryItemViewModel(
      id: historyItem.id,
      eventTitle: "Door \(stateString)",
      captionTitle: nil,
      deviceName: deviceName,
      timestampString: timestampString,
      thumbnailURL: "",
      previewClipURL: nil,
      historicalPlaybackURL: nil,
      timestamp: historyItem.timestamp,
      iconName: "lock",
      eventTypeIdentifier: "LockStateChange"
    )
  }

  private func handleLockOperationEvent(
    _ event: Matter.DoorLockTrait.LockOperationEvent,
    historyItem: HistoryItem
  ) -> HistoryItemViewModel {
    let title =
      "Door Lock Operation \"\(event.payload.lockOperationType.text)\" succeeded"
    let longTitle =
      "Door Lock Operation \"\(event.payload.lockOperationType.text)\" succeeded. Operation source: \(event.payload.operationSource.text)"

    return HistoryItemViewModel(
      id: historyItem.id,
      eventTitle: title,
      captionTitle: longTitle,
      deviceName: self.resolveDeviceName(for: historyItem.source),
      timestampString: HistoryViewModel.dateFormatter.string(from: historyItem.timestamp),
      thumbnailURL: "",
      previewClipURL: nil,
      historicalPlaybackURL: nil,
      timestamp: historyItem.timestamp,
      iconName: "lock",
      eventTypeIdentifier: "LockOperation"
    )
  }

  private func handleDoorLockAlarmEvent(
    _ event: Matter.DoorLockTrait.DoorLockAlarmEvent,
    historyItem: HistoryItem
  ) -> HistoryItemViewModel {
    let title = "Door Lock Alarm: \(event.payload.alarmCode.text)"

    return HistoryItemViewModel(
      id: historyItem.id,
      eventTitle: title,
      captionTitle: nil,
      deviceName: self.resolveDeviceName(for: historyItem.source),
      timestampString: HistoryViewModel.dateFormatter.string(from: historyItem.timestamp),
      thumbnailURL: "",
      previewClipURL: nil,
      historicalPlaybackURL: nil,
      timestamp: historyItem.timestamp,
      iconName: "exclamationmark.triangle",
      eventTypeIdentifier: "LockAlarm"
    )
  }

  private func handleThermostatStateChange(
    _ event: StateChangeEvent<Matter.ThermostatTrait>,
    historyItem: HistoryItem
  ) -> HistoryItemViewModel {
    let currentAttributes = event.newValue.attributes
    let deviceName = self.resolveDeviceName(for: historyItem.source)

    let systemMode = currentAttributes.systemMode.text
    let localTemperature = currentAttributes.localTemperature.map {
      String(format: "%.1f", Double($0) / 100.0)
    } ?? "N/A"

    let eventTitle = "\(deviceName) is \(systemMode) (\(localTemperature)°C)"

    var captionTitle: String? = nil
    if systemMode == "Cool", let coolingSetpoint = currentAttributes.occupiedCoolingSetpoint {
      let temp = String(format: "%.1f", Double(coolingSetpoint) / 100.0)
      captionTitle = "Cooling setpoint: \(temp)°C"
    } else if systemMode == "Heat", let heatingSetpoint = currentAttributes.occupiedHeatingSetpoint {
      let temp = String(format: "%.1f", Double(heatingSetpoint) / 100.0)
      captionTitle = "Heating setpoint: \(temp)°C"
    }

    return HistoryItemViewModel(
      id: historyItem.id,
      eventTitle: eventTitle,
      captionTitle: captionTitle,
      deviceName: deviceName,
      timestampString: HistoryViewModel.dateFormatter.string(from: historyItem.timestamp),
      thumbnailURL: "",
      previewClipURL: nil,
      historicalPlaybackURL: nil,
      timestamp: historyItem.timestamp,
      iconName: "thermometer",
      eventTypeIdentifier: "ThermostatStateChange"
    )
  }


  private func handleRelativeHumidityMeasurementStateChange(
    _ stateChange: StateChangeEvent<Matter.RelativeHumidityMeasurementTrait>,
    historyItem: HistoryItem
  ) -> HistoryItemViewModel {
    let timestampString = HistoryViewModel.dateFormatter.string(from: historyItem.timestamp)
    let deviceName = self.resolveDeviceName(for: historyItem.source)

    var eventTitle = "\(deviceName) humidity updated"
    if let measuredValue = stateChange.newValue.attributes.measuredValue {
      let humidityValue = Double(measuredValue) / 100.0
      eventTitle = "\(deviceName) humidity updated to \(String(format: "%.1f", humidityValue))%"
    }

    return HistoryItemViewModel(
      id: historyItem.id,
      eventTitle: eventTitle,
      captionTitle: nil,
      deviceName: deviceName,
      timestampString: timestampString,
      thumbnailURL: "",
      previewClipURL: nil,
      historicalPlaybackURL: nil,
      timestamp: historyItem.timestamp,
      iconName: "humidity",
      eventTypeIdentifier: "RelativeHumidityMeasurementStateChange"
    )
  }

  /// Ignored to avoid cluttering the history events pool with high-frequency battery status updates.
  private func handlePowerSourceStateChange(
    _ stateChange: StateChangeEvent<Matter.PowerSourceTrait>,
    historyItem: HistoryItem
  ) -> HistoryItemViewModel? {
    return nil
  }

  /// Ignored to avoid cluttering the history events pool with high-frequency connectivity status updates.
  private func handleConnectivityStateChange(
    _ stateChange: StateChangeEvent<Google.ConnectivityTrait>,
    historyItem: HistoryItem
  ) -> HistoryItemViewModel? {
    return nil
  }
}

extension Google.CameraHistoryTrait.HistoryItemEvent.Payload {
  var shortCaption: String? {
    return self.captions?.first { $0.captionType == .short }?.captionText
  }

  var longCaption: String? {
    return self.captions?.first { $0.captionType == .long }?.captionText
  }
}

extension HistoryItem.Source {
  var deviceName: String {
    switch self {
    case .device(let device, _, _):
      return device.name
    default:
      return "Unknown device"
    }
  }
}

/// An event type that can be displayed in the event type filter sheet.
///
/// This provides a mapping between the SDK event type enum, the event type name for display in the
/// UI, and the filter event type string that is received from the SDK and sent for filtering
/// history by event type.
public struct EventType: Sendable, Hashable, Identifiable {
  public let id: String
  public let cameraEventTypeEnum: Google.CameraHistoryTrait.EventType
  public let eventTypeName: String
  public let filterEventTypeString: String

  public init(
    _ cameraEventTypeEnum: Google.CameraHistoryTrait.EventType,
    _ eventTypeName: String,
    _ filterEventTypeString: String
  ) {
    self.id = filterEventTypeString
    self.cameraEventTypeEnum = cameraEventTypeEnum
    self.eventTypeName = eventTypeName
    self.filterEventTypeString = filterEventTypeString
  }
}

/// A device that can be displayed in the device picker sheet.
///
/// This is a simplification of the SDK Device type to only hold the information needed for the
/// device picker sheet when filtering history on a list of devices.
public struct DeviceFilterSelection: Sendable, Hashable, Identifiable {
  public let id: String
  public let name: String
}

/// HistoryItemViewModel is a wrapper around the HistoryItem data model that is used by the UI to
/// simplify representation logic.
public struct HistoryItemViewModel: Sendable, Identifiable {
  public let id: String
  public let eventTitle: String
  public let captionTitle: String?
  public let deviceName: String
  public let timestampString: String
  public let thumbnailURL: String
  public let previewClipURL: URL?
  public let historicalPlaybackURL: URL?
  public let timestamp: Date
  public let iconName: String
  public let eventTypeIdentifier: String
}

/// HistorySection is a wrapper around a group of history items that are all from the same day.
/// This is used to group history items in the UI by day.
public struct HistorySection: Sendable {
  public let dateString: String
  public let date: Date
  public var events: [HistoryItemViewModel]
}

// MARK: - DoorLock Alarm Extensions

extension Matter.DoorLockTrait.AlarmCodeEnum? {
  fileprivate var text: String {
    switch self {
    case .doorAjar:
      return "Door Ajar"
    case .doorForcedOpen:
      return "Door Forced Open"
    case .forcedUser:
      return "Forced User"
    case .frontEsceutcheonRemoved:
      return "Front Escutcheon Removed"
    case .lockFactoryReset:
      return "Lock Factory Reset"
    case .lockJammed:
      return "Lock Jammed"
    case .lockRadioPowerCycled:
      return "Lock Radio Power Cycled"
    case .wrongCodeEntryLimit:
      return "Wrong Code Entry Limit Exceeded"
    default:
      return "Unknown"
    }
  }
}

// MARK: - DoorLock Extensions

extension Matter.DoorLockTrait.LockOperationTypeEnum? {
  fileprivate var text: String {
    switch self {
    case .lock:
      return "Lock"
    case .unlock:
      return "Unlock"
    case .forcedUserEvent:
      return "Forced User Event"
    case .nonAccessUserEvent:
      return "Non-Access User Event"
    case .unlatch:
      return "Unlatch"
    default:
      return "Unknown"
    }
  }
}

extension Matter.DoorLockTrait.OperationSourceEnum? {
  fileprivate var text: String {
    switch self {
    case .manual:
      return "Manual"
    case .keypad:
      return "Keypad"
    case .proprietaryRemote:
      return "Proprietary Remote"
    case .rfid:
      return "RFID"
    case .auto:
      return "Auto"
    case .biometric:
      return "Biometric"
    case .button:
      return "Button"
    case .remote:
      return "Remote"
    case .schedule:
      return "Schedule"
    case .aliro:
      return "Aliro"
    default:
      return "Unknown"
    }
  }
}

// MARK: - Thermostat Enum Text Extensions

extension Matter.ThermostatTrait.ThermostatRunningModeEnum? {
  fileprivate var text: String {
    switch self {
    case .off:
      return "Off"
    case .heat:
      return "Heat"
    case .cool:
      return "Cool"
    default:
      return "Unknown"
    }
  }
}

extension Matter.ThermostatTrait.SystemModeEnum? {
  fileprivate var text: String {
    switch self {
    case .off:
      return "Off"
    case .heat:
      return "Heat"
    case .cool:
      return "Cool"
    case .auto:
      return "Auto"
    case .fanOnly:
      return "Fan Only"
    case .emergencyHeat:
      return "Emergency Heat"
    case .precooling:
      return "Pre-cooling"
    case .dry:
      return "Dry"
    case .sleep:
      return "Sleep"
    default:
      return "Unknown"
    }
  }
}
