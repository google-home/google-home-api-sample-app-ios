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

/// A view of the camera OOBE setup process (OTA -> Settings -> Done).
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
      case .ota:
        OtaStepView(state: viewModel.otaUiState)
          .toolbar {
            if viewModel.canSkipOta {
              ToolbarItem(placement: .primaryAction) {
                Button("Next") {
                  self.viewModel.nextStep()
                }
              }
            }
          }
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
    .onDisappear {
      // Mark configuration done on exit (e.g. swipe-dismiss while waiting for the device to come
      // back online). Skipped in the settings step because its NavigationLink pushes also trigger
      // onDisappear, so a swipe-dismiss during Settings does not write ConfigurationDone.
      // finishConfiguration() is a no-op once it has succeeded.
      guard self.viewModel.step != .settings else { return }
      Task { await self.viewModel.configurationDone() }
    }
  }

  private struct OtaStepView: View {
    let state: OtaUiState

    var body: some View {
      VStack {
        Text("Software update")
          .font(.headline)
        Text(state.displayStatusText)
        progressIndicator
          .padding()
      }
    }

    @ViewBuilder
    private var progressIndicator: some View {
      switch state {
      case .downloading(let percent?, _):
        ProgressView(value: Double(percent), total: 100) { Text("Progress: \(percent)%") }
      case .loading, .checking, .downloading, .installing:
        ProgressView()
      case .delayed, .failed, .upToDate:
        EmptyView()
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
        if viewModel.isOnline {
          Image(systemName: "checkmark.circle")
            .resizable()
            .scaledToFit()
            .frame(width: 80, height: 80)
            .foregroundColor(.blue)
            .padding(.bottom, 10)
          Text("Setup complete!")
            .font(.title2)
            .fontWeight(.bold)
        } else {
          ProgressView()
          Text("Waiting for device to be online...")
        }
      }.toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button("Done") {
            Task { @MainActor in
              await self.viewModel.configurationDone()
              self.dismiss()
            }
          }
          .disabled(!viewModel.isOnline || viewModel.isLoading)
        }
      }
    }
  }
}
