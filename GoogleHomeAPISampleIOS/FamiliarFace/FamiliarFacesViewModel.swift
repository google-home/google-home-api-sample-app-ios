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
import GoogleHomeTypes
import OSLog

/// A ViewModel for managing Familiar Faces using the FaceLibraryTrait.
@MainActor
class FamiliarFacesViewModel: ObservableObject {

  private enum Constants {
    static let notSupportedErrorMessage = "Face Library is not supported on this structure."
    static let loadFailedErrorMessagePrefix = "Failed to load faces: "
    static let loadCamerasFailedMessagePrefix = "Failed to load cameras: "
    static let toggleFaceDetectionFailedMessagePrefix = "Failed to toggle face detection for "
  }

  struct FaceCameraItem: Identifiable {
    let id: String
    let name: String
    let roomName: String?
    let trait: Google.AvStreamAnalysisTrait
    var isEnabled: Bool
  }

  @Published var knownFaces = [GoogleHomeTypes.Google.FaceLibraryTrait.Face]()
  @Published var unlabeledFaces = [GoogleHomeTypes.Google.FaceLibraryTrait.Face]()
  @Published var cameraItems = [FaceCameraItem]()
  @Published var isLoading = false
  @Published var errorMessage: String? = nil
  private let home: Home
  private let structure: Structure
  private var faceLibraryTrait: GoogleHomeTypes.Google.FaceLibraryTrait? = nil

  init(home: Home, structure: Structure) {
    self.home = home
    self.structure = structure
  }

  /// Asynchronously loads all faces (both named and unlabeled) associated with the current structure.
  public func loadFaces() async {
    isLoading = true
    errorMessage = nil
    do {
      guard let trait = await structure.traits.get(GoogleHomeTypes.Google.FaceLibraryTrait.self) else {
        errorMessage = Constants.notSupportedErrorMessage
        isLoading = false
        return
      }
      self.faceLibraryTrait = trait
      let response = try await trait.getFaces()
      let faces = response.facesArray
      self.knownFaces = faces.filter { $0.category == .faceCategoryKnown }
      self.unlabeledFaces = faces.filter { $0.category == .faceCategoryUnlabeled }
    } catch {
      Logger().error("[FamiliarFacesViewModel] Failed to load faces: \(error.localizedDescription) (\(error))")
      errorMessage = "\(Constants.loadFailedErrorMessagePrefix)\(error.localizedDescription)"
    }
    isLoading = false
  }

  /// Renames an existing face profile or names an unlabeled face profile.
  /// - Parameters:
  ///   - face: The face to rename.
  ///   - newName: The new name for the face.
  /// - Returns: A Boolean indicating if the rename operation completed successfully.
  public func renameFace(face: GoogleHomeTypes.Google.FaceLibraryTrait.Face, newName: String) async -> Bool {
    guard let trait = faceLibraryTrait, let faceID = face.id else {
      Logger().error("[FamiliarFacesViewModel] Cannot rename: trait or face ID is missing.")
      return false
    }
    do {
      _ = try await trait.updateFace(
        id: faceID,
        name: newName,
        category: face.category == .faceCategoryUnlabeled ? .faceCategoryKnown : .faceCategoryUnspecified
      )
      await loadFaces()
      return true
    } catch {
      Logger().error("[FamiliarFacesViewModel] Failed to rename face: \(error.localizedDescription) (\(error))")
      return false
    }
  }

  /// Deletes a named face profile from the library.
  /// - Parameter face: The face profile to delete.
  public func deleteFace(face: GoogleHomeTypes.Google.FaceLibraryTrait.Face) async {
    guard let trait = faceLibraryTrait, let faceID = face.id else { return }
    do {
      _ = try await trait.removeFaces(faceIdsArray: [faceID])
      await loadFaces()
    } catch {
      Logger().error("[FamiliarFacesViewModel] Failed to delete face: \(error.localizedDescription) (\(error))")
    }
  }

