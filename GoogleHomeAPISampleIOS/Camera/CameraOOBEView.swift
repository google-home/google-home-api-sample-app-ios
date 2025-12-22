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
      case .otaDownload:
        OTAView(viewModel: self.viewModel)
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

  private struct OTAView: View {
    private let viewModel: CameraOOBEViewModel<T>

    init(viewModel: CameraOOBEViewModel<T>) {
      self.viewModel = viewModel
    }

    var body: some View {
      VStack {
        Image(systemName: "icloud.and.arrow.down")
          .resizable()
          .scaledToFit()
          .frame(width: 80, height: 80)
          .foregroundColor(.blue)
          .padding(.bottom, 10)
        Text("OTA Software Update")
          .font(.title2)
          .fontWeight(.bold)
        Text(
          "During this step of the setup process, "
            + "the device will download a software update if necessary. "
            + "Check the OTA update status before proceeding to the next step."
        )
        .multilineTextAlignment(.center)
        .foregroundColor(.primary)
        .padding(.top, 4)
        Text("For more information, visit")
          .multilineTextAlignment(.center)
          .foregroundColor(.secondary)
          .padding(.top, 4)
        if let url = URL(string: "https://developers.home.google.com/") {
          Link("https://developers.home.google.com", destination: url)
            .font(.subheadline)
        }
        Spacer()
        Button(action: {
          self.viewModel.nextStep()
        }) {
          Text("Next")
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .cornerRadius(12)
        }
      }
      .padding(24)
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
