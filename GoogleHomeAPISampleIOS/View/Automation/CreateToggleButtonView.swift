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

import SwiftUI

struct CreateToggleButtonView: View {
  @Binding var isOn: Bool
  let leftText: String
  let rightText: String
  var body: some View {
    ZStack {
      Capsule()
        .fill(Color.gray.opacity(0.3))

      Capsule()
        .fill(Color.blue)
        .frame(width: (UIScreen.main.bounds.width - 80) / 2) // Half width of screen minus padding
        .offset(x: isOn ? -(UIScreen.main.bounds.width - 80) / 4 : (UIScreen.main.bounds.width - 80) / 4)
        .animation(.easeInOut(duration: 0.2), value: isOn)

      HStack {
        Text(leftText)
          .foregroundColor(Color("fontColor"))
          .padding(.horizontal, 16)
          .padding(.vertical, 8)
        Spacer()
        Text(rightText)
          .foregroundColor(Color("fontColor"))
          .padding(.horizontal, 16)
          .padding(.vertical, 8)
      }
    }
    .frame(width: UIScreen.main.bounds.width - 80, height: 60)
    .onTapGesture {
        isOn.toggle()
    }
  }
}
