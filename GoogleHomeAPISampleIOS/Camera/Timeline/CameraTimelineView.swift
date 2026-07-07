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
import Foundation
import OSLog
import SwiftUI

/// A view that displays a list of camera timeline periods using a Canvas.
public struct CameraTimelineView: View {
  /// Default values for the public initializer of the timeline view.
  public enum Defaults {
    public static let initialPointsPerSecond: CGFloat = 0.05
  }

  fileprivate enum Constraints {
    static let scrollSyncThreshold: CGFloat = 0.01
    static let topPadding: CGFloat = 40.0
    static let momentumDeadZone: CGFloat = 50.0
    static let scalingFactor: CGFloat = 30.0
    static let animationDuration: Range<CGFloat> = 0.2..<1.2
    static let initialPointsPerSecond: CGFloat = Defaults.initialPointsPerSecond
    static let minPointsPerSecond: CGFloat = 0.01
    static let maxPointsPerSecond: CGFloat = 1.0
    static let timerInterval: TimeInterval = 1.0
    static let playheadLiveSyncThreshold: TimeInterval = 1.0

    static let liveEdgeIndicatorTriggerOffset: CGFloat = 10.0
    static let labelAreaWidthDivisor: CGFloat = 4.0
    static let timelineTrackWidthDivisor: CGFloat = 16.0
    static let spineSpacingDivisor: CGFloat = 2.0
    static let pillWidth: CGFloat = 8.0
    static let axisLineWidth: CGFloat = 2.0
    static let maxThumbnailSizeFraction: CGFloat = 0.8
    static let thumbnailSpacingFraction: CGFloat = 3.0

    static let liveEdgeThreshold: CGFloat = 0.1
    static let catchAnimationThreshold: CGFloat = 0.5
    static let hourMarkLabelDistance: CGFloat = 50.0
    static let hourMarkTickOpacityThreshold: CGFloat = 0.05
    static let minPillHeight: CGFloat = 4.0
    static let captionPadding: CGFloat = 8.0
    static let captionDoublePadding: CGFloat = 16.0
    static let thumbnailPadding: CGFloat = 5.0
    static let staticBoxHeight: CGFloat = 60.0
    static let boxSpacingFromPill: CGFloat = 20.0
    static let boxBorderWidth: CGFloat = 2.0
    static let lineBorderWidth: CGFloat = 2.0
    static let boxCornerRadius: CGFloat = 4.0

    static let unavailableOverlayPaddingBottom: CGFloat = 80.0
    static let unavailableOverlayOpacity: Double = 0.8
    static let unavailableOverlayHorizontalPadding: CGFloat = 12.0
    static let unavailableOverlayVerticalPadding: CGFloat = 8.0
    static let unavailableOverlayCornerRadius: CGFloat = 8.0
    static let unavailableOverlayShadowRadius: CGFloat = 4.0

    static let datePickerPaddingHorizontal: CGFloat = 16.0
    static let datePickerPaddingVertical: CGFloat = 6.0
    static let datePickerShadowRadius: CGFloat = 4.0
    static let datePickerPaddingTop: CGFloat = 8.0
    static let goToLiveShadowRadius: CGFloat = 4.0
    static let goToLiveButtonPaddingBottom: CGFloat = 24.0

    static let springResponse: Double = 0.4
    static let springDampingFraction: Double = 0.8
    static let playheadOverlayLineOpacity: Double = 0.3
    static let axisLineOpacity: Double = 0.3
    static let hourMarkLineOpacity: Double = 0.3
    static let shadowOpacity: Double = 0.1
  }

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase

  private let periods: CameraTimelinePeriodList
  private let isLoading: Bool
  private let onTimeChange: (Date) -> Void
  private let onStateChange: (CameraTimelineState) -> Void
  @State private var referenceDate: Date
  private let calendar: Calendar
  private let currentTimelineDate: Date?
  @State private var scrollPosition: CGFloat
  @State private var dragOffset: CGFloat = 0
  @State private var presentationState: ScrollPresentationState
  @State private var calendarSelection: Date = Date()
  @State private var showDatePickerSheet = false
  @State private var isBackgrounded = false
  @State private var isProgrammaticUpdate = false

