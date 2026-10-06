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

import GoogleHomeSDK
import SwiftUI

/// A post-commissioning view displaying Matter OTA update status for non-camera Matter devices.
///
/// Cameras and doorbells use `CameraOOBEView` (OTA -> Settings -> Done) instead.
public struct OtaUpdateScreenView: View {
  private enum Constants {
    static let title = "OTA Software Update"
    static let description =
      "During setup, your device automatically receives software updates if available."
    static let done = "Done"
    static let currentVersionLabel = "Current Version:"
    static let statusLabel = "Status:"
    static let checkingPlaceholder = "Checking..."
    static let autoDismissDelay: Duration = .seconds(5)
    static let progressPercentDivisor = 100.0

    static func versionDisplay(_ version: String) -> String {
      "v\(version)"
    }
  }

  @Environment(\.dismiss) private var dismiss
  @StateObject private var viewModel: OtaUpdateViewModel
  @State private var autoDismissTask: Task<Void, Never>?

  /// Initializes the post-commissioning OTA screen for a known `HomeDevice`.
  ///
  /// - Parameters:
  ///   - home: The `Home` instance owning `device`.
  ///   - device: The newly commissioned device whose OTA state is shown.
  public init(home: Home, device: HomeDevice) {
    self._viewModel = StateObject(
      wrappedValue: OtaUpdateViewModel(home: home, device: device, isOobeFlow: true)
    )
  }

  /// The content and layout of the OTA update screen.
  public var body: some View {
    VStack(spacing: .md) {
      Spacer()

      // Title & Device Name Header
      VStack(spacing: .xs) {
        Text(Constants.title)
          .font(.title2)
          .fontWeight(.bold)
          .multilineTextAlignment(.center)

        Text(viewModel.deviceName)
          .font(.headline)
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
      }

      // Structured Status Card
      statusCard
        .padding(.horizontal, .md)

      // Subtitle / Description
      Text(Constants.description)
        .font(.footnote)
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, .md)

      Spacer()

      // Primary Action Button
      Button {
        Task {
          try? await viewModel.finishConfiguration()
          dismiss()
        }
      } label: {
        Text(Constants.done)
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
    }
    .padding(.md)
    .onAppear {
      self.scheduleAutoDismissIfNeeded(for: viewModel.otaUiState)
    }
    .onChange(of: viewModel.otaUiState) { _, newState in
      self.scheduleAutoDismissIfNeeded(for: newState)
    }
    .onDisappear {
      autoDismissTask?.cancel()
      autoDismissTask = nil
      // Any user exit (including swipe-down) completes configuration.
      // `finishConfiguration()` retries after a failure and is a no-op once it has succeeded.
      let viewModel = self.viewModel
      Task {
        try? await viewModel.finishConfiguration()
      }
    }
  }

  private func scheduleAutoDismissIfNeeded(for state: OtaUiState) {
    autoDismissTask?.cancel()
    autoDismissTask = nil
    if case .upToDate = state {
      autoDismissTask = Task {
        try? await Task.sleep(for: Constants.autoDismissDelay)
        guard !Task.isCancelled else { return }
        try? await viewModel.finishConfiguration()
        guard !Task.isCancelled else { return }
        dismiss()
      }
    }
  }

  @ViewBuilder
  private var statusCard: some View {
    VStack(alignment: .leading, spacing: .smd) {
      // 1. Current Version
      HStack {
        Text(Constants.currentVersionLabel)
          .font(.subheadline)
          .foregroundColor(.secondary)
        Spacer()
        Text(viewModel.currentVersion.map(Constants.versionDisplay) ?? Constants.checkingPlaceholder)
          .font(.subheadline)
          .fontWeight(.medium)
      }

      Divider()

      // 2. Status Description & Progress Bar
      VStack(alignment: .leading, spacing: .sm) {
        HStack {
          Text(Constants.statusLabel)
            .font(.subheadline)
            .foregroundColor(.secondary)
          Spacer()
          statusText
        }

        progressIndicator
      }
    }
    .padding(.md)
    .frame(maxWidth: .infinity)
    .background(Color(.secondarySystemBackground))
    .cornerRadius(.sm)
  }

  @ViewBuilder
  private var statusText: some View {
    let text = viewModel.otaUiState.displayStatusText
    switch viewModel.otaUiState {
    case .loading, .checking:
      Text(text)
        .font(.subheadline)
        .foregroundColor(.secondary)

    case .downloading, .installing:
      Text(text)
        .font(.subheadline)
        .foregroundColor(.blue)

    case .delayed:
      Text(text)
        .font(.subheadline)
        .foregroundColor(.orange)

    case .failed:
      Text(text)
        .font(.subheadline)
        .foregroundColor(.red)

    case .upToDate:
      Text(text)
        .font(.subheadline)
        .fontWeight(.medium)
        .foregroundColor(.green)
    }
  }

  @ViewBuilder
  private var progressIndicator: some View {
    switch viewModel.otaUiState {
    case .loading, .checking:
      ProgressView()
        .progressViewStyle(LinearProgressViewStyle())

    case .downloading(let percent, _):
      if let percent {
        ProgressView(value: Double(percent) / Constants.progressPercentDivisor)
          .progressViewStyle(LinearProgressViewStyle())
      } else {
        ProgressView()
          .progressViewStyle(LinearProgressViewStyle())
      }

    case .installing:
      ProgressView()
        .progressViewStyle(LinearProgressViewStyle())

    case .delayed, .failed, .upToDate:
      EmptyView()
    }
  }
}
