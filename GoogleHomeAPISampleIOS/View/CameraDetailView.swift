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

/// A view of camera.
public struct CameraDetailView: View {
  @ObservedObject private var deviceControl: DeviceControl
  private let home: Home

  init(home: Home, deviceControl: DeviceControl) {
    self.deviceControl = deviceControl
    self.home = home
  }

  public var body: some View {
    VStack {
      Text(self.deviceControl.tileInfo.title)
        .font(.title)
        .fontWeight(.bold)
      Divider()
        .padding(.bottom, .smd)
      CameraLiveView(home: self.home, deviceControl: self.deviceControl)
    }
  }
}

/// A view for camera livestreaming and control.
public struct CameraLiveView: View {
  @State private var viewModel: CameraLiveViewModel?
  @State private var videoRenderer: RTCMTLVideoView?
  private let home: Home
  private let deviceControl: DeviceControl
  private let liveViewHeight: CGFloat?

  init(home: Home, deviceControl: DeviceControl) {
    self.home = home
    self.deviceControl = deviceControl
    switch deviceControl {
    case is CameraControl:
      liveViewHeight = 200
    case is DoorbellControl:
      liveViewHeight = nil
    default:
      liveViewHeight = 200
    }
  }

  public var body: some View {
    VStack {
      if let viewModel = self.viewModel {
        switch viewModel.uiState {
        case .loading:
          ProgressView().frame(height: 300)
        case .live:
          if let renderer = self.videoRenderer {
            LiveStreamView(videoRendererView: renderer)
              .frame(height: liveViewHeight)
          }
          Spacer()
          Button("Turn Camera OFF") {
            viewModel.toggleIsRecording(isOn: false)
          }
          .buttonStyle(.borderedProminent)
          Spacer()
          Button(action: {
            viewModel.toggleTwoWayTalk(isOn: !viewModel.isTwoWayTalkOn)
          }) {
            Image(systemName: viewModel.isTwoWayTalkOn ? "mic.fill" : "mic.slash.fill")
              .font(.title)
              .padding()
              .background(Circle().fill(.gray.opacity(0.2)))
          }
        case .off:
          Text("Camera is OFF").frame(height: 300)
          Spacer()
          Button("Turn Camera ON") {
            viewModel.toggleIsRecording(isOn: true)
          }
          .buttonStyle(.borderedProminent)
        case .disconnected:
          Text("The stream has disconnected.")
          Spacer()
          Button("Retry Connection") {
            viewModel.reconnectStream()
          }
          .buttonStyle(.borderedProminent)
        }
        Spacer()
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
