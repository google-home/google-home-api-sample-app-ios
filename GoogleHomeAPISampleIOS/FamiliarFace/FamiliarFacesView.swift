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

/// A view for listing and managing familiar faces and unlabeled faces.
struct FamiliarFacesView: View {
  private enum Constants {
    static let thumbnailSize: CGFloat = 50
    static let buttonCornerRadius: CGFloat = 24
    static let loadingFaces = "Loading faces..."
    static let retryButton = "Retry"
    static let reviewNewFacesHeader = "Review New Faces"
    static let unlabeledFaceLabel = "Unlabeled Face"
    static let idPrefix = "ID: "
    static let unknownFace = "Unknown"
    static let nameButton = "Name"
    static let notAPersonLabel = "Not a Person"
    static let knownFacesHeader = "Known Faces"
    static let noKnownFacesMessage = "No known faces yet."
    static let deleteLabel = "Delete"
    static let mergeSelectedPrefix = "Merge Selected ("
    static let navigationTitle = "Familiar Faces"
    static let editButton = "Edit"
    static let doneButton = "Done"
    static let chooseProfileTitle = "Choose the primary profile to keep"
    static let unnamedSuffixPrefix = "Unnamed (..."
    static let cancel = "Cancel"
    static let unnamed = "Unnamed"
    // System Icons
    static let exclamationTriangleIcon = "exclamationmark.triangle"
    static let arrowCombineIcon = "arrow.combine"
    static let personXmarkIcon = "person.fill.xmark"
    static let trashIcon = "trash"
    static let personCropCircleIcon = "person.crop.circle.fill"
    static let videoFillIcon = "video.fill"
    static let camerasHeader = "Cameras"
    static let chooseCamerasFooter = "Choose which cameras you want to use for familiar face detection"
    static let emptyString = ""
  }

  @StateObject private var viewModel: FamiliarFacesViewModel
  @State private var editMode: EditMode = .inactive
  @State private var selectedFaceIDs = Set<String>()
  @State private var isShowingMergeConfirmation = false
  init(home: Home, structure: Structure) {
    self._viewModel = StateObject(
      wrappedValue: FamiliarFacesViewModel(home: home, structure: structure)
    )
  }

