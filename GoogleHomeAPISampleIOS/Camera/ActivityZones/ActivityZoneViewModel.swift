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

import Combine
import CoreGraphics
import Foundation
import GoogleHomeSDK
import GoogleHomeTypes
import Observation
import OSLog
import SwiftUI
import UIKit

// MARK: - Data Models for UI
/// Represents a single, complete Activity Zone in the UI layer.
/// This local model bridges the Google Home Platform SDK traits with the SwiftUI presentation layer.
public struct ActivityZone: Identifiable, Equatable, Sendable {
  /// The reserved ID of the default/background zone representing the area outside custom zones.
  public static let defaultZoneID = "0"
  /// The display name for the default background zone.
  public static let defaultZoneName = "Default (Outside Defined Zones)"
  /// Unique identifier assigned by the cloud/SDK. Unsaved temporary zones will have a `nil` ID.
  public var id: String?
  /// Custom name of the activity zone chosen by the user.
  public var name: String
  /// Curated color used to highlight this zone in the UI.
  public var color: ZoneColor
  /// Ordered array of vertices (as 2D Cartesian coordinates) defining the polygon's shape.
  public var vertices: [CGPoint]
  /// Set of selective event triggers configured for this specific zone.
  public var uses: [ZoneUse]
  /// Evaluates if this represents the non-editable default zone.
  public var isDefaultZone: Bool {
    self.id == ActivityZone.defaultZoneID
  }
  /// Helper to map this local UI data model back into the exact SDK Cartesian zone structure
  /// required for GHP trait commands.
  public func toSDKStruct() -> Google.ZoneManagementTrait.TwoDCartesianZoneStruct {
    let sdkVertices = self.vertices.map {
      Google.ZoneManagementTrait.TwoDCartesianVertexStruct(x: UInt16($0.x), y: UInt16($0.y))
    }
    let sdkUses = self.uses.filter { $0.isSelected }.map { $0.use }
    return Google.ZoneManagementTrait.TwoDCartesianZoneStruct(
      name: self.name,
      use: sdkUses,
      vertices: sdkVertices,
      color: self.color.rawValue
    )
  }
}
/// Represents a specific event trigger option for an Activity Zone (e.g., Person, Vehicle, Motion).
public struct ZoneUse: Equatable, Sendable {
  /// The internal Google SDK representation of this event category.
  public var use: Google.ZoneManagementTrait.ZoneUseEnum
  /// Flag specifying if the event trigger is enabled/selected for the zone.
  public var isSelected: Bool
  /// Human-readable name of the trigger shown in lists and settings.
  public var displayName: String {
    switch use {
    case .motion: return "Motion"
    case .person: return "Person"
    case .vehicle: return "Vehicle"
    case .package: return "Package"
    case .animal: return "Animal"
    default: return "Unknown"
    }
  }
  /// Visual icon corresponding to the event type, using standard system symbols.
  public var icon: Image {
    switch use {
    case .motion: return Image(systemName: "video")
    case .person: return Image(systemName: "figure.walk")
    case .vehicle: return Image(systemName: "car")
    case .package: return Image(systemName: "shippingbox")
    case .animal: return Image(systemName: "dog")
    default: return Image(systemName: "questionmark.circle")
    }
  }
}
/// Curated set of activity zone hex colors defined by the Google Home Platform spec.
public enum ZoneColor: String, CaseIterable, Sendable {
  case salmon = "#F439A0"
  case teal = "#24C1E0"
  case purple = "#A142F4"
  case orange = "#FBBC04"
  case grey = "#9AA0A6"  // Reserved for the non-editable background zone
  /// Native SwiftUI color counterpart.
  public var swiftUIColor: Color {
    switch self {
    case .salmon: return .pink
    case .teal: return .teal
    case .purple: return .purple
    case .orange: return .orange
    case .grey: return .gray
    }
  }
  /// User-facing localized display name.
  public var displayName: String {
    switch self {
    case .salmon: return "Salmon"
    case .teal: return "Teal"
    case .purple: return "Purple"
    case .orange: return "Orange"
    case .grey: return "Grey"
    }
  }
  /// Limits the selection pool for new/custom zones, preventing the background gray color from being assigned.
  public static func settableColors() -> [ZoneColor] {
    return [.salmon, .teal, .purple, .orange]
  }
}
// MARK: - SDK Enums Extension
extension Google.AvStreamAnalysisTrait.EventTriggerTypeEnum {
  /// Maps global camera event trigger traits directly into the corresponding activity zone use category.
  /// Returns `nil` if the trigger type is global-only and cannot be isolated inside custom zones (e.g., tamper detection).
  public var zoneUseEnum: Google.ZoneManagementTrait.ZoneUseEnum? {
    switch self {
    case .motion: return .motion
    case .personDetected: return .person
    case .vehicleDetected: return .vehicle
    case .animalDetected: return .animal
    case .packageDetected: return .package
    default: return nil
    }
  }
}
// MARK: - View Model Implementation
/// An `@Observable` view model that operates on the main thread to manage the state
/// and perform CRUD operations for Camera/Doorbell Activity Zones using GHP SDK traits.
@Observable
@MainActor
public class ActivityZoneViewModel {
  private enum Constants {
    static let defaultCanvasWidth: Double = 1920
    static let defaultCanvasHeight: Double = 1080
    static let referenceOctagonRatio1: Double = 0.3
    static let referenceOctagonRatio2: Double = 0.5
    static let referenceOctagonRatio3: Double = 0.7
  }
  /// Local reference to the zone management trait of the smart home device.
  private var zoneManagementTrait: Google.ZoneManagementTrait? {
    didSet {
      self.updateZonesFromTrait()
    }
  }
  private let home: Home
  private let deviceID: String
  private var cancellables = Set<AnyCancellable>()
  /// Observable list of parsed activity zones available on the camera.
  public private(set) var zones: [ActivityZone]? = nil
  /// Flag representing if the initial fetch/subscription is complete.
  public private(set) var activityZonesInitialized = false
  /// The native resolution of the camera video stream (e.g. 1920x1080) used as the Cartesian coordinates limit.
  public private(set) var zoneMaxSize: CGSize = CGSize(width: Constants.defaultCanvasWidth, height: Constants.defaultCanvasHeight)
  /// Supported zone triggers resolved dynamically based on the camera hardware capabilities.
  private var possibleZoneUses: [Google.ZoneManagementTrait.ZoneUseEnum] = []
  /// Dynamic background image fetched from camera snapshot trait or passed from initializer.
  public var backgroundImage: UIImage? = nil
  /// Initializes the ActivityZoneViewModel by establishing subscriptions to device traits.
  ///
  /// - Parameters:
  ///   - home: The Home SDK instance.
  ///   - deviceID: The ID of the Camera or Doorbell device.
  ///   - backgroundImage: An optional pre-loaded background image.
  public init(home: Home, deviceID: String, backgroundImage: UIImage? = nil) {
    self.home = home
    self.deviceID = deviceID
    self.backgroundImage = backgroundImage
    self.subscribeToDeviceTraits()
  }
  /// Listens for changes on the camera device and resolves `ZoneManagementTrait` and `AvStreamAnalysisTrait`.
  private func subscribeToDeviceTraits() {
    self.home.device(id: deviceID)
      .removeDuplicates()
      .receive(on: DispatchQueue.main)
      .map { device -> AnyPublisher<DeviceTypeCollection, HomeError> in
        // Subscribe to all available trait updates on the active camera device
        return device.types.subscribeAll().eraseToAnyPublisher()
      }
      .switchToLatest()
      .receive(on: DispatchQueue.main)
      .sink { completion in
        if case .failure(let error) = completion {
          Logger().error("Error subscribing to activity zone traits: \(error)")
        }
      } receiveValue: { [weak self] collection in
        guard let self = self else { return }
        // Resolve device instance (support both generic Camera and Doorbell types)
        var targetDevice: (any DeviceType)? = nil
        if collection.contains(GoogleCameraDeviceType.self) {
          targetDevice = collection.getAll(of: GoogleCameraDeviceType.self).first
        } else if collection.contains(GoogleDoorbellDeviceType.self) {
          targetDevice = collection.getAll(of: GoogleDoorbellDeviceType.self).first
        }
        guard let targetDevice else {
          Logger().error("No matching camera or doorbell device type resolved.")
          return
        }

        // 1. Resolve supported triggers dynamically from AvStreamAnalysis
        let streamAnalysis = targetDevice.traits[Google.AvStreamAnalysisTrait.self]
        self.possibleZoneUses =
          streamAnalysis?.attributes.supportedEventTriggers?
          .compactMap { $0.zoneUseEnum } ?? []
        // 2. Set Zone Management Trait which triggers data extraction
        self.zoneManagementTrait = targetDevice.traits[Google.ZoneManagementTrait.self]
        // 3. Resolve CameraSnapshotTrait and fetch snapshot if we don't have a background image yet
        if self.backgroundImage == nil {
          if let cameraSnapshotTrait = targetDevice.traits[Google.CameraSnapshotTrait.self] {
            self.fetchCameraSnapshot(from: cameraSnapshotTrait)
          }
        }
      }
      .store(in: &self.cancellables)
  }

