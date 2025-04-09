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

struct CreateButtonView: View {
    let imageName: String
    let text1: String
    let text2: String
    let action: () -> Void // Add action parameter

    var body: some View {
      Button(action: {
        action() // Call the provided action
      }) {
        HStack {
          Image(imageName)
          VStack(alignment:.leading) {
            Text(text1)
              .frame(maxWidth: .infinity, alignment: .leading)
              .lineLimit(1)
              .truncationMode(.tail)
              .foregroundColor(Color("fontColor"))
            if !text2.isEmpty {
                Text(text2)
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .font(.footnote)
                  .lineLimit(1)
                  .truncationMode(.tail)
                  .foregroundColor(Color("fontColor"))
            }
          }
        }
      }
      .buttonStyle(.bordered)
      .frame(maxWidth: .infinity, maxHeight: 80)
      .buttonBorderShape(.roundedRectangle)
    }
}