  private var currentScrollOffset: CGFloat {
    self.scrollPosition + self.dragOffset
  }

  @State private var pointsPerSecond: CGFloat
  @State private var lastMagnification: CGFloat = 1.0

  private static let timer = Timer.publish(every: Constraints.timerInterval, on: .main, in: .common).autoconnect()

  /// Initializes the camera timeline view.
  ///
  /// - Parameters:
  ///   - periods: The list of periods to display.
  ///   - isLoading: Whether the timeline is currently loading.
  ///   - onTimeChange: Called when the timeline time is changed.
  ///   - onStateChange: Called when the state of the timeline is changed.
  ///   - referenceDate: Anchor date for 'now' (defaults to current date).
  ///   - calendar: The calendar to use for date calculations. Defaults to .current.
  ///   - currentTimelineDate: The date that should be centered on the timeline playhead.
  ///   - initialPointsPerSecond: The initial zoom level factor (points per second) for the timeline.
  public init(
    periods: CameraTimelinePeriodList,
    isLoading: Bool = false,
    onTimeChange: @escaping (Date) -> Void,
    onStateChange: @escaping (CameraTimelineState) -> Void,
    referenceDate: Date? = nil,
    calendar: Calendar = .current,
    currentTimelineDate: Date?,
    initialPointsPerSecond: CGFloat = Defaults.initialPointsPerSecond
  ) {
    self.periods = periods
    self.isLoading = isLoading
    self.onTimeChange = onTimeChange
    self.onStateChange = onStateChange
    self.calendar = calendar
    self.currentTimelineDate = currentTimelineDate
    self._pointsPerSecond = State(initialValue: initialPointsPerSecond)

    let anchorDate = referenceDate ?? Date()
    self._referenceDate = State(initialValue: anchorDate)

    let initialScrollPosition: CGFloat
    if let currentTimelineDate = currentTimelineDate {
      let timeDiff = anchorDate.timeIntervalSince(currentTimelineDate)
      initialScrollPosition =
        (timeDiff >= 0 && timeDiff < Constraints.playheadLiveSyncThreshold) ? 0 : max(0, timeDiff * initialPointsPerSecond)
    } else {
      initialScrollPosition = 0
    }
    self._scrollPosition = State(initialValue: initialScrollPosition)

    let presentationState = ScrollPresentationState()
    presentationState.offset = initialScrollPosition
    self._presentationState = State(initialValue: presentationState)
  }