  /// Maps SDK device attributes into our clean local `ActivityZone` structures.
  private func updateZonesFromTrait() {
    defer { self.activityZonesInitialized = true }
    guard let zoneManagementTrait else {
      Logger().warning("ZoneManagementTrait is currently unavailable.")
      return
    }
    // Parse maximum Cartesian constraints (defaults to 1920x1080)
    self.zoneMaxSize = CGSize(
      width: Int(zoneManagementTrait.attributes.twoDCartesianMax?.x ?? UInt16(Constants.defaultCanvasWidth)),
      height: Int(zoneManagementTrait.attributes.twoDCartesianMax?.y ?? UInt16(Constants.defaultCanvasHeight))
    )
    // Convert the SDK zones array to local ActivityZone instances
    self.zones = zoneManagementTrait.attributes.zones?.map { sdkZone in
      let zoneData = sdkZone.twoDCartesianZone
      let activeUses = zoneData?.use ?? []
      let uses = self.possibleZoneUses.map { use in
        ZoneUse(use: use, isSelected: activeUses.contains(use))
      }
      return ActivityZone(
        id: String(sdkZone.zoneID),
        name: zoneData?.name ?? "",
        color: ZoneColor(rawValue: zoneData?.color ?? "") ?? .grey,
        vertices: zoneData?.vertices.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) } ?? [],
        uses: uses
      )
    }
  }

  // MARK: - CRUD Operations

  /// Generates a pre-scaled octagon template placed at the center of the viewport.
  /// Used to initialize the canvas editor for a brand new zone.
  public func getNewActivityZoneTemplate() -> ActivityZone {
    let referenceRatios: [CGPoint] = [
      CGPoint(x: Constants.referenceOctagonRatio1, y: Constants.referenceOctagonRatio1),
      CGPoint(x: Constants.referenceOctagonRatio2, y: Constants.referenceOctagonRatio1),
      CGPoint(x: Constants.referenceOctagonRatio3, y: Constants.referenceOctagonRatio1),
      CGPoint(x: Constants.referenceOctagonRatio3, y: Constants.referenceOctagonRatio2),
      CGPoint(x: Constants.referenceOctagonRatio3, y: Constants.referenceOctagonRatio3),
      CGPoint(x: Constants.referenceOctagonRatio2, y: Constants.referenceOctagonRatio3),
      CGPoint(x: Constants.referenceOctagonRatio1, y: Constants.referenceOctagonRatio3),
      CGPoint(x: Constants.referenceOctagonRatio1, y: Constants.referenceOctagonRatio2),
    ]
    let initialVertices = referenceRatios.map {
      CGPoint(x: $0.x * zoneMaxSize.width, y: $0.y * zoneMaxSize.height)
    }
    let defaultUses = self.possibleZoneUses.map { ZoneUse(use: $0, isSelected: false) }
    return ActivityZone(
      id: nil,  // Indicates a new, unsaved zone
      name: "New Zone",
      color: .salmon,
      vertices: initialVertices,
      uses: defaultUses
    )
  }

  /// Saves a new activity zone to the GHP SDK using the `createTwoDCartesianZone` command.
  public func addActivityZone(zone: ActivityZone) async {
    guard let trait = self.zoneManagementTrait else {
      Logger().error("Unable to create zone: ZoneManagementTrait is missing.")
      return
    }
    do {
      _ = try await trait.createTwoDCartesianZone(zone: zone.toSDKStruct())
    } catch {
      Logger().error("Error calling createTwoDCartesianZone: \(error)")
    }
  }

  /// Updates settings and shapes for an existing zone via the `updateTwoDCartesianZone` command.
  public func updateActivityZone(zone: ActivityZone) async {
    guard let trait = self.zoneManagementTrait else {
      Logger().error("Unable to update zone: ZoneManagementTrait is missing.")
      return
    }
    guard let idString = zone.id, let zoneID = UInt16(idString) else {
      Logger().error("Error: Invalid zone ID for update operations.")
      return
    }
    do {
      try await trait.updateTwoDCartesianZone(zoneID: zoneID, zone: zone.toSDKStruct())
    } catch {
      Logger().error("Error calling updateTwoDCartesianZone: \(error)")
    }
  }

  /// Removes a custom zone permanently using the `removeZone` trait command.
  public func deleteActivityZone(zone: ActivityZone) async {
    guard let trait = self.zoneManagementTrait else {
      Logger().error("Unable to delete zone: ZoneManagementTrait is missing.")
      return
    }
    guard let idString = zone.id, let zoneID = UInt16(idString) else {
      Logger().error("Error: Invalid zone ID for deletion.")
      return
    }
    do {
      try await trait.removeZone(zoneID: zoneID)
    } catch {
      Logger().error("Error calling removeZone: \(error)")
    }
  }

  /// Fetches a live camera snapshot and loads it as a `UIImage`.
  private func fetchCameraSnapshot(from trait: Google.CameraSnapshotTrait) {
    Task { [weak self] in
      guard let self = self else { return }
      do {
        let response = try await trait.getLiveSnapshot()
        try await self.downloadAndSetBackgroundImage(urlString: response.snapshot_url)
      } catch {
        Logger().error("Error calling getLiveSnapshot(): \(error)")
        if let previewImageUrl = trait.attributes.preview_image_url {
          do {
            try await self.downloadAndSetBackgroundImage(urlString: previewImageUrl)
          } catch {
            Logger().error("Failed to download fallback preview image: \(error)")
          }
        } else {
          Logger().warning("No fallback preview_image_url available.")
        }
      }
    }
  }

  /// Downloads image from URL using SDK authorization token.
  private func downloadAndSetBackgroundImage(urlString: String) async throws {
    guard let url = URL(string: urlString) else {
      throw HomeError.invalidArgument("Invalid URL string: \(urlString)")
    }
    let auth = try await self.home.permissions.authorization()
    var request = URLRequest(url: url)
    request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")

    let (data, _) = try await URLSession.shared.data(for: request)
    if let image = UIImage(data: data) {
      self.backgroundImage = image
    } else {
      Logger().error("Failed to decode UIImage from camera snapshot data of size: \(data.count) bytes.")
      throw HomeError.failedPrecondition("Failed to decode UIImage from downloaded data.")
    }
  }
}