  var body: some View {
    VStack {
      if viewModel.isLoading {
        loadingView
      } else if let errorMsg = viewModel.errorMessage {
        errorView(errorMsg)
      } else {
        mainListView
      }
    }
    .navigationTitle(Constants.navigationTitle)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        Button(editMode == .active ? Constants.doneButton : Constants.editButton) {
          withAnimation {
            if editMode == .active {
              editMode = .inactive
              selectedFaceIDs.removeAll()
            } else {
              editMode = .active
            }
          }
        }
      }
    }
    .confirmationDialog(
      Constants.chooseProfileTitle,
      isPresented: $isShowingMergeConfirmation,
      titleVisibility: .visible
    ) {
      let selectedFaces = (viewModel.knownFaces + viewModel.unlabeledFaces).filter {
        guard let id = $0.id else { return false }
        return selectedFaceIDs.contains(id)
      }
      ForEach(selectedFaces, id: \.id) { face in
        Button(face.name ?? "\(Constants.unnamedSuffixPrefix)\(String(face.id?.suffix(6) ?? "")))") {
          Task {
            await performMerge(masterFace: face, selectedFaces: selectedFaces)
          }
        }
      }
      Button(Constants.cancel, role: .cancel) {}
    }
    .task {
      await viewModel.loadFaces()
      await viewModel.loadCameraItems()
    }
  }

  @ViewBuilder
  private var loadingView: some View {
    ProgressView(Constants.loadingFaces)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  @ViewBuilder
  private func errorView(_ message: String) -> some View {
    VStack(spacing: .md) {
      Image(systemName: Constants.exclamationTriangleIcon)
        .font(.largeTitle)
        .foregroundColor(.red)
      Text(message)
        .font(.body)
        .multilineTextAlignment(.center)
      Button(Constants.retryButton) {
        Task {
          await viewModel.loadFaces()
        }
      }
      .padding()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  @ViewBuilder
  private var mainListView: some View {
    ZStack(alignment: .bottom) {
      List(selection: $selectedFaceIDs) {
        knownFacesSection
        if editMode == .inactive {
          camerasSection
        }
        unlabeledFacesSection
      }
      .listStyle(InsetGroupedListStyle())
      .environment(\.editMode, $editMode)
      floatingMergeButton
    }
  }

  @ViewBuilder
  private var unlabeledFacesSection: some View {
    if !viewModel.unlabeledFaces.isEmpty {
      Section(header: Text(Constants.reviewNewFacesHeader)) {
        ForEach(viewModel.unlabeledFaces, id: \.id) { face in
          unlabeledFaceRow(face: face)
        }
      }
    }
  }

  @ViewBuilder
  private func unlabeledFaceRow(face: GoogleHomeTypes.Google.FaceLibraryTrait.Face) -> some View {
    HStack(spacing: .md) {
      faceThumbnail(face: face)
      VStack(alignment: .leading, spacing: .xxs) {
        Text(Constants.unlabeledFaceLabel)
          .font(.body)
          .fontWeight(.semibold)
        Text("\(Constants.idPrefix)\(face.id ?? Constants.unknownFace)")
          .font(.caption)
          .foregroundColor(.gray)
      }
      Spacer()
      if editMode == .inactive {
        NavigationLink(destination: RenameView(
          viewModel: RenameViewModel(
            renameType: .Face,
            name: "",
            setName: { newName in
              let success = await viewModel.renameFace(face: face, newName: newName)
              if !success {
                throw NSError(domain: "FamiliarFacesView", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to name face"])
              }
              return success
            }
          )
        )) {
          Text(Constants.nameButton)
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundColor(.blue)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.vertical, .xs)
    .tag(face.id ?? "")
    .swipeActions(edge: .trailing) {
      if editMode == .inactive {
        Button(role: .destructive) {
          Task {
            await viewModel.dismissFaceAsNotAPerson(face: face)
          }
        } label: {
          Label(Constants.notAPersonLabel, systemImage: Constants.personXmarkIcon)
        }
      }
    }
  }

  @ViewBuilder
  private var knownFacesSection: some View {
    Section(header: Text(Constants.knownFacesHeader)) {
      if viewModel.knownFaces.isEmpty {
        Text(Constants.noKnownFacesMessage)
          .font(.body)
          .foregroundColor(.gray)
          .padding(.vertical, .sm)
      } else {
        ForEach(viewModel.knownFaces, id: \.id) { face in
          if editMode == .inactive {
            NavigationLink(destination: RenameView(
              viewModel: RenameViewModel(
                renameType: .Face,
                name: face.name ?? "",
                setName: { newName in
                  let success = await viewModel.renameFace(face: face, newName: newName)
                  if !success {
                    throw NSError(domain: "FamiliarFacesView", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to rename face"])
                  }
                  return success
                }
              )
            )) {
              knownFaceRow(face: face)
            }
            .swipeActions(edge: .trailing) {
              Button(role: .destructive) {
                Task {
                  await viewModel.deleteFace(face: face)
                }
              } label: {
                Label(Constants.deleteLabel, systemImage: Constants.trashIcon)
              }
            }
          } else {
            knownFaceRow(face: face)
              .tag(face.id ?? "")
          }
        }
      }
    }
  }

  @ViewBuilder
  private var floatingMergeButton: some View {
    if editMode == .active && selectedFaceIDs.count >= 2 {
      Button(action: {
        isShowingMergeConfirmation = true
      }) {
        HStack(spacing: .xs) {
          Image(systemName: Constants.arrowCombineIcon)
          Text("\(Constants.mergeSelectedPrefix)\(selectedFaceIDs.count))")
        }
        .font(.headline)
        .foregroundColor(.white)
        .padding(.vertical, .mmd)
        .padding(.horizontal, .xl)
        .background(Color.blue)
        .cornerRadius(Constants.buttonCornerRadius)
        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
      }
      .padding(.bottom, .lg)
      .transition(.move(edge: .bottom).combined(with: .opacity))
    }
  }

  @ViewBuilder
  private func knownFaceRow(face: GoogleHomeTypes.Google.FaceLibraryTrait.Face) -> some View {
    HStack(spacing: .md) {
      faceThumbnail(face: face)
      VStack(alignment: .leading, spacing: .xxs) {
        Text(face.name ?? Constants.unnamed)
          .font(.body)
          .fontWeight(.semibold)
        Text("\(Constants.idPrefix)\(face.id ?? Constants.unknownFace)")
          .font(.caption)
          .foregroundColor(.gray)
      }
    }
    .padding(.vertical, .xs)
  }

  @ViewBuilder
  private func faceThumbnail(face: GoogleHomeTypes.Google.FaceLibraryTrait.Face) -> some View {
    if let urlString = face.mostRepresentativeFaceInstance?.url,
       let url = URL(string: urlString) {
      AsyncImage(url: url) { image in
        image
          .resizable()
          .aspectRatio(contentMode: .fill)
      } placeholder: {
        ProgressView()
      }
      .frame(width: Constants.thumbnailSize, height: Constants.thumbnailSize)
      .clipShape(Circle())
    } else {
      Image(systemName: Constants.personCropCircleIcon)
        .resizable()
        .frame(width: Constants.thumbnailSize, height: Constants.thumbnailSize)
        .foregroundColor(.gray)
    }
  }

  private func performMerge(
    masterFace: GoogleHomeTypes.Google.FaceLibraryTrait.Face,
    selectedFaces: [GoogleHomeTypes.Google.FaceLibraryTrait.Face]
  ) async {
    let duplicateFaces = selectedFaces.filter { $0.id != masterFace.id }
    await viewModel.mergeFaces(masterFace: masterFace, duplicateFaces: duplicateFaces)
    selectedFaceIDs.removeAll()
    withAnimation {
      editMode = .inactive
    }
  }

  @ViewBuilder
  private var camerasSection: some View {
    if !viewModel.cameraItems.isEmpty {
      Section {
        ForEach(viewModel.cameraItems) { item in
          HStack {
            Image(systemName: Constants.videoFillIcon)
              .foregroundColor(.blue)
            VStack(alignment: .leading, spacing: .xxs) {
              Text(item.name)
                .font(.body)
                .fontWeight(.semibold)
              if let roomName = item.roomName {
                Text(roomName)
                  .font(.caption)
                  .foregroundColor(.gray)
              }
            }
            Spacer()
            Toggle(Constants.emptyString, isOn: Binding(
              get: { item.isEnabled },
              set: { newValue in
                Task {
                  await viewModel.toggleFaceDetection(for: item, isEnabled: newValue)
                }
              }
            ))
            .labelsHidden()
          }
          .padding(.vertical, .xs)
        }
      } header: {
        Text(Constants.camerasHeader)
      } footer: {
        Text(Constants.chooseCamerasFooter)
      }
    }
  }
}
