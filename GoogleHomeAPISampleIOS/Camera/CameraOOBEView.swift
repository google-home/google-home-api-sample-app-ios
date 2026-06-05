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
import GoogleHomeSDK
import GoogleHomeTypes
import OSLog
import SwiftUI

/// A view of the OOBE setup process (OTA Download -> Settings -> Done).
public struct CameraOOBEView<T: DeviceType>: View {
  private let device: HomeDevice
  @State private var viewModel: CameraOOBEViewModel<T>

  public init(home: Home, device: HomeDevice) {
    self.device = device
    self.viewModel = CameraOOBEViewModel(home: home, device: device)
  }

  public var body: some View {
    VStack {
      switch viewModel.step {
      case .otaDownload(let state, let progress):
        OtaDownloadView(state: state, progress: progress)
      case .settings:
        CameraSettingsView<T>(
          home: self.viewModel.home, deviceID: self.device.id, initiatingFlow: .oobe
        )
        .toolbar {
          ToolbarItem(placement: .primaryAction) {
            Button("Next") {
              self.viewModel.nextStep()
            }
          }
        }
      case .done:
        DoneView(viewModel: self.viewModel)
      }

    }
    .navigationTitle(device.name)
    .navigationBarTitleDisplayMode(.inline)
  }

  private struct OtaDownloadView: View {
    let state: Matter.OtaSoftwareUpdateRequestorTrait.UpdateStateEnum
    let progress: Double

    var body: some View {
      VStack {
        Text("Downloading software update...")
        Text("State: \(state.description)")
        ProgressView(value: progress) { Text("Progress: \(progress.formatted(.percent))") }
          .padding()
      }
    }
  }

  private struct DoneView: View {
    @Environment(\.dismiss) private var dismiss
    private let viewModel: CameraOOBEViewModel<T>

    init(viewModel: CameraOOBEViewModel<T>) {
      self.viewModel = viewModel
    }

    var body: some View {
      VStack {
        Image(systemName: "checkmark.circle")
          .resizable()
          .scaledToFit()
          .frame(width: 80, height: 80)
          .foregroundColor(.blue)
          .padding(.bottom, 10)
        Text("Setup complete!")
          .font(.title2)
          .fontWeight(.bold)
      }.toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button("Done") {
            Task { @MainActor in
              do {
                try await self.viewModel.configurationDone()
              } catch {
                Logger().error("Failed to mark configuration done: \(error)")
              }
              self.dismiss()
            }
          }
        }
      }
    }
  }
}

extension Matter.OtaSoftwareUpdateRequestorTrait.UpdateStateEnum {
  public var description: String {
    switch self {
    case .unknown:
      return "Unknown"
    case .idle:
      return "Idle"
    case .querying:
      return "Querying"
    case .delayedOnQuery:
      return "Delayed on query"
    case .downloading:
      return "Downloading"
    case .applying:
      return "Applying"
    case .delayedOnApply:
      return "Delayed on apply"
    case .rollingBack:
      return "Rolling back"
    case .delayedOnUserConsent:
      return "Delayed on user consent"
    case .unrecognized_:
      return "Unrecognized"
    @unknown default:
      return "Unknown"
    }
  }
}
