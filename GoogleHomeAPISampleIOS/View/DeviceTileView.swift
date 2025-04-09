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

import CoreFoundation
import SwiftUI

struct DeviceTileView: View {
  private let title: String
  private let status: String
  private let containerColor: Color
  private let variantColor: Color
  private let imageName: String
  private let isBusy: Bool
  private let rangeView: RangeView?
  private let error: String?
  private let onTap: (() -> Void)?

  init(
    title: String,
    status: String,
    containerColor: Color,
    variantColor: Color,
    imageName: String,
    isBusy: Bool,
    rangeView: RangeView? = nil,
    error: String? = nil,
    onTap: (() -> Void)? = nil
  ) {
    self.title = title
    self.status = status
    self.containerColor = containerColor
    self.variantColor = variantColor
    self.imageName = imageName
    self.rangeView = rangeView
    self.isBusy = isBusy
    self.error = error
    self.onTap = onTap
  }

  var body: some View {
    ZStack {
      if let rangeView {
        rangeView
      }
      HStack(alignment: .center, spacing: .deviceTileHorizontalSpacing) {
        if isBusy {
          ProgressView()
            .progressViewStyle(.circular)
            .frame(width: .deviceTileIconDimension, height: .deviceTileIconDimension)
        } else {
          Image(imageName)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(
              width: .deviceTileIconDimension,
              height: .deviceTileIconDimension,
              alignment: .center
            )
        }
        VStack(alignment: .leading) {
          Text(title)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .font(.subheadline)
          Text(status)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .font(.subheadline)
          if let error {
            Text(error)
              .foregroundColor(.red)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
      }
      .foregroundColor(
        containerColor
      )
      .padding(
        EdgeInsets(
          top: .deviceTileVerticalPadding,
          leading: .deviceTileHorizontalPadding,
          bottom: .deviceTileVerticalPadding,
          trailing: .deviceTileHorizontalPadding
        )
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .background(
      variantColor
    )
    .clipShape(RoundedRectangle(cornerRadius: .deviceTileCornerRadius))
    .frame(height: .deviceTileHeight)
    .disabled(isBusy)
    .onTapGesture {
      onTap?()
    }
  }
}
