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

/// A view for the camera device settings, which is also shown in the OOBE process.
public struct CameraSettingsView<T: DeviceType>: View {

  /// The flow that initiated the camera settings view.
  ///
  /// This is used to determine which settings to show.
  public enum InitiatingFlow {
    /// The default full settings flow.
    case settings

    /// The OOBE flow.
    case oobe
  }

  @State private var viewModel: CameraSettingsViewModel<T>

  public init(home: Home, deviceID: String, initiatingFlow: InitiatingFlow = .settings) {
    self._viewModel = State(
      initialValue: CameraSettingsViewModel<T>(
        home: home, deviceID: deviceID, initiatingFlow: initiatingFlow)
    )
  }

  public var body: some View {
    guard viewModel.settingsInitialized else {
      return AnyView(ProgressView())
    }

    return AnyView(
      List {
        if viewModel.displayedSettings.contains(.microphone) {
          Section {
            Toggle(isOn: viewModel.microphoneOnController.binding) {
              HStack {
                Image(systemName: "microphone.fill")
                Text("Microphone")
                if viewModel.microphoneOnController.isLoading {
                  ProgressView()
                }
              }
            }
            .disabled(!viewModel.microphoneOnController.isEnabled)
            Toggle(isOn: viewModel.audioRecordingOnController.binding) {
              HStack {
                Image(systemName: "waveform")
                Text("Audio Recording")
                if viewModel.audioRecordingOnController.isLoading {
                  ProgressView()
                }
              }
            }
            .disabled(
              !self.viewModel.audioRecordingOnController.isEnabled
                || !self.viewModel.microphoneOnController.value)
          } header: {
            Text("Microphone Settings")
          } footer: {
            Text(
              "When audio recording is off, the microphone still lets you hear live audio, "
                + "but it won't be saved to your history."
            )
          }
        }
        if viewModel.displayedSettings.contains(.camera) {
          Section {
            Picker(selection: viewModel.imageRotationController.binding) {
              ForEach(viewModel.imageRotationSettings, id: \.self) { imageRotation in
                Text("\(imageRotation)°")
              }
            } label: {
              HStack {
                Text("Image Rotation")
                if viewModel.imageRotationController.isLoading {
                  ProgressView()
                }
              }
            }.disabled(!viewModel.imageRotationController.isEnabled)
            Picker(selection: viewModel.nightVisionController.binding) {
              ForEach(viewModel.nightVisionSettings, id: \.self) { nightVision in
                Text(viewModel.triStateAutoEnumDisplayName(setting: nightVision))
              }
            } label: {
              HStack {
                Text("Night Vision")
                if viewModel.nightVisionController.isLoading {
                  ProgressView()
                }
              }
            }.disabled(!viewModel.nightVisionController.isEnabled)
            VStack {
              HStack {
                Text(
                  "Camera Speaker Volume: \(Int(viewModel.speakerVolumeController.binding.wrappedValue))"
                )
                if viewModel.speakerVolumeController.isLoading {
                  ProgressView()
                }
                Spacer()
              }
              Slider(
                value: viewModel.speakerVolumeController.binding,
                in: 0...100,
                step: 1,
                onEditingChanged: { editing in
                  if !editing {
                    Task {
                      await viewModel.speakerVolumeController.manualRemoteUpdateValue()
                    }
                  }
                }
              ).disabled(!viewModel.speakerVolumeController.isEnabled)
            }
            Picker(selection: viewModel.statusLightBrightnessController.binding) {
              ForEach(viewModel.statusLightBrightnessSettings, id: \.self) {
                statusLightBrightness in
                Text(viewModel.threeLevelAutoEnumDisplayName(setting: statusLightBrightness))
              }
            } label: {
              HStack {
                Text("Status Light Brightness")
                if viewModel.statusLightBrightnessController.isLoading {
                  ProgressView()
                }
              }
            }.disabled(!viewModel.statusLightBrightnessController.isEnabled)
          } header: {
            Text("Camera Settings")
          }
        }

        if viewModel.displayedSettings.contains(.doorbell) {
          Section {
            Picker(selection: viewModel.doorbellChimeController.binding) {
              ForEach(viewModel.doorbellChimeSettings, id: \.id) { doorbellChime in
                Text("\(doorbellChime.displayName)").tag(doorbellChime)
              }
            } label: {
              HStack {
                Text("Doorbell Chime")
                if viewModel.doorbellChimeController.isLoading {
                  ProgressView()
                }
              }
            }
            .disabled(!viewModel.doorbellChimeController.isEnabled)
            Picker(selection: viewModel.externalChimeController.binding) {
              ForEach(viewModel.externalChimeSettings, id: \.self) { externalChime in
                Text(viewModel.externalChimeDisplayName(setting: externalChime))
              }
            } label: {
              HStack {
                Text("Doorbell Chime Type")
                if viewModel.externalChimeController.isLoading {
                  ProgressView()
                }
              }
            }
            .disabled(!viewModel.externalChimeController.isEnabled)
          } header: {
            Text("Doorbell Settings")
          }
        }

        if viewModel.displayedSettings.contains(.battery) {
          Section {
            Picker(selection: viewModel.wakeUpSensitivityController.binding) {
              ForEach(viewModel.wakeUpSensitivitySettings, id: \.self) { wakeUpSensitivity in
                Text(viewModel.wakeUpSensitivityDisplayName(setting: wakeUpSensitivity))
              }
            } label: {
              HStack {
                Text("Wake Up Sensitivity")
                if viewModel.wakeUpSensitivityController.isLoading {
                  ProgressView()
                }
              }
            }.disabled(!viewModel.wakeUpSensitivityController.isEnabled)
            Picker(selection: viewModel.maxEventLengthController.binding) {
              ForEach(viewModel.maxEventLengthSettings, id: \.self) { maxEventLength in
                Text("\(maxEventLength)s")
              }
            } label: {
              HStack {
                Text("Max Event Length")
                if viewModel.maxEventLengthController.isLoading {
                  ProgressView()
                }
              }
            }.disabled(!viewModel.maxEventLengthController.isEnabled)
          } header: {
            Text("Battery Settings")
          }
        }

        if viewModel.displayedSettings.contains(.information) {
          Section {
            HStack {
              Text("Vendor Name")
              Spacer()
              Text("\(viewModel.vendorName ?? "N/A")")
                .foregroundColor(.gray)
            }
            HStack {
              Text("Model Name")
              Spacer()
              Text("\(viewModel.productName ?? "N/A")")
                .foregroundColor(.gray)
            }
            HStack {
              Text("Software Version")
              Spacer()
              Text("\(viewModel.softwareVersionString ?? "N/A")")
                .foregroundColor(.gray)
            }
          } header: {
            Text("Device Information")
          }
        }
      }
    )
  }
}
