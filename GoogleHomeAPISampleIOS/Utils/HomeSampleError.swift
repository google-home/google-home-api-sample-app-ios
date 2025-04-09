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

/// the error set for device errors, input deviceType
enum HomeSampleError: Error {
  case unableToCreateControlForDeviceType(deviceType: String)
  case unableToUpdateControlForDeviceType(deviceType: String)
}

extension HomeSampleError: LocalizedError {
   var errorDescription: String? {
    switch self {
    case .unableToCreateControlForDeviceType(let deviceType):
      return "Unable to create control for device type: \(deviceType)"
    case .unableToUpdateControlForDeviceType(let deviceType):
      return "Unable to update control for device type: \(deviceType)"
    }
  }
}
