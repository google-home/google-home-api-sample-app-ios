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

import GoogleHomeSDK
import GoogleHomeTypes

extension Google.CameraTimelineTrait.EventType {
  /// The priority of the event type, lower numbered priorities are more significant.
  public var priority: Int {
    return CameraEventTypePriority.priority(forTimelineEventType: self)
  }

  /// The fallback display name for the event type.
  public var fallbackEventTypeName: String {
    return CameraEventTypePriority.displayName(forTimelineEventType: self)
  }
}

extension Google.CameraHistoryTrait.EventType {
  /// The priority of the event type, lower numbered priorities are more significant.
  public var priority: Int {
    return CameraEventTypePriority.priority(forHistoryEventType: self)
  }

  /// The fallback display name for the event type.
  public var fallbackEventTypeName: String {
    return CameraEventTypePriority.displayName(forHistoryEventType: self)
  }
}

/// Configuration model representing a camera event type, mapping its display name and matching enums
/// across multiple traits (Timeline and History).
public struct CameraEventTypeConfig: Sendable {
  /// The localized display name to use for the camera event.
  public let displayName: String

  /// The corresponding event type defined under the Camera Timeline trait, if applicable.
  public let timelineEventType: Google.CameraTimelineTrait.EventType?

  /// The corresponding event type defined under the Camera History trait, if applicable.
  public let historyEventType: Google.CameraHistoryTrait.EventType?

  /// Initializes a camera event type configuration.
  /// - Parameters:
  ///   - displayName: The display name for the event.
  ///   - timelineEventType: The optional matching timeline event type enum case.
  ///   - historyEventType: The optional matching history event type enum case.
  public init(
    displayName: String,
    timelineEventType: Google.CameraTimelineTrait.EventType? = nil,
    historyEventType: Google.CameraHistoryTrait.EventType? = nil
  ) {
    self.displayName = displayName
    self.timelineEventType = timelineEventType
    self.historyEventType = historyEventType
  }
}

/// Handles prioritization and display name resolution for camera event types.
///
/// Mappings are backed by a single, unified configuration list which establishes a single source of
/// truth for the order of event significance.
public enum CameraEventTypePriority: Sendable {
  private static let defaultPriority = 99
  private static let defaultDisplayName = String(localized: "Unknown camera event")

  /// The unified configuration list for all camera event types.
  /// Order defines the priority (lower index = higher significance).
  public static let configs: [CameraEventTypeConfig] = [
    CameraEventTypeConfig(
      displayName: String(localized: "Smoke Alarm"),
      timelineEventType: .smokeAlarm,
      historyEventType: .smokeAlarm
    ),
    CameraEventTypeConfig(
      displayName: String(localized: "Recording Smoke Alarm"),
      timelineEventType: .recordingSmokeAlarm,
      historyEventType: .recordingSmokeAlarm
    ),
    CameraEventTypeConfig(
      displayName: String(localized: "CO Alarm"),
      timelineEventType: .coAlarm,
      historyEventType: .coAlarm
    ),
    CameraEventTypeConfig(
      displayName: String(localized: "Recording CO Alarm"),
      timelineEventType: .recordingCOAlarm,
      historyEventType: .recordingCOAlarm
    ),
    CameraEventTypeConfig(
      displayName: String(localized: "Security Alarm"),
      timelineEventType: .securityAlarm,
      historyEventType: .securityAlarm
    ),
    CameraEventTypeConfig(
      displayName: String(localized: "Glass Break"),
      timelineEventType: .glassBreak,
      historyEventType: .glassBreak
    ),
    CameraEventTypeConfig(
      displayName: String(localized: "Package Delivered"),
      timelineEventType: .packageDelivered,
      historyEventType: .packageDelivered
    ),
    CameraEventTypeConfig(
      displayName: String(localized: "Package Retrieved"),
      timelineEventType: .packageRetrieved,
      historyEventType: .packageRetrieved
    ),
    CameraEventTypeConfig(
      displayName: String(localized: "Package In Transit"),
      timelineEventType: .packageInTransit,
      historyEventType: .packageInTransit
    ),
    CameraEventTypeConfig(
      displayName: String(localized: "Familiar Face"),
      timelineEventType: .familiarFace,
      historyEventType: .familiarFace
    ),
    CameraEventTypeConfig(
      displayName: String(localized: "Unfamiliar Face"),
      timelineEventType: .unfamiliarFace,
      historyEventType: .unfamiliarFace
    ),
    CameraEventTypeConfig(
      displayName: String(localized: "Doorbell Pressed"),
      timelineEventType: .doorbell,
      historyEventType: .doorbell
    ),
    CameraEventTypeConfig(
      displayName: String(localized: "Person"),
      timelineEventType: .person,
      historyEventType: .person
    ),
    CameraEventTypeConfig(
      displayName: String(localized: "Garage Door Opened"),
      timelineEventType: .garageDoorOpened,
      historyEventType: .garageDoorOpened
    ),
    CameraEventTypeConfig(
      displayName: String(localized: "Garage Door Closed"),
      timelineEventType: .garageDoorClosed,
      historyEventType: .garageDoorClosed
    ),
    CameraEventTypeConfig(
      displayName: String(localized: "Animal"),
      timelineEventType: .animal,
      historyEventType: .animal
    ),
    CameraEventTypeConfig(
      displayName: String(localized: "Vehicle"),
      timelineEventType: .vehicle,
      historyEventType: .vehicle
    ),
    CameraEventTypeConfig(
      displayName: String(localized: "Sound"),
      timelineEventType: .sound,
      historyEventType: .sound
    ),
    CameraEventTypeConfig(
      displayName: String(localized: "Motion"),
      timelineEventType: .motion,
      historyEventType: .motion
    ),
    CameraEventTypeConfig(
      displayName: String(localized: "Dog Bark"),
      timelineEventType: .dogBark,
      historyEventType: .dogBark
    ),
    CameraEventTypeConfig(
      displayName: String(localized: "Person Talking"),
      timelineEventType: .personTalking,
      historyEventType: .personTalking
    ),
  ]

