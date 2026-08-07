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
import GoogleHomeTypes
import SwiftUI
import OSLog

private enum Constants {
  static let saveButton = "Save"
  static let navigationTitle = "Event triggers"
  static let motion = "Motion"
  static let person = "Person"
  static let vehicle = "Vehicle"
  static let animal = "Animal"
  static let package = "Package"
  static let sound = "Sound"
  static let personTalking = "Person Talking"
  static let dogBark = "Dog Bark"
  static let glassBreak = "Glass Break"
  static let smokeAlarm = "Smoke Alarm"
  static let coAlarm = "CO Alarm"
  static let packageDelivered = "Package Delivered"
  static let packageRetrieved = "Package Retrieved"
  static let garageDoor = "Garage Door"
  static let videoAnalysisDescription = "Video Analysis Description (AI Caption)"
  static let unknown = "Unknown"
}

struct EventTriggerSettingsView<T: DeviceType>: View {
  @Binding var eventTriggers: [CameraSettingsViewModel<T>.EventTrigger]
  let saveCallback: () async throws -> Void
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    List {
      Section {
        ForEach($eventTriggers) { $trigger in
          Toggle(isOn: $trigger.enabled) {
            Text(eventTriggerDisplayName(eventTrigger: trigger.id))
          }
        }
      }
    }
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        Button {
          Task {
            do {
              try await saveCallback()
            } catch {
              Logger().error("Error saving event triggers: \(error)")
            }
            dismiss()
          }
        } label: {
          Text(Constants.saveButton)
        }
      }
    }
    .navigationTitle(Constants.navigationTitle)
  }
  /// String conversion for the Google.AvStreamAnalysisTrait.EventTriggerTypeEnum enum.
  private func eventTriggerDisplayName(
    eventTrigger: Google.AvStreamAnalysisTrait.EventTriggerTypeEnum
  ) -> String {
    switch eventTrigger {
    case .motion: return Constants.motion
    case .personDetected: return Constants.person
    case .vehicleDetected: return Constants.vehicle
    case .animalDetected: return Constants.animal
    case .packageDetected: return Constants.package
    case .sound: return Constants.sound
    case .personTalking: return Constants.personTalking
    case .dogBark: return Constants.dogBark
    case .glassBreak: return Constants.glassBreak
    case .smokeAlarm: return Constants.smokeAlarm
    case .coAlarm: return Constants.coAlarm
    case .packageDelivered: return Constants.packageDelivered
    case .packageRetrieved: return Constants.packageRetrieved
    case .garageDoor: return Constants.garageDoor
    case .videoAnalysisDescription: return Constants.videoAnalysisDescription
    default: return Constants.unknown
    }
  }
}
