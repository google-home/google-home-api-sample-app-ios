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

import GoogleHomeSDK
import GoogleHomeTypes
import SwiftUI
import UIKit
import WebRTC

/// A view of the camera, its controls, and settings options.
public struct CameraDetailView<T: DeviceType>: View {
  @ObservedObject private var deviceControl: DeviceControl
  private let home: Home

  init(home: Home, deviceControl: DeviceControl) {
    self.deviceControl = deviceControl
    self.home = home
  }

  public var body: some View {
    VStack(spacing: .sm) {
      Text(self.deviceControl.tileInfo.title)
        .font(.title3)
        .fontWeight(.bold)
        .padding(.top, .sm)

      Divider()
        .padding(.horizontal)

      CameraLiveView(home: self.home, deviceControl: self.deviceControl)

      Spacer()

      NavigationLink(
        destination: CameraSettingsView<T>(home: self.home, deviceID: self.deviceControl.id)
      ) {
        Text("Settings")
          .font(.subheadline.bold())
          .foregroundColor(.blue)
          .padding(.vertical, .sm)
      }
    }
  }
}

/// A view for camera livestreaming and control.
public struct CameraLiveView: View {
  private enum Constraints {
    static let videoAspectRatio: CGFloat = 1.77
    static let timelineHeight: CGFloat = 240.0
    static let playerCornerRadius: CGFloat = 12.0
    static let placeholderOpacity: CGFloat = 0.05
    static let strokeOpacity: CGFloat = 0.2
    static let controlBarHeight: CGFloat = 48.0
    static let micButtonPadding: CGFloat = 12.0
    static let micButtonBackgroundOpacity: CGFloat = 0.12
    static let offButtonBackgroundOpacity: CGFloat = 0.85
  }

  @State private var viewModel: CameraLiveViewModel?
  @State private var videoRenderer: RTCMTLVideoView?
  private let home: Home
  private let deviceControl: DeviceControl

  init(home: Home, deviceControl: DeviceControl) {
    self.home = home
    self.deviceControl = deviceControl
  }

  public var body: some View {
    VStack(spacing: .mmd) {
      if let viewModel = self.viewModel {
        playerView
          .frame(maxWidth: .infinity)
          .padding(.horizontal)

        controlButtonsView

        Divider()
          .padding(.horizontal)

        CameraTimelineScreen(delegate: viewModel)
          .frame(height: Constraints.timelineHeight)
      }
    }
    .task {
      videoRenderer = RTCMTLVideoView()
      if let renderer = self.videoRenderer {
        viewModel = CameraLiveViewModel(
          home: self.home,
          deviceID: self.deviceControl.id,
          renderer: renderer
        )
      }
    }
    .onDisappear {
      if let viewModel = self.viewModel {
        viewModel.leaveStreamView()
      }
    }
  }

  @ViewBuilder
  private var playerView: some View {
    if let viewModel = self.viewModel {
      Group {
        switch viewModel.playerState {
        case .historicalPlayback(let url, let headers):
          HistoricalPlaybackView(
            url: url,
            headers: headers,
            aspectRatio: Constraints.videoAspectRatio,
            onTimeChanged: { offset in
              viewModel.onPlaybackTimeChanged(offset: offset)
            }
          )
        case .scrubbing:
          ZStack {
            Color.black.opacity(Constraints.placeholderOpacity)
            VStack(spacing: .sm) {
              ProgressView()
              Text("Scrubbing...")
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
        case .live:
          livePlayerView
        case .noVideo(let reason):
          ZStack {
            Color.black.opacity(Constraints.placeholderOpacity)
            Text(reason ?? "Unable to play video.")
              .font(.subheadline)
              .foregroundColor(.secondary)
          }
        }
      }
      .aspectRatio(Constraints.videoAspectRatio, contentMode: .fit)
      .cornerRadius(Constraints.playerCornerRadius)
      .overlay(
        RoundedRectangle(cornerRadius: Constraints.playerCornerRadius)
          .stroke(Color.gray.opacity(Constraints.strokeOpacity), lineWidth: 1)
      )
    }
  }

  @ViewBuilder
  private var livePlayerView: some View {
    if let viewModel = self.viewModel {
      switch viewModel.uiState {
      case .loading:
        ZStack {
          Color.black.opacity(Constraints.placeholderOpacity)
          ProgressView()
        }
      case .live:
        if let renderer = self.videoRenderer {
          LiveStreamView(videoRendererView: renderer)
        }
      case .off:
        ZStack {
          Color.black.opacity(Constraints.placeholderOpacity)
          Text("Camera is OFF")
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
      case .disconnected:
        ZStack {
          Color.black.opacity(Constraints.placeholderOpacity)
          VStack(spacing: .sm) {
            Text("Stream disconnected")
              .font(.caption)
              .foregroundColor(.secondary)
            Button("Retry") {
              viewModel.reconnectStream()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
          }
        }
      }
    }
  }

  @ViewBuilder
  private var controlButtonsView: some View {
    if let viewModel = self.viewModel {
      HStack(spacing: .lg) {
        if viewModel.uiState == .live {
          Button(action: {
            viewModel.toggleTwoWayTalk(isOn: !viewModel.isTwoWayTalkOn)
          }) {
            Image(systemName: viewModel.isTwoWayTalkOn ? "mic.fill" : "mic.slash.fill")
              .font(.title3)
              .padding(Constraints.micButtonPadding)
              .background(Circle().fill(Color.gray.opacity(Constraints.micButtonBackgroundOpacity)))
              .foregroundColor(.primary)
          }

          Button(action: {
            viewModel.toggleIsRecording(isOn: false)
          }) {
            Text("Turn Camera OFF")
              .font(.subheadline.bold())
              .foregroundColor(.white)
              .padding(.horizontal, .md)
              .padding(.vertical, .sm)
              .background(Capsule().fill(Color.red.opacity(Constraints.offButtonBackgroundOpacity)))
          }
        } else if viewModel.uiState == .off {
          Button(action: {
            viewModel.toggleIsRecording(isOn: true)
          }) {
            Text("Turn Camera ON")
              .font(.subheadline.bold())
              .foregroundColor(.white)
              .padding(.horizontal, .lg)
              .padding(.vertical, .sm)
              .background(Capsule().fill(Color.blue))
          }
        }
      }
      .frame(height: Constraints.controlBarHeight)
    }
  }
}

public struct LiveStreamView: UIViewRepresentable {
  public let videoRendererView: RTCMTLVideoView

  public init(videoRendererView: RTCMTLVideoView) {
    self.videoRendererView = videoRendererView
    self.videoRendererView.isEnabled = true
  }

  public func makeUIView(context: Context) -> RTCMTLVideoView {
    videoRendererView.contentMode = .scaleAspectFit
    return videoRendererView
  }

  public func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {}

  public static func dismantleUIView(_ uiView: RTCMTLVideoView, coordinator: ()) {
    uiView.isEnabled = false
  }
}
