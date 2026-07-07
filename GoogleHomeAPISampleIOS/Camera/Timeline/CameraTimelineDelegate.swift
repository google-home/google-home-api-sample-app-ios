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

/// A delegate for a camera timeline view, allowing for the timeline to retrieve periods from the
/// remote traits.
@MainActor
public protocol CameraTimelineDelegate: AnyObject, ObservableObject {
  /// Returns the timeline periods for the given start and end dates.
  var timelinePeriods: CameraTimelinePeriodList { get }

  /// Returns true if the timeline is currently loading.
  var isTimelineLoading: Bool { get }

  /// The date that should be centered on the timeline playhead. If nil, the timeline will be at the
  /// live edge.
  var currentTimelineDate: Date? { get }

  /// Called when the timeline time is changed.
  func timelineTimeDidChange(_ time: Date)

  /// Called when the state of the timeline is changed.
  func timelineStateDidChange(_ state: CameraTimelineState)
}

/// The state of the camera timeline view.
public enum CameraTimelineState {
  case scrubbing
  case stopped
  case live
}