  /// The view body.
  public var body: some View {
    GeometryReader { geometry in
      let labelAreaWidth = geometry.size.width / Constraints.labelAreaWidthDivisor
      let timelineTrackWidth = geometry.size.width / Constraints.timelineTrackWidthDivisor
      let spineSpacing = timelineTrackWidth / Constraints.spineSpacingDivisor
      let pillWidth = Constraints.pillWidth
      let axisLineWidth = Constraints.axisLineWidth
      let thumbnailSpacing = labelAreaWidth * Constraints.thumbnailSpacingFraction
      let maxThumbnailSize = labelAreaWidth * Constraints.maxThumbnailSizeFraction
      let playheadDate = self.dateForScrollPosition(self.currentScrollOffset)

      Group {
        if self.isLoading {
          ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          ZStack(alignment: .top) {
            AnimatableTimelineCanvas(
              scrollOffset: self.currentScrollOffset,
              presentationState: self.presentationState,
              periods: self.periods,
              referenceDate: self.referenceDate,
              pointsPerSecond: self.pointsPerSecond,
              topPadding: Constraints.topPadding,
              viewportHeight: geometry.size.height,
              draw: { context, size, animatedOffset, periods in
                self.drawTimeline(
                  in: context,
                  size: size,
                  intersectingPeriods: periods,
                  scrollOffset: animatedOffset,
                  labelAreaWidth: labelAreaWidth,
                  spineSpacing: spineSpacing,
                  pillWidth: pillWidth,
                  axisLineWidth: axisLineWidth,
                  thumbnailSpacing: thumbnailSpacing,
                  maxThumbnailSize: maxThumbnailSize,
                  topPadding: Constraints.topPadding,
                  pointsPerSecond: self.pointsPerSecond
                )
              },
              symbols: { periods in
                ForEach(periods.event) { period in
                  if let provider = period.historyItem?.thumbnailProvider {
                    TimelineThumbnailView(
                      thumbnailProvider: provider,
                      maxSize: maxThumbnailSize
                    )
                    .tag(period.id)
                  }
                }
              }
            )
            .contentShape(Rectangle())
            .gesture(self.timelineDragGesture)
            .gesture(self.timelineMagnifyGesture)

            if let reason = self.periods.noVideoReason(at: playheadDate) {
              VideoUnavailableOverlay(reason: reason)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, Constraints.unavailableOverlayPaddingBottom)
                .allowsHitTesting(false)
            }

            self.playheadOverlay(labelAreaWidth: labelAreaWidth, pillWidth: pillWidth)

            self.goToLiveButton()
          }
          .animation(.easeInOut, value: self.currentScrollOffset > Constraints.liveEdgeIndicatorTriggerOffset)
          .overlay(alignment: .top) {
            self.datePickerButton()
          }
        }
      }
      .onChange(of: self.currentScrollOffset) { _, newOffset in
        if self.isProgrammaticUpdate {
          self.isProgrammaticUpdate = false
        } else {
          self.onTimeChange(self.dateForScrollPosition(newOffset))
        }
      }
      .onChange(of: self.currentTimelineDate) { _, newDate in
        if let newDate = newDate {
          if self.dragOffset == 0 {
            let newScrollPosition = self.referenceDate.timeIntervalSince(newDate) * self.pointsPerSecond
            if abs(self.scrollPosition - newScrollPosition) > Constraints.scrollSyncThreshold {
              self.isProgrammaticUpdate = true
              if self.reduceMotion {
                self.scrollPosition = newScrollPosition
              } else {
                withAnimation(.spring(response: Constraints.springResponse, dampingFraction: Constraints.springDampingFraction)) {
                  self.scrollPosition = newScrollPosition
                }
              }
            }
          }
        } else {
          // Snap to live edge if no target date.
          if self.scrollPosition != 0 {
            self.isProgrammaticUpdate = true
            withAnimation(.spring(response: Constraints.springResponse, dampingFraction: Constraints.springDampingFraction)) {
              self.scrollPosition = 0
              self.dragOffset = 0
            }
          }
        }
      }
      .onReceive(Self.timer) { newDate in
        let lastDate = self.referenceDate
        self.referenceDate = newDate
        let timeDelta = newDate.timeIntervalSince(lastDate)

        // Stay live if at the edge, otherwise auto-scroll to lock visual time.
        if self.scrollPosition > Constraints.liveEdgeThreshold || self.dragOffset != 0 {
          self.isProgrammaticUpdate = true
          self.scrollPosition += timeDelta * self.pointsPerSecond
        } else {
          if self.scrollPosition != 0 {
            self.isProgrammaticUpdate = true
            self.scrollPosition = 0
          }
          // Sync live edge time changes.
          self.onTimeChange(newDate)
        }
      }
      .onChange(of: self.scenePhase) { _, newPhase in
        if newPhase == .background {
          self.isBackgrounded = true
        } else if newPhase == .active && self.isBackgrounded {
          self.isBackgrounded = false
          if self.scrollPosition > Constraints.liveEdgeThreshold {
            // Recalculate referenceDate and scrollPosition to prevent layout jump.
            let oldDateUnderPlayhead = self.dateForScrollPosition(self.scrollPosition)
            self.referenceDate = Date()
            self.isProgrammaticUpdate = true
            self.scrollPosition = max(0, self.referenceDate.timeIntervalSince(oldDateUnderPlayhead) * self.pointsPerSecond)
          } else {
            // Keep at live edge.
            self.referenceDate = Date()
            self.isProgrammaticUpdate = true
            self.scrollPosition = 0
          }
        }
      }
    }
  }

  private func dateForScrollPosition(_ position: CGFloat) -> Date {
    let seconds = Double(position / self.pointsPerSecond)
    return self.referenceDate.addingTimeInterval(-seconds)
  }

  private var timelineDragGesture: some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        // Catch the timeline to stop active momentum animation.
        if abs(self.currentScrollOffset - self.presentationState.offset) > Constraints.catchAnimationThreshold {
          withAnimation(nil) {
            self.scrollPosition = max(0, self.presentationState.offset)
          }
        }

        if self.dragOffset != 0 {
          self.onStateChange(.scrubbing)
        }

        self.dragOffset = -value.translation.height
      }
      .onEnded { value in
        let remainingTranslation =
          value.predictedEndTranslation.height - value.translation.height

        // Apply momentum scroll if above the dead zone.
        let momentum =
          abs(remainingTranslation) > Constraints.momentumDeadZone ? -remainingTranslation : 0

        // Decelerate naturally using a square-root duration curve.
        let duration = clamp(
          sqrt(abs(momentum)) / Constraints.scalingFactor,
          lowerBound: Constraints.animationDuration.lowerBound,
          upperBound: Constraints.animationDuration.upperBound
        )

        withAnimation(.easeOut(duration: duration)) {
          self.scrollPosition = max(0, self.scrollPosition + self.dragOffset + momentum)
          self.dragOffset = 0
        } completion: {
          if self.scrollPosition == 0 {
            self.onStateChange(.live)
          } else {
            self.onStateChange(.stopped)
          }
        }
      }
  }

  private var timelineMagnifyGesture: some Gesture {
    MagnifyGesture()
      .onChanged { value in
        let delta = value.magnification / self.lastMagnification
        self.lastMagnification = value.magnification
        let oldPointsPerSecond = self.pointsPerSecond
        self.pointsPerSecond = max(Constraints.minPointsPerSecond, min(Constraints.maxPointsPerSecond, self.pointsPerSecond * delta))

        // Adjust scroll position to keep the centered date anchored under playhead.
        let ratio = self.pointsPerSecond / oldPointsPerSecond
        self.isProgrammaticUpdate = true
        self.scrollPosition *= ratio
      }
      .onEnded { _ in
        self.lastMagnification = 1.0
      }
  }

  @ViewBuilder
  private func playheadOverlay(labelAreaWidth: CGFloat, pillWidth: CGFloat) -> some View {
    HStack(spacing: .sm) {
      PlayheadTimeView(
        referenceDate: self.referenceDate,
        scrollOffset: self.currentScrollOffset,
        pointsPerSecond: self.pointsPerSecond
      )
      .font(.caption.bold())
      .foregroundColor(.blue)
      .frame(width: labelAreaWidth - (pillWidth / 2 + Constraints.captionPadding), alignment: .trailing)

      Rectangle()
        .fill(Color.blue.opacity(Constraints.playheadOverlayLineOpacity))
        .frame(height: 1)
    }
    .padding(.top, Constraints.topPadding - 4)
    .allowsHitTesting(false)
  }

  @ViewBuilder
  private func goToLiveButton() -> some View {
    HStack {
      Spacer()
      if self.currentScrollOffset > Constraints.liveEdgeIndicatorTriggerOffset {
        Button {
          withAnimation(.spring(response: Constraints.springResponse, dampingFraction: Constraints.springDampingFraction)) {
            self.scrollPosition = 0
            self.dragOffset = 0
          }
          self.onStateChange(.live)
        } label: {
          Text("Go to live")
            .font(.subheadline.bold())
            .foregroundColor(.white)
            .padding(.horizontal, Constraints.datePickerPaddingHorizontal)
            .padding(.vertical, .sm)
            .background(Capsule().fill(Color.blue))
            .shadow(radius: Constraints.goToLiveShadowRadius)
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
      }
      Spacer()
    }
    .frame(maxHeight: .infinity, alignment: .bottom)
    .padding(.bottom, Constraints.goToLiveButtonPaddingBottom)
  }

  @ViewBuilder
  private func datePickerButton() -> some View {
    Button {
      self.calendarSelection = self.dateForScrollPosition(self.scrollPosition)
      self.showDatePickerSheet = true
    } label: {
      PlayheadDateView(
        referenceDate: self.referenceDate,
        scrollOffset: self.currentScrollOffset,
        pointsPerSecond: self.pointsPerSecond,
        calendar: self.calendar
      )
      .font(.subheadline.bold())
      .foregroundColor(.white)
      .padding(.horizontal, Constraints.datePickerPaddingHorizontal)
      .padding(.vertical, Constraints.datePickerPaddingVertical)
      .background(Capsule().fill(Color.blue).shadow(radius: Constraints.datePickerShadowRadius))
    }
    .padding(.top, Constraints.datePickerPaddingTop)
    .sheet(isPresented: self.$showDatePickerSheet) {
      CalendarPickerSheet { newDate in
        self.calendarSelection = newDate
        let timeDiff = self.referenceDate.timeIntervalSince(newDate)
        let newScrollPosition = timeDiff * self.pointsPerSecond
        withAnimation(.spring(response: Constraints.springResponse, dampingFraction: Constraints.springDampingFraction)) {
          self.scrollPosition = max(0, newScrollPosition)
        }
        self.showDatePickerSheet = false
      }
      .presentationDetents([.medium])
    }
  }

  private func drawTimeline(
    in context: GraphicsContext,
    size: CGSize,
    intersectingPeriods: CameraTimelinePeriodListSlice,
    scrollOffset: CGFloat,
    labelAreaWidth: CGFloat,
    spineSpacing: CGFloat,
    pillWidth: CGFloat,
    axisLineWidth: CGFloat,
    thumbnailSpacing: CGFloat,
    maxThumbnailSize: CGFloat,
    topPadding: CGFloat,
    pointsPerSecond: CGFloat
  ) {
    let now = self.referenceDate

    func xPosition(for type: TimelineType) -> CGFloat {
      switch type {
      case .cameraStatus:
        return labelAreaWidth
      case .recording:
        return labelAreaWidth + spineSpacing
      case .event:
        return labelAreaWidth + spineSpacing * 2
      }
    }

    for type in TimelineType.allCases {
      let x = xPosition(for: type)
      var path = Path()
      path.move(to: CGPoint(x: x, y: 0))
      path.addLine(to: CGPoint(x: x, y: size.height))
      context.stroke(path, with: .color(.gray.opacity(Constraints.axisLineOpacity)), lineWidth: axisLineWidth)
    }

    // Hour marks
    let viewportTopTime =
      now.addingTimeInterval(Double((topPadding - scrollOffset) / pointsPerSecond))
    let startHourComponents = self.calendar.dateComponents(
      [.year, .month, .day, .hour], from: viewportTopTime.addingTimeInterval(3600))
    guard var currentHour = self.calendar.date(from: startHourComponents) else {
      Logger().error("Failed to create date from components \(startHourComponents)")
      return
    }

    while let nextHour = self.calendar.date(byAdding: .hour, value: -1, to: currentHour) {
      let relativeTime = CGFloat(now.timeIntervalSince(currentHour)) * pointsPerSecond
      let y = relativeTime + topPadding - scrollOffset

      if y > size.height {
        break
      }

      if y >= 0 {
        let distanceToPlayhead = abs(y - topPadding)
        let opacity = min(1.0, distanceToPlayhead / Constraints.hourMarkLabelDistance)

        if opacity > Constraints.hourMarkTickOpacityThreshold {
          var hourContext = context
          hourContext.opacity = Double(opacity)
          let hourLabel = Text(currentHour, format: .dateTime.hour())
            .font(.caption2.bold())
          hourContext.draw(
            hourLabel, at: CGPoint(x: labelAreaWidth - (pillWidth / 2 + Constraints.captionPadding), y: y),
            anchor: .trailing)

          var tickPath = Path()
          tickPath.move(to: CGPoint(x: labelAreaWidth - pillWidth / 2, y: y))
          tickPath.addLine(to: CGPoint(x: labelAreaWidth + pillWidth / 2, y: y))
          hourContext.stroke(tickPath, with: .color(.gray.opacity(Constraints.hourMarkLineOpacity)), lineWidth: 1)
        }
      }

      currentHour = nextHour
    }

    var drawnThumbnailRects = [CGRect]()

    func render(_ periods: some Sequence<CameraTimelinePeriod>) {
      for period in periods {
        self.drawPeriod(
          period,
          in: context,
          scrollOffset: scrollOffset,
          topPadding: topPadding,
          size: size,
          now: now,
          xPosition: xPosition(for: period.type),
          pillWidth: pillWidth,
          maxThumbnailSize: maxThumbnailSize,
          thumbnailSpacing: thumbnailSpacing,
          drawnThumbnailRects: &drawnThumbnailRects,
          pointsPerSecond: pointsPerSecond
        )
      }
    }

    // Prioritize longer events to optimize thumbnail layout.
    let prioritizedEvents = intersectingPeriods.event.sorted {
      $0.endTime.timeIntervalSince($0.startTime) > $1.endTime.timeIntervalSince($1.startTime)
    }
    render(prioritizedEvents)
    render(intersectingPeriods.recording)
    render(intersectingPeriods.cameraStatus)
  }

  private func drawPeriod(
    _ period: CameraTimelinePeriod,
    in context: GraphicsContext,
    scrollOffset: CGFloat,
    topPadding: CGFloat,
    size: CGSize,
    now: Date,
    xPosition: CGFloat,
    pillWidth: CGFloat,
    maxThumbnailSize: CGFloat,
    thumbnailSpacing: CGFloat,
    drawnThumbnailRects: inout [CGRect],
    pointsPerSecond: CGFloat
  ) {
    let relativeStart = CGFloat(now.timeIntervalSince(period.startTime)) * pointsPerSecond
    let relativeEnd = CGFloat(now.timeIntervalSince(period.endTime)) * pointsPerSecond

    let startY = relativeStart + topPadding - scrollOffset
    let endY = relativeEnd + topPadding - scrollOffset

    let height = max(Constraints.minPillHeight, startY - endY)
    let pillCenterY = endY + height / 2

    // Use conservative bounds to avoid pre-resolving thumbnails before spacing check.
    var drawThumbnail = false
    let thumbnailPadding = Constraints.thumbnailPadding

    if period.historyItem != nil, period.type == .event {
      let estimatedRect = CGRect(
        x: thumbnailSpacing,
        y: pillCenterY - maxThumbnailSize / 2,
        width: maxThumbnailSize,
        height: maxThumbnailSize
      )

      let paddedRect = estimatedRect.insetBy(dx: 0, dy: -thumbnailPadding)
      let intersectsOtherThumbnail = drawnThumbnailRects.contains { paddedRect.intersects($0) }
      let intersectsVisibleArea = estimatedRect.intersects(CGRect(origin: .zero, size: size))

      if !intersectsOtherThumbnail {
        drawnThumbnailRects.append(estimatedRect)

        if intersectsVisibleArea {
          drawThumbnail = true
        }
      }
    }

    if startY >= 0 && endY <= size.height {
      let pillRect = CGRect(
        x: xPosition - pillWidth / 2, y: endY, width: pillWidth, height: height)
      context.fill(
        Path(roundedRect: pillRect, cornerRadius: pillWidth / 2),
        with: .color(self.color(for: period.type))
      )
    }

    if drawThumbnail {
      if let resolvedImage = context.resolveSymbol(id: period.id) {
        let staticBoxHeight = Constraints.staticBoxHeight
        let availableHeight = staticBoxHeight - 2 * thumbnailPadding
        let availableWidth = maxThumbnailSize
        let aspectRatio =
          (resolvedImage.size.width > 0 && resolvedImage.size.height > 0)
          ? resolvedImage.size.width / resolvedImage.size.height
          : 1.0

        let thumbnailWidth: CGFloat
        let thumbnailHeight: CGFloat
        if availableWidth / availableHeight > aspectRatio {
          thumbnailHeight = availableHeight
          thumbnailWidth = availableHeight * aspectRatio
        } else {
          thumbnailWidth = availableWidth
          thumbnailHeight = availableWidth / aspectRatio
        }

        let thumbnailRect = CGRect(
          x: thumbnailSpacing,
          y: pillCenterY - thumbnailHeight / 2,
          width: thumbnailWidth,
          height: thumbnailHeight
        )

        context.draw(resolvedImage, in: thumbnailRect)

        let boxSpacingFromPill = Constraints.boxSpacingFromPill
        // Draw a connected caption box aligned with the event pill.
        let boxRect = CGRect(
          x: xPosition + pillWidth / 2 + boxSpacingFromPill,
          y: pillCenterY - staticBoxHeight / 2,
          width: (thumbnailSpacing + thumbnailWidth + thumbnailPadding)
            - (xPosition + pillWidth / 2 + boxSpacingFromPill),
          height: staticBoxHeight
        )
        let boxPath = Path(roundedRect: boxRect, cornerRadius: Constraints.boxCornerRadius)
        context.stroke(boxPath, with: .color(.gray.opacity(0.3)), lineWidth: Constraints.boxBorderWidth)

        var linePath = Path()
        linePath.move(to: CGPoint(x: xPosition + pillWidth / 2, y: pillCenterY))
        linePath.addLine(to: CGPoint(x: boxRect.minX, y: pillCenterY))
        context.stroke(linePath, with: .color(.gray.opacity(0.3)), lineWidth: Constraints.lineBorderWidth)

        if let caption = period.historyItem?.caption {
          let textRect = CGRect(
            x: boxRect.minX + Constraints.captionPadding,
            y: boxRect.minY + Constraints.captionPadding,
            width: boxRect.width - thumbnailWidth - thumbnailPadding - Constraints.captionDoublePadding,
            height: boxRect.height - Constraints.captionDoublePadding
          )
          let text = Text(caption).font(.caption).foregroundColor(.primary)
          context.draw(text, in: textRect)
        }
      }
    }
  }

  private func color(for type: TimelineType) -> Color {
    switch type {
    case .cameraStatus:
      return .gray
    case .recording:
      return .blue
    case .event:
      return .orange
    }
  }
}