  /// Dismisses an unlabeled face profile, categorizing it as "Not a Person" so it is hidden from review lists.
  /// - Parameter face: The face profile to dismiss.
  public func dismissFaceAsNotAPerson(face: GoogleHomeTypes.Google.FaceLibraryTrait.Face) async {
    guard let trait = faceLibraryTrait, let faceID = face.id else { return }
    do {
      _ = try await trait.updateFace(id: faceID, name: "", category: .faceCategoryNotAPerson)
      await loadFaces()
    } catch {
      Logger().error("[FamiliarFacesViewModel] Failed to dismiss face: \(error.localizedDescription) (\(error))")
    }
  }

  /// Merges duplicate face profiles into a primary master face profile.
  /// - Parameters:
  ///   - masterFace: The primary face profile to keep.
  ///   - duplicateFaces: The duplicate face profiles to merge into the master profile.
  public func mergeFaces(masterFace: GoogleHomeTypes.Google.FaceLibraryTrait.Face, duplicateFaces: [GoogleHomeTypes.Google.FaceLibraryTrait.Face]) async {
    guard let trait = faceLibraryTrait, let masterID = masterFace.id else { return }
    let duplicateIDs = duplicateFaces.compactMap { $0.id }
    guard !duplicateIDs.isEmpty else { return }
    do {
      _ = try await trait.mergeFaces(
        mergedFaceId: masterID,
        faceIdsToMergeArray: duplicateIDs,
        name: nil
      )
      await loadFaces()
    } catch {
      Logger().error("[FamiliarFacesViewModel] Failed to merge faces: \(error.localizedDescription) (\(error))")
    }
  }

  /// Asynchronously loads all cameras in this structure supporting face detection.
  public func loadCameraItems() async {
    do {
      let devices = try await home.devices().list()
      let structureDevices = devices.filter { $0.structureID == structure.id }

      let rooms = try await home.rooms().list()
      let roomMap = Dictionary(uniqueKeysWithValues: rooms.map { ($0.id, $0.name) })

      var items = [FaceCameraItem]()
      for device in structureDevices {
        guard let trait = await getAvStreamAnalysisTrait(for: device) else {
          continue
        }
        guard trait.attributes.supportedEventTriggers?.contains(.face) == true else {
          continue
        }

        let isEnabled = trait.attributes.enabledEventTriggers?.contains(.face) == true
        let roomName = device.roomID.flatMap { roomMap[$0] }

        items.append(
          FaceCameraItem(
            id: device.id,
            name: device.name,
            roomName: roomName,
            trait: trait,
            isEnabled: isEnabled
          )
        )
      }
      self.cameraItems = items.sorted(by: { $0.name < $1.name })
    } catch {
      Logger().error("[FamiliarFacesViewModel] \(Constants.loadCamerasFailedMessagePrefix)\(error.localizedDescription) (\(error))")
    }
  }

  /// Toggles Face Detection on or off for a single camera item.
  public func toggleFaceDetection(for item: FaceCameraItem, isEnabled: Bool) async {
    guard let index = cameraItems.firstIndex(where: { $0.id == item.id }) else { return }
    cameraItems[index].isEnabled = isEnabled

    do {
      let status: Google.AvStreamAnalysisTrait.EnablementStatusEnum = isEnabled ? .enabled : .disabled
      try await item.trait.setOrUpdateEventDetectionTriggers(
        eventTriggerEnablements: [
          Google.AvStreamAnalysisTrait.EventTriggerEnablement(
            eventTriggerType: .face,
            enablementStatus: status
          )
        ]
      )
    } catch {
      Logger().error("[FamiliarFacesViewModel] \(Constants.toggleFaceDetectionFailedMessagePrefix)\(item.name): \(error.localizedDescription)")
      cameraItems[index].isEnabled = !isEnabled
    }
  }

  private func getAvStreamAnalysisTrait(for device: HomeDevice) async -> Google.AvStreamAnalysisTrait? {
    if device.types.contains(GoogleCameraDeviceType.self) {
      if let cameraDevice = await device.types.get(GoogleCameraDeviceType.self) {
        return cameraDevice.traits[Google.AvStreamAnalysisTrait.self]
      }
    } else if device.types.contains(GoogleDoorbellDeviceType.self) {
      if let doorbellDevice = await device.types.get(GoogleDoorbellDeviceType.self) {
        return doorbellDevice.traits[Google.AvStreamAnalysisTrait.self]
      }
    }
    return nil
  }
}
