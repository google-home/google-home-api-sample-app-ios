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

import Combine
import Foundation
import GoogleHomeSDK
import SwiftUI
import OSLog

struct DeviceView: View {
  @ObservedObject private var deviceControl: DeviceControl
  @ObservedObject private var structureViewModel: StructureViewModel

  let roomID: String?
  let structure: Structure

  @StateObject private var pinCodeInputState = PINCodeInputState()

  @State private var isShowingDestinationRoomPicker = false

  @Environment(\.colorScheme) var colorScheme: ColorScheme

  init(
    deviceControl: DeviceControl,
    roomID: String?,
    structure: Structure,
    structureViewModel: StructureViewModel
  ) {
    self.deviceControl = deviceControl
    self.roomID = roomID
    self.structure = structure
    self.structureViewModel = structureViewModel
  }

  private var rangeView: RangeView? {
    if let rangeControl = self.deviceControl.rangeControl,
      self.deviceControl.tileInfo.isActive
    {
      return RangeView(
        rangeControl: rangeControl,
        colorPalette: self.deviceControl.colorPalette)
    }
    return nil
  }

  var body: some View {
    ZStack {
      DeviceTileView(
        title: self.deviceControl.tileInfo.title,
        status: self.deviceControl.tileInfo.statusLabel,
        containerColor: self.deviceControl.colorPalette.onContainerColor(
          colorScheme: colorScheme, isActive: self.deviceControl.tileInfo.isActive),
        variantColor: self.deviceControl.colorPalette.containerVariantColor(
          colorScheme: colorScheme, isActive: self.deviceControl.tileInfo.isActive),
        imageName: self.deviceControl.tileInfo.imageName,
        isBusy: self.deviceControl.tileInfo.isBusy,
        rangeView: self.rangeView,
        error: self.pinCodeInputState.errorMessage,
        onTap: {
          if self.deviceControl.requiresPINCode {
            pinCodeInputState.errorMessage = nil
            pinCodeInputState.pinCode = ""
            pinCodeInputState.isEnteringPINCode = true
          } else {
            self.deviceControl.primaryAction()
          }
        })
    }
    .sheet(isPresented: self.$pinCodeInputState.isEnteringPINCode) {
      pinCodeInputView()
    }
    .sheet(isPresented: self.$isShowingDestinationRoomPicker) {
      destinationRoomPicker()
    }
    .contextMenu {
      Divider()
      Button("Move to Another Room", systemImage: "arrowshape.zigzag.right") {
        isShowingDestinationRoomPicker = true
      }
    }
  }

  private func destinationRoomPicker() -> some View {
    List {
      let entries = self.structureViewModel.entries.filter { $0.roomID != self.roomID }
      ForEach(entries) { entry in
        Button(entry.roomName) {
          self.isShowingDestinationRoomPicker = false
          self.structureViewModel.moveDevice(
            device: self.deviceControl.device.id,
            to: entry.roomID,
            structure: self.structure
          )
        }
      }
    }
    .listStyle(.insetGrouped)
  }

  func pinCodeInputView() -> some View {
    return VStack {
      let confirmAction = {
        self.pinCodeInputState.isEnteringPINCode = false
        self.deviceControl.setPINCode(self.pinCodeInputState.pinCode)
        self.deviceControl.primaryAction()
      }
      SecureField("Enter PIN Code", text: self.$pinCodeInputState.pinCode)
        .onSubmit(confirmAction)
      HStack {
        Button("Cancel", role: .cancel) {
          self.pinCodeInputState.isEnteringPINCode = false
        }
        .padding()
        Button("Confirm", role: .none, action: confirmAction)
          .padding()
      }
    }
    .padding()
    .listStyle(.insetGrouped)
  }

}
