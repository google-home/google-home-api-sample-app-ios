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

/// A generic view for renaming an entity, using a view model.
struct RenameView: View {
  @StateObject var viewModel: RenameViewModel
  @Environment(\.dismiss) var dismiss

  var body: some View {
    ZStack(alignment: .bottom) {
      VStack(alignment: .leading, spacing: 8) {
        Text(viewModel.title)
          .font(.headline)
        Text(viewModel.subtitle)
          .font(.subheadline)

        VStack(alignment: .leading, spacing: 2) {
          Text(viewModel.textFieldLabel)
            .font(.caption)

          TextField("", text: $viewModel.name)
            .border(.secondary)
            .textFieldStyle(.roundedBorder)
            .padding()
        }
        .padding(.top, 20)

        Spacer()
      }

      HStack {
        Spacer()
        Button(action: save) {
          Text("Save")
            .frame(
              width: Dimensions.buttonWidth, height: Dimensions.buttonHeight
            )
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(Dimensions.cornerRadius)
        }
      }
      .padding([.horizontal, .bottom])
    }
    .padding()
  }

  private func save() {
    Task {
      if await viewModel.save() {
        dismiss()
      }
    }
  }
}
