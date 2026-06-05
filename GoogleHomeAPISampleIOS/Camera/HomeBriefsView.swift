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

import Foundation
import GoogleHomeSDK
import SwiftUI

private enum Constraints {
  static let stackSpacing: CGFloat = 8
  static let verticalPadding: CGFloat = 4
  static let thumbnailWidth: CGFloat = 120
  static let thumbnailHeight: CGFloat = 80
  static let thumbnailCornerRadius: CGFloat = 8
}

/// View for displaying Home Briefs.
@MainActor
public struct HomeBriefsView: View {
  let viewModel: HomeBriefsViewModel
  let urlSession: URLSession

  public init(viewModel: HomeBriefsViewModel, urlSession: URLSession = .shared) {
    self.viewModel = viewModel
    self.urlSession = urlSession
  }

  public var body: some View {
    Section(header: Text("AI Summaries")) {
      if viewModel.briefs.isEmpty && viewModel.isLoadingMoreBriefs {
        ProgressView()
      } else if viewModel.briefs.isEmpty {
        Text("No Home Briefs found")
      } else {
        ForEach(viewModel.briefs, id: \.id) { brief in
          briefItemView(brief: brief)
        }
        if viewModel.isLoadingMoreBriefs && !viewModel.briefs.isEmpty {
          HStack {
            Spacer()
            ProgressView()
            Spacer()
          }
        }
      }
    }
  }

  @ViewBuilder
  private func briefItemView(brief: HomeBrief) -> some View {
    VStack(alignment: .leading, spacing: Constraints.stackSpacing) {
      Text(brief.body)
        .font(.body)

      Text(brief.generatedDate, style: .date)
        .font(.caption)
        .foregroundColor(.gray)

      if !brief.keyCameraEvents.isEmpty {
        Text("\(brief.keyCameraEvents.count) related clips")
          .font(.caption)
          .foregroundColor(.accentColor)

        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: Constraints.stackSpacing) {
            ForEach(
              Array(brief.keyCameraEvents.enumerated()),
              id: \.offset
            ) { _, event in
              CameraEventPreviewItem(event: event, urlSession: urlSession)
            }
          }
        }
      }
    }
    .padding(.vertical, Constraints.verticalPadding)
    .onAppear {
      // Fetch the next batch when the user scrolls to the end of the current list.
      // We detect this by checking if the item that just appeared is the last loaded brief.
      if brief.id == viewModel.briefs.last?.id && viewModel.hasMoreBriefs {
        Task {
          await viewModel.loadMoreHistoricalBriefs()
        }
      }
    }
  }
}

/// Displays a thumbnail preview for a camera event associated with a Home Brief.
struct CameraEventPreviewItem: View {
  let event: BasicCameraEventDetails
  let urlSession: URLSession

  var body: some View {
    ZStack {
      if let thumbnailURL = event.thumbnailURL {
        AsyncImage(url: thumbnailURL) { phase in
          switch phase {
          case .empty:
            ProgressView()
              .frame(width: Constraints.thumbnailWidth, height: Constraints.thumbnailHeight)
          case .success(let image):
            image
              .resizable()
              .aspectRatio(contentMode: .fill)
              .frame(width: Constraints.thumbnailWidth, height: Constraints.thumbnailHeight)
              .clipped()
          case .failure:
            Image(systemName: "video.slash.fill")
              .foregroundColor(.gray)
              .frame(width: Constraints.thumbnailWidth, height: Constraints.thumbnailHeight)
          @unknown default:
            Image(systemName: "photo")
              .foregroundColor(.gray)
              .frame(width: Constraints.thumbnailWidth, height: Constraints.thumbnailHeight)
          }
        }
      } else {
        Image(systemName: "photo")
          .foregroundColor(.gray)
          .frame(width: Constraints.thumbnailWidth, height: Constraints.thumbnailHeight)
      }

      if let previewURL = event.previewURL {
        WebPImageView(url: previewURL, urlSession: urlSession)
          .frame(width: Constraints.thumbnailWidth, height: Constraints.thumbnailHeight)
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: Constraints.thumbnailCornerRadius))
    .accessibilityLabel("Camera event preview")
  }
}
