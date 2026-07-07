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

import SwiftUI

/// A screen that displays the camera timeline for a specific device.
public struct CameraTimelineScreen<Delegate: CameraTimelineDelegate>: View {

  @ObservedObject private var delegate: Delegate

  /// Initializes the camera timeline screen and view model.
  /// - Parameters:
  ///   - delegate: The delegate for the camera timeline view.
  public init(delegate: Delegate) {
    self.delegate = delegate
  }

  /// The view body.
  public var body: some View {
    CameraTimelineView(
      periods: delegate.timelinePeriods,
      isLoading: delegate.isTimelineLoading,
      onTimeChange: { time in
        delegate.timelineTimeDidChange(time)
      },
      onStateChange: { state in
        delegate.timelineStateDidChange(state)
      },
      currentTimelineDate: delegate.currentTimelineDate
    )
  }
}