  private static let timelineMap:
    [Google.CameraTimelineTrait.EventType: (priority: Int, displayName: String)] = {
      var map = [Google.CameraTimelineTrait.EventType: (priority: Int, displayName: String)]()
      for (index, config) in configs.enumerated() {
        if let timelineType = config.timelineEventType {
          map[timelineType] = (index, config.displayName)
        }
      }
      return map
    }()

  private static let historyMap:
    [Google.CameraHistoryTrait.EventType: (priority: Int, displayName: String)] = {
      var map = [Google.CameraHistoryTrait.EventType: (priority: Int, displayName: String)]()
      for (index, config) in configs.enumerated() {
        if let historyType = config.historyEventType {
          map[historyType] = (index, config.displayName)
        }
      }
      return map
    }()

  /// Resolves the priority value for a Camera Timeline event type (lower values indicate higher significance).
  /// - Parameter eventType: The Camera Timeline event type.
  /// - Returns: The index-based priority value, defaulting to the default priority if not matched.
  public static func priority(forTimelineEventType eventType: Google.CameraTimelineTrait.EventType)
    -> Int
  {
    return timelineMap[eventType]?.priority ?? defaultPriority
  }

  /// Resolves the priority value for a Camera History event type (lower values indicate higher significance).
  /// - Parameter eventType: The Camera History event type.
  /// - Returns: The index-based priority value, defaulting to the default priority if not matched.
  public static func priority(forHistoryEventType eventType: Google.CameraHistoryTrait.EventType)
    -> Int
  {
    return historyMap[eventType]?.priority ?? defaultPriority
  }

  /// Resolves the localized display name for a Camera Timeline event type.
  /// - Parameter eventType: The Camera Timeline event type.
  /// - Returns: The display name, defaulting to default display name if not matched.
  public static func displayName(
    forTimelineEventType eventType: Google.CameraTimelineTrait.EventType
  ) -> String {
    return timelineMap[eventType]?.displayName ?? defaultDisplayName
  }

  /// Resolves the localized display name for a Camera History event type.
  /// - Parameter eventType: The Camera History event type.
  /// - Returns: The display name, defaulting to default display name if not matched.
  public static func displayName(forHistoryEventType eventType: Google.CameraHistoryTrait.EventType)
    -> String
  {
    return historyMap[eventType]?.displayName ?? defaultDisplayName
  }
}

extension Google.CameraTimelineTrait.CameraHistoryItem {
  var resolvedCaption: String {
    if let shortCaption = self.shortCaption {
      return shortCaption
    }
    let eventTypes = Set(self.eventTracks.flatMap { $0.eventTypes })
    if let bestEventType = eventTypes.min(by: { $0.priority < $1.priority }) {
      return bestEventType.fallbackEventTypeName
    }
    return "Unknown camera event"
  }

  var shortCaption: String? {
    return self.captions.first { $0.captionType == .short }?.captionText
  }
}

extension Google.CameraTimelineTrait.VideoUnavailableReason {
  var description: String {
    switch self {
    case .user:
      return String(localized: "Recording stopped by user")
    case .schedule:
      return String(localized: "Schedule")
    case .occupancy:
      return String(localized: "Occupancy")
    case .noEvents:
      return String(localized: "No Events")
    case .charging:
      return String(localized: "Device charging")
    case .privacySwitch:
      return String(localized: "Device privacy switch")
    case .thermalOverride:
      return String(localized: "Device thermal override")
    case .deviceUpdating:
      return String(localized: "Device updating")
    case .usedByDuo:
      return String(localized: "Used by Duo")
    case .notConnected:
      return String(localized: "Not Connected")
    case .batteryOverride:
      return String(localized: "Battery Override")
    case .unmounted:
      return String(localized: "Unmounted")
    case .batteryFault:
      return String(localized: "Battery Fault")
    case .stillImageOnly:
      return String(localized: "Still Image Only")
    case .etrMode:
      return String(localized: "ETR Mode")
    default:
      return String(localized: "Unknown")
    }
  }
}
