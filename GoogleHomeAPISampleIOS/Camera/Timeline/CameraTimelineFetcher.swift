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

private let logger = Logger(
  subsystem: "com.google.HomePlatform", category: "CameraTimelineFetcher")

/// Fetches the camera timeline data for a given camera timeline trait and provides it to the
/// parent through an async stream.
public actor CameraTimelineFetcher {

  private let cameraTimelineTraitProvider: @Sendable () async -> Google.CameraTimelineTrait?
  private let accessTokenProvider: @Sendable () async throws -> String

  /// The duration of the timeline query buffer in both directions (24 hours).
  private static let buffer: TimeInterval = 24 * 60 * 60
  /// The duration of each timeline data chunk to fetch (12 hours).
  private static let chunkDuration: TimeInterval = 12 * 60 * 60
  /// The buffer duration to protect live edge playback (1 minute).
  private static let liveEdgeBuffer: TimeInterval = 60
  /// The tolerance duration for chunk duration validation (1 second).
  private static let chunkTolerance: TimeInterval = 1

  public init(
    cameraTimelineTraitProvider: @escaping @Sendable () async -> Google.CameraTimelineTrait?,
    accessTokenProvider: @escaping @Sendable () async throws -> String
  ) {
    self.cameraTimelineTraitProvider = cameraTimelineTraitProvider
    self.accessTokenProvider = accessTokenProvider
  }

  private var pendingTime: Date? = nil
  private var pendingContinuation: CheckedContinuation<Void, Never>? = nil

  /// Updates the pending time to the given time.
  ///
  /// - Parameter newTime: The new pending time.
  public func updatePendingTime(_ newTime: Date) {
    self.pendingTime = newTime
    if let continuation = self.pendingContinuation {
      self.pendingContinuation = nil
      continuation.resume()
    }
  }

  private func resumePendingContinuation() {
    if let continuation = self.pendingContinuation {
      self.pendingContinuation = nil
      continuation.resume()
    }
  }

  private func waitForNewTime() async {
    guard self.pendingTime == nil else { return }
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        if Task.isCancelled {
          continuation.resume()
        } else {
          self.pendingContinuation = continuation
        }
      }
    } onCancel: {
      Task {
        await self.resumePendingContinuation()
      }
    }
  }

  /// Fetches the timeline data for a given camera timeline trait and provides it to the
  /// parent through an async stream.
  ///
  /// - Parameters:
  ///   - startDate: The start date of the range to fetch.
  /// - Returns: A tuple of an async stream of timeline data and a callback to update the pending
  ///   time. The callback should be used when the timeline is interacted with, for example, when
  ///   the playhead is moved.
  public func fetchTimeline(
    startDate: Date
  ) -> (
    result: AsyncStream<CameraTimelinePeriodList>,
    onPrioritizedTimeChanged: @Sendable (Date) -> Void
  ) {
    let (ingestionStream, ingestionContinuation) =
      AsyncStream<Date>.makeStream(bufferingPolicy: .bufferingNewest(1))
    let (periodsStream, listContinuation) = AsyncStream<CameraTimelinePeriodList>.makeStream()

    let monitorTask = Task { [weak self] in
      for await newTime in ingestionStream {
        await self?.updatePendingTime(newTime)
      }
    }

    let workerTask = Task { [weak self] in
      // Already fetched ClosedRanges.
      var fetchedTimelineRanges: [ClosedRange<Date>] = []
      // Aggregated timeline periods.
      var fetchedPeriods = CameraTimelinePeriodList()
      // Starting point for background fetching.
      var latestPlayheadAnchor = startDate

      // Trigger initial fetch.
      await self?.updatePendingTime(startDate)

      while !Task.isCancelled {
        guard let self = self else { break }
        let activeTargetTime: Date
        let isPriorityFetch: Bool

        // Priority Fetch: Prioritize fetching around playhead changes immediately.
        let capturedTime = await self.getAndClearPendingTime()
        if let capturedTime = capturedTime {
          activeTargetTime = capturedTime
          latestPlayheadAnchor = capturedTime
          isPriorityFetch = true
        } else {
          // Background Fetch: Expand buffer around playhead anchor.
          activeTargetTime = latestPlayheadAnchor
          isPriorityFetch = false
        }

        guard
          let fetchRange = await self.getNextFetchRange(
            currentTime: activeTargetTime,
            fetchedTimelineRanges: fetchedTimelineRanges
          ),
          let cameraTimelineTrait = await self.cameraTimelineTraitProvider()
        else {
          // Buffer full. Suspend task until new target arrives.
          await self.waitForNewTime()
          continue
        }

        do {
          logger.info(
            "\(isPriorityFetch ? "[Primary]" : "[Background]") Fetching timeline data from \(fetchRange.lowerBound) to \(fetchRange.upperBound)"
          )
          logger.debug(
            "FETCH: \(fetchRange.lowerBound.formatted(.iso8601)) to \(fetchRange.upperBound.formatted(.iso8601))"
          )

          let timelinePeriods = try await self.fetchTimelineData(
            cameraTimelineTrait: cameraTimelineTrait,
            dateRange: fetchRange
          )

          Self.insertAndMerge(fetchRange, into: &fetchedTimelineRanges)
          fetchedPeriods = fetchedPeriods.combine(with: timelinePeriods)

          listContinuation.yield(fetchedPeriods)
        } catch {
          logger.error("Error fetching timeline data: \(error)")
          // Sleep to avoid tight infinite retry loop on network/API failure.
          try? await Task.sleep(for: .seconds(5))
        }
      }
    }

    listContinuation.onTermination = { _ in
      monitorTask.cancel()
      workerTask.cancel()
    }

    return (
      periodsStream,
      { newDate in
        ingestionContinuation.yield(newDate)
      }
    )
  }

  private func getAndClearPendingTime() -> Date? {
    let value = self.pendingTime
    self.pendingTime = nil
    return value
  }

  /// Inserts and merges overlapping/contiguous ranges to simplify range calculations.
  private static func insertAndMerge(
    _ newRange: ClosedRange<Date>,
    into ranges: inout [ClosedRange<Date>]
  ) {
    ranges.append(newRange)
    ranges.sort { $0.lowerBound < $1.lowerBound }

    var merged: [ClosedRange<Date>] = []
    for range in ranges {
      if let last = merged.last, last.upperBound >= range.lowerBound {
        merged[merged.count - 1] = last.lowerBound...max(last.upperBound, range.upperBound)
      } else {
        merged.append(range)
      }
    }
    ranges = merged
  }

  /// Calculates the next time range to fetch based on current playhead and fetched ranges.
  ///
  /// - Parameters:
  ///   - currentTime: The anchor date for fetching.
  ///   - fetchedTimelineRanges: Fetched ClosedRange list.
  /// - Returns: The next range to fetch, or nil if buffer is full.
  private func getNextFetchRange(
    currentTime: Date,
    fetchedTimelineRanges: [ClosedRange<Date>]
  ) -> ClosedRange<Date>? {
    let liveEdge = Date()
    // Absolute search window (24h back/forward).
    let lowerBound = currentTime.addingTimeInterval(-CameraTimelineFetcher.buffer)
    // Upper bound is capped by 'now' because we cannot fetch future data.
    let upperBound = min(liveEdge, currentTime.addingTimeInterval(CameraTimelineFetcher.buffer))

    let fetchStartPoint: Date
    // Check if playhead intersects an already fetched range.
    if let intersectingRange = fetchedTimelineRanges.first(where: {
      let extendedLower = $0.lowerBound.addingTimeInterval(-Self.liveEdgeBuffer)
      let extendedUpper = $0.upperBound.addingTimeInterval(Self.liveEdgeBuffer)
      return (extendedLower...extendedUpper).contains(currentTime)
    }) {
      let canExpandLeft = lowerBound < intersectingRange.lowerBound

      // Find the next range ahead.
      let nextRange =
        fetchedTimelineRanges
        .filter { $0.lowerBound > intersectingRange.upperBound }
        .min(by: { $0.lowerBound < $1.lowerBound })

      // Capped by next range or live edge.
      let rightLimit = nextRange?.lowerBound ?? upperBound

      let isRightLimitLiveEdge = (rightLimit == liveEdge)
      let rightSpaceToLimit = rightLimit.timeIntervalSince(intersectingRange.upperBound)

      let canExpandRight: Bool
      if isRightLimitLiveEdge {
        canExpandRight = rightSpaceToLimit >= Self.liveEdgeBuffer
      } else {
        canExpandRight = rightSpaceToLimit > 0
      }

      // Fully fetched.
      guard canExpandLeft || canExpandRight else {
        return nil
      }

      // Expand towards playhead direction.
      if canExpandLeft && canExpandRight {
        let leftDist = currentTime.timeIntervalSince(intersectingRange.lowerBound)
        let rightDist = intersectingRange.upperBound.timeIntervalSince(currentTime)
        fetchStartPoint =
          leftDist < rightDist ? intersectingRange.lowerBound : intersectingRange.upperBound
      } else if canExpandLeft {
        fetchStartPoint = intersectingRange.lowerBound
      } else {
        fetchStartPoint = intersectingRange.upperBound
      }
    } else {
      // Anchor initial fetch at playhead.
      fetchStartPoint = currentTime
    }

    // Limit left expansion to prevent overlap.
    let minAllowed =
      fetchedTimelineRanges.filter { $0.upperBound <= fetchStartPoint }.map { $0.upperBound }.max()
      ?? lowerBound
    let actualLowerLimit = max(lowerBound, minAllowed)

    // Limit right expansion to prevent overlap.
    let maxAllowed =
      fetchedTimelineRanges.filter { $0.lowerBound >= fetchStartPoint }.map { $0.lowerBound }.min()
      ?? upperBound
    let actualUpperLimit = min(upperBound, maxAllowed)

    guard actualLowerLimit < actualUpperLimit else {
      return nil
    }

    let leftSpace = fetchStartPoint.timeIntervalSince(actualLowerLimit)
    let rightSpace = actualUpperLimit.timeIntervalSince(fetchStartPoint)
    let halfChunk = CameraTimelineFetcher.chunkDuration / 2

    var lower = fetchStartPoint
    var upper = fetchStartPoint

    // Expand chunk up to bounds.
    lower = fetchStartPoint.addingTimeInterval(-min(leftSpace, halfChunk))
    upper = fetchStartPoint.addingTimeInterval(min(rightSpace, halfChunk))

    guard lower < upper else {
      return nil
    }

    let isLiveEdge = (actualUpperLimit == liveEdge)
    if isLiveEdge && upper == actualUpperLimit {
      let fetchDuration = upper.timeIntervalSince(lower)
      if fetchDuration < Self.liveEdgeBuffer {
        return nil
      }
    }

    return lower...upper
  }

  /// Fetches the timeline data for a given time range from the camera timeline trait.
  private func fetchTimelineData(
    cameraTimelineTrait: Google.CameraTimelineTrait,
    dateRange: ClosedRange<Date>
  ) async throws -> CameraTimelinePeriodList {
    let accessTokenProvider = self.accessTokenProvider
    logger.debug(
      "FETCH: \(dateRange.lowerBound.formatted(.iso8601)) to \(dateRange.upperBound.formatted(.iso8601))"
    )
    // Validate date range and chunk size.
    guard
      dateRange.lowerBound <= dateRange.upperBound,
      dateRange.upperBound.timeIntervalSince(dateRange.lowerBound)
        <= CameraTimelineFetcher.chunkDuration + CameraTimelineFetcher.chunkTolerance
    else {
      throw HomeError.failedPrecondition(
        "Time interval greater than chunk size, start: \(dateRange.lowerBound) end: \(dateRange.upperBound) chunk size: \(CameraTimelineFetcher.chunkDuration)."
      )
    }

    var responses: [Google.CameraTimelineTrait.ListTimelinePeriodsCommandResponse] = []
    var nextPageToken: String = ""

    while responses.isEmpty || !nextPageToken.isEmpty {
      let response: Google.CameraTimelineTrait.ListTimelinePeriodsCommandResponse =
        try await cameraTimelineTrait.listTimelinePeriods(
          startTimeMillis: UInt64(dateRange.lowerBound.timeIntervalSince1970 * 1000),
          endTimeMillis: UInt64(dateRange.upperBound.timeIntervalSince1970 * 1000),
          modes: [.video, .events, .cameraStates],
          optionalArgsProvider: { [nextPageToken] optionalArgs in
            if !nextPageToken.isEmpty {
              optionalArgs.setPageToken(nextPageToken)
            }
          }
        )

      responses.append(response)
      nextPageToken = response.nextPageToken ?? ""
    }

    var newPeriodList: CameraTimelinePeriodList = CameraTimelinePeriodList()

    for response in responses {
      for timelineMode in response.timelinePeriodsStreams {
        let newPeriods = timelineMode.periods.map { timelinePeriod in
          let traitHistoryItem = timelinePeriod.noVideoPeriodData?.cameraHistoryItem
          let sessionID = traitHistoryItem?.sessionId

          let localHistoryItem: CameraTimelinePeriodHistoryItem?
          if let traitHistoryItem = traitHistoryItem, let sessionID = sessionID {
            let mediaUrl = traitHistoryItem.mediaUrl
            let thumbnailURL =
              mediaUrl.thumbnail_url.isEmpty ? nil : URL(string: mediaUrl.thumbnail_url)
            let hlsURL =
              mediaUrl.hls_master_playlist_url.isEmpty
              ? nil : URL(string: mediaUrl.hls_master_playlist_url)
            let mp4URL =
              mediaUrl.mp4_download_url.isEmpty ? nil : URL(string: mediaUrl.mp4_download_url)

            localHistoryItem = CameraTimelinePeriodHistoryItem(
              sessionID: sessionID,
              caption: traitHistoryItem.resolvedCaption,
              thumbnailProvider: { [accessTokenProvider] in
                guard let thumbnailURL = thumbnailURL else { return nil }
                do {
                  let token = try await accessTokenProvider()
                  var request = URLRequest(url: thumbnailURL)
                  request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                  let (data, response) = try await URLSession.shared.data(for: request)
                  guard let httpResponse = response as? HTTPURLResponse else {
                    logger.error("CameraTimelineFetcher: Non-HTTP response for thumbnail: \(thumbnailURL.absoluteString, privacy: .public)")
                    return nil
                  }
                  guard httpResponse.statusCode == 200 else {
                    logger.error("CameraTimelineFetcher: Thumbnail request failed with status \(httpResponse.statusCode)")
                    return nil
                  }
                  return data
                } catch {
                  logger.error("CameraTimelineFetcher: Failed to load thumbnail from \(thumbnailURL.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
                  return nil
                }
              },
              historicalPlaybackURL: hlsURL,
              downloadURL: mp4URL
            )
          } else {
            localHistoryItem = nil
          }

          return CameraTimelinePeriod(
            startTime: Date(timeIntervalSince1970: Double(timelinePeriod.startTimeMillis) / 1000),
            endTime: Date(timeIntervalSince1970: Double(timelinePeriod.endTimeMillis) / 1000),
            type: TimelineType(from: timelineMode.timelineMode),
            sessionID: sessionID,
            historyItem: localHistoryItem,
            noVideoReason: timelinePeriod.noVideoPeriodData?.reason.description
          )
        }

        switch timelineMode.timelineMode {
        case .cameraStates:
          newPeriodList.cameraStatus.append(contentsOf: newPeriods)
        case .video:
          newPeriodList.recording.append(contentsOf: newPeriods)
        case .events:
          newPeriodList.event.append(contentsOf: newPeriods)
        default:
          break
        }
      }
    }

    return newPeriodList
  }

}