private let signposter = OSSignposter(
  subsystem: "com.google.HomePlatform", category: "CameraTimeline")
private let logger = Logger(
  subsystem: "com.google.HomePlatform", category: "CameraTimeline")

private struct TimelineThumbnailView: View {
  let thumbnailProvider: @Sendable () async throws -> Data?
  let maxSize: CGFloat
  @State private var image: UIImage?

  var body: some View {
    Group {
      if let image = self.image {
        Image(uiImage: image)
          .resizable()
          .aspectRatio(contentMode: .fit)
      } else {
        Color.clear
          .frame(width: self.maxSize, height: self.maxSize)
          .overlay {
            ProgressView()
          }
      }
    }
    .task {
      let state = signposter.beginInterval("ThumbnailLoading")
      defer { signposter.endInterval("ThumbnailLoading", state) }
      do {
        if let data = try await self.thumbnailProvider() {
          self.image = UIImage(data: data)
        }
      } catch {
        logger.error("Failed to load thumbnail: \(error)")
      }
    }
  }
}

/// Displays the time of the playhead.
private struct PlayheadTimeView: View, Animatable {
  var referenceDate: Date
  var scrollOffset: CGFloat
  var pointsPerSecond: CGFloat

  nonisolated var animatableData: CGFloat {
    get { self.scrollOffset }
    set { self.scrollOffset = newValue }
  }

