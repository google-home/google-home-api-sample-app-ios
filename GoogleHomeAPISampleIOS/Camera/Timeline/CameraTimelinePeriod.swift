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
import GoogleHomeTypes

/// A pill in the camera timeline.
public struct CameraTimelinePeriod: Identifiable, Sendable {
  /// The id of the period.
  public let id: String
  /// The start time of the period.
  public let startTime: Date
  /// The end time of the period.
  public let endTime: Date
  /// The type of the period.
  public let type: TimelineType
  /// The session id of the period.
  public let sessionID: String?
  /// The history item associated with the period.
  public let historyItem: CameraTimelinePeriodHistoryItem?
  /// The reason for video to be unavailable at the given period.
  public let noVideoReason: String?

  /// Creates a new timeline period.
  ///
  /// - Parameters:
  ///   - startTime: The start time of the period.
  ///   - endTime: The end time of the period.
  ///   - type: The type of the period.
  ///   - sessionID: The session id of the period.
  ///   - historyItem: The history item associated with the period.
  ///   - noVideoReason: The reason for video to be unavailable at the given period.
  public init(
    startTime: Date,
    endTime: Date,
    type: TimelineType,
    sessionID: String? = nil,
    historyItem: CameraTimelinePeriodHistoryItem? = nil,
    noVideoReason: String? = nil
  ) {
    self.id = "\(startTime.timeIntervalSince1970)_\(endTime.timeIntervalSince1970)_\(sessionID ?? type.rawValue)"
    self.startTime = startTime
    self.endTime = endTime
    self.type = type
    self.sessionID = sessionID
    self.historyItem = historyItem
    self.noVideoReason = noVideoReason
  }
}

/// The type of timeline that a period represents.
public enum TimelineType: String, CaseIterable, Sendable {
  case cameraStatus, recording, event

  /// Creates a new timeline type from a camera timeline trait timeline mode.
  ///
  /// - Parameter mode: The trait timeline mode to create the timeline type from.
  public init(from mode: Google.CameraTimelineTrait.TimelineMode) {
    switch mode {
    case .cameraStates:
      self = .cameraStatus
    case .video:
      self = .recording
    case .events:
      self = .event
    default:
      self = .cameraStatus
    }
  }
}

/// A list of camera timeline periods.
public struct CameraTimelinePeriodList: Sendable {
  public var cameraStatus: [CameraTimelinePeriod]
  public var recording: [CameraTimelinePeriod]
  public var event: [CameraTimelinePeriod]

  public init(
    cameraStatus: [CameraTimelinePeriod] = [],
    recording: [CameraTimelinePeriod] = [],
    event: [CameraTimelinePeriod] = []
  ) {
    self.cameraStatus = cameraStatus
    self.recording = recording
    self.event = event
  }

  /// Returns a list of periods intersecting with the given date range.
  ///
  /// - Parameter dateRange: The date range to check intersections for.
  /// - Returns: A `CameraTimelinePeriodListSlice` containing periods that intersect with the date range.
  public func intersectingPeriods(
    in dateRange: ClosedRange<Date>
  ) -> CameraTimelinePeriodListSlice {
    return CameraTimelinePeriodListSlice(
      cameraStatus: intersecting(in: cameraStatus, for: dateRange),
      recording: intersecting(in: recording, for: dateRange),
      event: intersecting(in: event, for: dateRange)
    )
  }

  /// Performs a search on the periods to find intersecting periods.
  ///
  /// - Parameters:
  ///   - periods: The list of periods to search.
  ///   - dateRange: The date range to check intersections for.
  /// - Returns: An array slice of periods that intersect with the date range.
  /// Note: The search assumes the input array is sorted such that ending times are monotonically increasing,
  /// which typically holds true for non-overlapping timeline states.
  private func intersecting(
    in periods: [CameraTimelinePeriod],
    for dateRange: ClosedRange<Date>
  ) -> ArraySlice<CameraTimelinePeriod> {
    guard dateRange.lowerBound <= dateRange.upperBound else { return [] }
    var low = 0
    var high = periods.count

    while low < high {
      let mid = low + (high - low) / 2
      if periods[mid].endTime < dateRange.lowerBound {
        low = mid + 1
      } else {
        high = mid
      }
    }
    let startIndex = low

    var endIndex = startIndex
    while endIndex < periods.count && periods[endIndex].startTime <= dateRange.upperBound {
      endIndex += 1
    }

    return periods[startIndex..<endIndex]
  }

