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

import Foundation

struct DeviceTileInfo {

  var title: String
  var imageName: String
  var isActive: Bool
  var isBusy: Bool
  var statusLabel: String
  var error: (any Error)?

  // MARK: - Initialization

  init(
    title: String,
    imageName: String,
    isActive: Bool,
    isBusy: Bool,
    statusLabel: String,
    error: (any Error)?
  ) {
    self.title = title
    self.imageName = imageName
    self.isActive = isActive
    self.isBusy = isBusy
    self.statusLabel = statusLabel
    self.error = error
  }

  /// Create the `DeviceTileInfo` model object for a HomeError that occurs upstream while
  /// subscribing to traits.
  ///
  /// The view should include an error icon and a limited explanation of what went wrong.
  static func make(forError error: any Error) -> DeviceTileInfo {
    return DeviceTileInfo(
      title: "Error: " + error.localizedDescription,
      imageName: "error_symbol",
      isActive: false,
      isBusy: false,
      statusLabel: "Disabled",
      error: error
    )
  }

  public static func makeLoading(title: String, imageName: String) -> DeviceTileInfo {
    return DeviceTileInfo(
      title: title,
      imageName: "imageName",
      isActive: false,
      isBusy: true,
      statusLabel: "Loading...",
      error: nil
    )
  }
}