  var body: some View {
    let date = self.referenceDate.addingTimeInterval(-Double(self.scrollOffset / self.pointsPerSecond))
    Text(date, format: .dateTime.hour().minute().second())
  }
}

/// Displays the date of the playhead.
private struct PlayheadDateView: View, Animatable {
  var referenceDate: Date
  var scrollOffset: CGFloat
  var pointsPerSecond: CGFloat
  var calendar: Calendar

  nonisolated var animatableData: CGFloat {
    get { self.scrollOffset }
    set { self.scrollOffset = newValue }
  }

  var body: some View {
    let date = self.referenceDate.addingTimeInterval(-Double(self.scrollOffset / self.pointsPerSecond))
    if self.calendar.isDateInToday(date) {
      Text("Today")
    } else if self.calendar.isDateInYesterday(date) {
      Text("Yesterday")
    } else {
      Text(date, format: .dateTime.month(.wide).day())
    }
  }
}

/// A helper view that makes the Canvas scroll offset animatable.
private struct AnimatableTimelineCanvas<Symbols: View>: View, Animatable {
  var scrollOffset: CGFloat
  var presentationState: ScrollPresentationState
  var periods: CameraTimelinePeriodList
  var referenceDate: Date
  var pointsPerSecond: CGFloat
  var topPadding: CGFloat
  var viewportHeight: CGFloat
  var draw: (GraphicsContext, CGSize, CGFloat, CameraTimelinePeriodListSlice) -> Void
  @ViewBuilder var symbols: (CameraTimelinePeriodListSlice) -> Symbols