  public func combine(with other: CameraTimelinePeriodList) -> CameraTimelinePeriodList {
    return CameraTimelinePeriodList(
      cameraStatus: mergeAndDeduplicate(cameraStatus, other.cameraStatus),
      recording: mergeAndDeduplicate(recording, other.recording),
      event: mergeAndDeduplicate(event, other.event)
    )
  }

  private func mergeAndDeduplicate(
    _ lhs: [CameraTimelinePeriod],
    _ rhs: [CameraTimelinePeriod]
  ) -> [CameraTimelinePeriod] {
    var result = [CameraTimelinePeriod]()
    result.reserveCapacity(lhs.count + rhs.count)
    var seenKeys = Set<String>()

    var lhsIndex = 0
    var rhsIndex = 0

    while lhsIndex < lhs.count && rhsIndex < rhs.count {
      let lhsPeriod = lhs[lhsIndex]
      let rhsPeriod = rhs[rhsIndex]

      if lhsPeriod.startTime <= rhsPeriod.startTime {
        if seenKeys.insert(lhsPeriod.id).inserted {
          result.append(lhsPeriod)
        }
        lhsIndex += 1
      } else {
        if seenKeys.insert(rhsPeriod.id).inserted {
          result.append(rhsPeriod)
        }
        rhsIndex += 1
      }
    }

    while lhsIndex < lhs.count {
      let lhsPeriod = lhs[lhsIndex]
      if seenKeys.insert(lhsPeriod.id).inserted {
        result.append(lhsPeriod)
      }
      lhsIndex += 1
    }

    while rhsIndex < rhs.count {
      let rhsPeriod = rhs[rhsIndex]
      if seenKeys.insert(rhsPeriod.id).inserted {
        result.append(rhsPeriod)
      }
      rhsIndex += 1
    }

    return result
  }

  /// For a given date, returns any non-empty no video reason from any period containing the date.
  public func noVideoReason(at date: Date) -> String? {
    let range = date...date
    return intersecting(in: recording, for: range).first?.noVideoReason
      ?? intersecting(in: event, for: range).first?.noVideoReason
      ?? intersecting(in: cameraStatus, for: range).first?.noVideoReason
  }

}

/// A slice of camera timeline periods.
public struct CameraTimelinePeriodListSlice: Sendable {
  /// The camera status periods in the slice.
  public var cameraStatus: ArraySlice<CameraTimelinePeriod>
  /// The recording periods in the slice.
  public var recording: ArraySlice<CameraTimelinePeriod>
  /// The event periods in the slice.
  public var event: ArraySlice<CameraTimelinePeriod>
}

/// A history item associated with a camera timeline period.
public struct CameraTimelinePeriodHistoryItem: Sendable {
  /// The session id of the history item.
  public let sessionID: String
  /// The caption of the history item.
  public let caption: String?
  /// A provider for the thumbnail image data.
  public let thumbnailProvider: (@Sendable () async throws -> Data?)?
  /// The historical playback URL of the history item.
  public let historicalPlaybackURL: URL?
  /// The download URL of the history item.
  public let downloadURL: URL?

  public init(
    sessionID: String,
    caption: String? = nil,
    thumbnailProvider: (@Sendable () async throws -> Data?)? = nil,
    historicalPlaybackURL: URL? = nil,
    downloadURL: URL? = nil
  ) {
    self.sessionID = sessionID
    self.caption = caption
    self.thumbnailProvider = thumbnailProvider
    self.historicalPlaybackURL = historicalPlaybackURL
    self.downloadURL = downloadURL
  }
}
