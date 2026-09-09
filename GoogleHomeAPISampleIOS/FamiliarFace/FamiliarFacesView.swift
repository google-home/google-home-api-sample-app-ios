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
  fileprivate enum Constants {
    static let thumbnailSize: CGFloat = 50
    static let shadowOpacity: CGFloat = 0.15
    static let shadowRadius: CGFloat = 8
    static let shadowYOffset: CGFloat = 4
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
    static let arrowMergeIcon = "arrow.merge"
    static let personXmarkIcon = "person.fill.xmark"
    static let trashIcon = "trash"
    static let personCropCircleIcon = "person.crop.circle.fill"
    static let videoFillIcon = "video.fill"
    static let camerasHeader = "Cameras"
    static let chooseCamerasFooter = "Choose which cameras you want to use for familiar face detection"
    static let errorDomain = "FamiliarFacesView"
    static let failedToNameFace = "Failed to name face"
    static let chevronRightIcon = "chevron.right"
  }

  @StateObject private var viewModel: FamiliarFacesViewModel
  @State private var editMode: EditMode = .inactive
  @State private var selectedFaceIDs = Set<String>()
  @State private var isShowingMergeConfirmation = false
  @State private var navigateToRenameFace: GoogleHomeTypes.Google.FaceLibraryTrait.Face?

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
  private var listContent: some View {
    knownFacesSection
    if editMode == .inactive {
      camerasSection
    }
    unlabeledFacesSection
  }

  @ViewBuilder
  private var mainListView: some View {
    ZStack(alignment: .bottom) {
      List(selection: $selectedFaceIDs) {
        listContent
      }
      .listStyle(.insetGrouped)
      .environment(\.editMode, $editMode)
      floatingMergeButton
    }
    .background(
      NavigationLink(
        destination: Group {
          if let face = navigateToRenameFace {
            RenameView(
              viewModel: RenameViewModel(
                renameType: .Face,
                name: "",
                setName: { newName in
                  let success = await viewModel.renameFace(face: face, newName: newName)
                  if !success { throw NSError(domain: Constants.errorDomain, code: 1, userInfo: [NSLocalizedDescriptionKey: Constants.failedToNameFace]) }
                  return success
                }
              )
            )
          }
        },
        isActive: Binding(
          get: { navigateToRenameFace != nil },
          set: { if !$0 { navigateToRenameFace = nil } }
        ),
        label: {
          EmptyView()
        }
      )
    )
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
        Button {
          navigateToRenameFace = face
        } label: {
          Text(Constants.nameButton)
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundColor(.blue)
        }
        .buttonStyle(.plain)
      } else {
        Text(Constants.nameButton)
          .font(.subheadline)
          .fontWeight(.semibold)
          .foregroundColor(.gray)
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
          NavigationLink {
            KnownFaceManagementView(viewModel: viewModel, face: face)
          } label: {
            knownFaceRow(face: face)
          }
          .tag(face.id ?? "")
          .swipeActions(edge: .trailing) {
            if editMode == .inactive {
              Button(role: .destructive) {
                Task {
                  await viewModel.deleteFace(face: face)
                }
              } label: {
                Label(Constants.deleteLabel, systemImage: Constants.trashIcon)
              }
            }
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
          Image(systemName: Constants.arrowMergeIcon)
          Text("\(Constants.mergeSelectedPrefix)\(selectedFaceIDs.count))")
        }
        .font(.headline)
        .foregroundColor(.white)
        .padding(.vertical, .mmd)
        .padding(.horizontal, .xl)
        .background(Color.blue)
        .cornerRadius(.xl)
        .shadow(color: Color.black.opacity(Constants.shadowOpacity), radius: Constants.shadowRadius, x: 0, y: Constants.shadowYOffset)
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
          .lineLimit(1)
          .truncationMode(.middle)
      }
    }
    .padding(.vertical, .xs)
  }

  @ViewBuilder
  private func faceThumbnail(face: GoogleHomeTypes.Google.FaceLibraryTrait.Face) -> some View {
    FaceImageView(
      urlString: face.mostRepresentativeFaceInstance?.url,
      size: Constants.thumbnailSize,
      home: viewModel.home
    )
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
            Toggle("", isOn: Binding(
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

/// A view for managing a known face, moving or deleting face instances (images).
struct KnownFaceManagementView: View {
  private enum ViewConstants {
    static let xmarkIcon = "xmark"
    static let forkIcon = "arrow.triangle.branch"
    static let trashIcon = "trash"
    static let pencilIcon = "pencil"
    static let personCropCircleIcon = "person.crop.circle.fill"
    static let photoIcon = "photo"
    static let checkmarkCircleFillIcon = "checkmark.circle.fill"
    static let circleIcon = "circle"
    static let selectFacesPrompt = "Select faces that you want to move or delete"
    static let noFaceImages = "No face images available."
    static let renameFaceTitle = "Rename Face"
    static let renameFaceMessage = "Enter a new name for this face profile."
    static let faceNamePlaceholder = "Face Name"
    static let saveButton = "Save"
    static let deleteAlertTitle = "Delete selected face images?"
    static let deleteAlertMessage = "These face images will be removed from this profile."
    static let deleteButton = "Delete"
    static let cancel = "Cancel"
    static let createNewHeader = "Create New"
    static let addNewPersonButton = "Add a new person"
    static let selectProfileToMoveTitle = "Select profile to move to"
    static let addNewPersonAlertTitle = "Add a new person"
    static let addNewPersonAlertMessage = "Enter a name for this new person profile."
    static let personNamePlaceholder = "Person Name"
    static let addButton = "Add"
    static let profileImageSize: CGFloat = 72
    static let smallProfileImageSize: CGFloat = 40
    static let imageGridMinHeight: CGFloat = 110
    static let checkmarkPadding: CGFloat = 6
    static let noFaceImagesPaddingTop: CGFloat = 32
    static let noSpacing: CGFloat = 0
    static let placeholderBackgroundOpacity: CGFloat = 0.1
    static let selectionOverlayOpacity: CGFloat = 0.4
    static let selectionAnimationDuration: Double = 0.15
  }

  @Environment(\.dismiss) private var dismiss
  @ObservedObject var viewModel: FamiliarFacesViewModel
  let face: GoogleHomeTypes.Google.FaceLibraryTrait.Face

  @State private var selectedInstanceIDs = Set<String>()
  @State private var showDeleteAlert = false
  @State private var showMoveTargetPicker = false
  @State private var showNewPersonAlert = false
  @State private var newPersonName = ""
  @State private var showRenameAlert = false
  @State private var editFaceName = ""
  @State private var currentFaceName = ""

  var body: some View {
    VStack(spacing: ViewConstants.noSpacing) {
      headerBar
      ScrollView {
        VStack(spacing: .smd) {
          profileHeader
          if viewModel.isLoadingInstances {
            ProgressView()
              .padding(.top, ViewConstants.noFaceImagesPaddingTop)
          } else if viewModel.loadedFaceInstances.isEmpty {
            Text(ViewConstants.noFaceImages)
              .foregroundColor(.secondary)
              .padding(.top, ViewConstants.noFaceImagesPaddingTop)
          } else {
            imageGrid
          }
        }
        .padding(.horizontal, .xxs)
      }
    }
    .navigationBarHidden(true)
    .task {
      currentFaceName = face.name ?? FamiliarFacesView.Constants.unnamed
      await viewModel.loadFaceInstances(for: face)
    }
    .alert(ViewConstants.renameFaceTitle, isPresented: $showRenameAlert) {
      TextField(ViewConstants.faceNamePlaceholder, text: $editFaceName)
      Button(ViewConstants.saveButton) {
        guard !editFaceName.isEmpty else { return }
        let nameToSave = editFaceName
        Task {
          let success = await viewModel.renameFace(face: face, newName: nameToSave)
          if success {
            currentFaceName = nameToSave
          }
        }
      }
      Button(ViewConstants.cancel, role: .cancel) {}
    } message: {
      Text(ViewConstants.renameFaceMessage)
    }
    .alert(ViewConstants.deleteAlertTitle, isPresented: $showDeleteAlert) {
      Button(ViewConstants.deleteButton, role: .destructive) {
        Task {
          await viewModel.deleteFaceInstances(instanceIDs: Array(selectedInstanceIDs), for: face)
          selectedInstanceIDs.removeAll()
        }
      }
      Button(ViewConstants.cancel, role: .cancel) {}
    } message: {
      Text(ViewConstants.deleteAlertMessage)
    }
    .sheet(isPresented: $showMoveTargetPicker) {
      targetPickerSheet
    }
  }

  @ViewBuilder
  private var headerBar: some View {
    HStack {
      Button {
        dismiss()
      } label: {
        Image(systemName: ViewConstants.xmarkIcon)
          .font(.title2)
          .foregroundColor(.primary)
      }

      if !selectedInstanceIDs.isEmpty {
        Text("\(selectedInstanceIDs.count)")
          .font(.title2)
          .foregroundColor(.primary)
          .padding(.leading, .sm)
      }

      Spacer()

      HStack(spacing: .lg) {
        Button {
          showMoveTargetPicker = true
        } label: {
          Image(systemName: ViewConstants.forkIcon)
            .font(.title2)
            .foregroundColor(selectedInstanceIDs.isEmpty ? .gray : .blue)
        }
        .disabled(selectedInstanceIDs.isEmpty)

        Button {
          showDeleteAlert = true
        } label: {
          Image(systemName: ViewConstants.trashIcon)
            .font(.title2)
            .foregroundColor(selectedInstanceIDs.isEmpty ? .gray : .red)
        }
        .disabled(selectedInstanceIDs.isEmpty)
      }
    }
    .padding()
  }

  @ViewBuilder
  private var profileHeader: some View {
    VStack(spacing: .sm) {
      FaceImageView(
        urlString: face.mostRepresentativeFaceInstance?.url,
        size: ViewConstants.profileImageSize,
        home: viewModel.home
      )

      HStack(spacing: .sm) {
        Text(currentFaceName.isEmpty ? (face.name ?? FamiliarFacesView.Constants.unnamed) : currentFaceName)
          .font(.title2)
          .fontWeight(.semibold)

        Button {
          editFaceName = currentFaceName.isEmpty ? (face.name ?? "") : currentFaceName
          showRenameAlert = true
        } label: {
          Image(systemName: ViewConstants.pencilIcon)
            .font(.title3)
            .foregroundColor(.blue)
        }
      }

      Text(ViewConstants.selectFacesPrompt)
        .font(.subheadline)
        .foregroundColor(.secondary)
    }
    .padding(.top, .sm)
    .padding(.bottom, .md)
  }

  @ViewBuilder
  private var imageGrid: some View {
    let columns = [
      GridItem(.flexible(), spacing: StackSpacing.xs.rawValue),
      GridItem(.flexible(), spacing: StackSpacing.xs.rawValue),
      GridItem(.flexible(), spacing: StackSpacing.xs.rawValue),
    ]
    LazyVGrid(columns: columns, spacing: StackSpacing.xs.rawValue) {
      ForEach(viewModel.loadedFaceInstances, id: \.id) { instance in
        if let urlString = instance.url, let url = URL(string: urlString),
           let instanceID = instance.id {
          let isSelected = selectedInstanceIDs.contains(instanceID)
          ZStack(alignment: .topLeading) {
            AuthenticatedAsyncImage(url: url, home: viewModel.home) { phase in
              if let image = phase.image {
                image.resizable().aspectRatio(contentMode: .fill)
              } else if phase.error != nil {
                Image(systemName: ViewConstants.photoIcon)
                  .font(.largeTitle)
                  .foregroundColor(.gray)
                  .frame(maxWidth: .infinity, maxHeight: .infinity)
                  .background(Color.secondary.opacity(ViewConstants.placeholderBackgroundOpacity))
              } else {
                ProgressView()
                  .frame(maxWidth: .infinity, maxHeight: .infinity)
                  .background(Color.secondary.opacity(ViewConstants.placeholderBackgroundOpacity))
              }
            }
            .frame(minWidth: ViewConstants.noSpacing, maxWidth: .infinity, minHeight: ViewConstants.imageGridMinHeight, maxHeight: ViewConstants.imageGridMinHeight)
            .clipped()
            .cornerRadius(.xs)
            Image(systemName: isSelected ? ViewConstants.checkmarkCircleFillIcon : ViewConstants.circleIcon)
              .font(.title3)
              .foregroundColor(isSelected ? .blue : .white)
              .background(
                Circle().fill(isSelected ? Color.white : Color.black.opacity(ViewConstants.selectionOverlayOpacity))
              )
              .padding(ViewConstants.checkmarkPadding)
          }
          .contentShape(Rectangle())
          .onTapGesture {
            withAnimation(.easeInOut(duration: ViewConstants.selectionAnimationDuration)) {
              if isSelected {
                selectedInstanceIDs.remove(instanceID)
              } else {
                selectedInstanceIDs.insert(instanceID)
              }
            }
          }
        }
      }
    }
  }

  @ViewBuilder
  private var targetPickerSheet: some View {
    let candidateFaces = viewModel.knownFaces.filter { $0.id != face.id }
    NavigationStack {
      List {
        Section {
          Button {
            showNewPersonAlert = true
          } label: {
            HStack(spacing: .smd) {
              Text(ViewConstants.addNewPersonButton)
                .font(.body.weight(.semibold))
                .foregroundColor(.blue)
            }
          }
        } header: {
          Text(ViewConstants.createNewHeader)
        }
        Section(header: Text(ViewConstants.selectProfileToMoveTitle)) {
          ForEach(candidateFaces, id: \.id) { targetFace in
            Button {
              if let targetID = targetFace.id {
                Task {
                  await viewModel.moveFaceInstances(
                    instanceIDs: Array(selectedInstanceIDs),
                    toTargetFaceID: targetID,
                    for: face
                  )
                  selectedInstanceIDs.removeAll()
                  showMoveTargetPicker = false
                }
              }
            } label: {
              HStack(spacing: .smd) {
                FaceImageView(
                  urlString: targetFace.mostRepresentativeFaceInstance?.url,
                  size: ViewConstants.smallProfileImageSize,
                  home: viewModel.home
                )
                Text(targetFace.name ?? FamiliarFacesView.Constants.unnamed)
                  .foregroundColor(.primary)
              }
            }
          }
        }
      }
      .alert(ViewConstants.addNewPersonAlertTitle, isPresented: $showNewPersonAlert) {
        TextField(ViewConstants.personNamePlaceholder, text: $newPersonName)
        Button(ViewConstants.addButton) {
          guard !newPersonName.isEmpty else { return }
          Task {
            await viewModel.createNewPerson(
              from: Array(selectedInstanceIDs),
              withName: newPersonName,
              for: face
            )
            selectedInstanceIDs.removeAll()
            showMoveTargetPicker = false
            newPersonName = ""
          }
        }
        Button(ViewConstants.cancel, role: .cancel) {
          newPersonName = ""
        }
      } message: {
        Text(ViewConstants.addNewPersonAlertMessage)
      }
      .navigationTitle(ViewConstants.selectProfileToMoveTitle)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(ViewConstants.cancel) { showMoveTargetPicker = false }
        }
      }
    }
  }
}

/// A shared view for displaying a face profile image.
struct FaceImageView: View {
  let urlString: String?
  let size: CGFloat
  let home: Home?

  var body: some View {
    if let urlString = urlString, let url = URL(string: urlString) {
      AuthenticatedAsyncImage(url: url, home: home) { phase in
        if let image = phase.image {
          image
            .resizable()
            .aspectRatio(contentMode: .fill)
        } else if phase.error != nil {
          placeholderImage
        } else {
          ProgressView()
        }
      }
      .frame(width: size, height: size)
      .clipShape(Circle())
    } else {
      placeholderImage
        .frame(width: size, height: size)
    }
  }

  private var placeholderImage: some View {
    Image(systemName: "person.crop.circle.fill")
      .resizable()
      .foregroundColor(.gray)
  }
}