  init(
    scrollOffset: CGFloat,
    presentationState: ScrollPresentationState,
    periods: CameraTimelinePeriodList,
    referenceDate: Date,
    pointsPerSecond: CGFloat,
    topPadding: CGFloat,
    viewportHeight: CGFloat,
    draw: @escaping (GraphicsContext, CGSize, CGFloat, CameraTimelinePeriodListSlice) -> Void,
    @ViewBuilder symbols: @escaping (CameraTimelinePeriodListSlice) -> Symbols
  ) {
    self.scrollOffset = scrollOffset
    self.presentationState = presentationState
    self.periods = periods
    self.referenceDate = referenceDate
    self.pointsPerSecond = pointsPerSecond
    self.topPadding = topPadding
    self.viewportHeight = viewportHeight
    self.draw = draw
    self.symbols = symbols
  }

  nonisolated var animatableData: CGFloat {
    get { self.scrollOffset }
    set {
      self.scrollOffset = newValue
      self.presentationState.offset = newValue
    }
  }

  var body: some View {
    let viewportTopDate = self.referenceDate.addingTimeInterval(
      Double((self.topPadding - self.scrollOffset) / self.pointsPerSecond))
    let viewportBottomDate = self.referenceDate.addingTimeInterval(
      -Double((self.viewportHeight - self.topPadding + self.scrollOffset) / self.pointsPerSecond))

    let buffer = viewportTopDate.timeIntervalSince(viewportBottomDate)

    let intersectingPeriods = self.periods.intersectingPeriods(
      in: viewportBottomDate.addingTimeInterval(-buffer)...viewportTopDate.addingTimeInterval(buffer)
    )

    Canvas { context, size in
      self.draw(context, size, self.scrollOffset, intersectingPeriods)
    } symbols: {
      self.symbols(intersectingPeriods)
    }
  }
}

/// Tracks the presentation value of the scroll offset during animations.
/// Marked as `@unchecked Sendable` because it uses internal lock synchronization to safely update
/// animatable canvas offset properties across main thread graphics contexts.
private final class ScrollPresentationState: @unchecked Sendable {
  private let lock = NSLock()
  private var _offset: CGFloat = 0

  var offset: CGFloat {
    get {
      self.lock.lock()
      defer { self.lock.unlock() }
      return self._offset
    }
    set {
      self.lock.lock()
      defer { self.lock.unlock() }
      self._offset = newValue
    }
  }
}

/// Helper function to restrict a value to a given range.
private func clamp<T: Comparable>(_ value: T, lowerBound: T, upperBound: T) -> T {
  return min(max(value, lowerBound), upperBound)
}

private struct VideoUnavailableOverlay: View {
  let reason: String?

  var body: some View {
    VStack(spacing: .xxs) {
      Text("Video Unavailable")
        .font(.caption.bold())
      if let reason = self.reason {
        Text(reason)
          .font(.caption2)
          .opacity(CameraTimelineView.Constraints.unavailableOverlayOpacity)
      }
    }
    .padding(.horizontal, CameraTimelineView.Constraints.unavailableOverlayHorizontalPadding)
    .padding(.vertical, CameraTimelineView.Constraints.unavailableOverlayVerticalPadding)
    .background(Color(.systemBackground).opacity(CameraTimelineView.Constraints.unavailableOverlayOpacity))
    .cornerRadius(CameraTimelineView.Constraints.unavailableOverlayCornerRadius)
    .shadow(color: .black.opacity(CameraTimelineView.Constraints.shadowOpacity), radius: CameraTimelineView.Constraints.unavailableOverlayShadowRadius)
  }
}

private struct CalendarPickerSheet: View {
  @State private var selectedDate = Date()
  let onSelect: (Date) -> Void

  var body: some View {
    VStack {
      HStack {
        Spacer()
        Text("Select Date").font(.headline)
        Spacer()
      }
      .overlay(alignment: .trailing) {
        Button {
          self.onSelect(self.selectedDate)
        } label: {
          Text("Apply").bold()
        }
      }
      .padding(.horizontal)
      .padding(.top)

      DatePicker(
        "",
        selection: self.$selectedDate,
        in: ...Date(),
        displayedComponents: [.date]
      )
      .datePickerStyle(.graphical)
    }
  }
}
