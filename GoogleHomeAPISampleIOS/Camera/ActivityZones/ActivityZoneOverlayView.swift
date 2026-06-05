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

import CoreGraphics
import SwiftUI
import UIKit

/// A highly reusable rendering component that overlays geometric shapes (polygons)
/// and drag handles directly over a camera view.
///
/// ### Coordinate Transformation:
/// The GHP SDK operates on absolute Cartesian limits (typically a 1920x1080 canvas).
/// This view scales these coordinates dynamically into local screen dimensions to ensure
/// exact bounds alignment across multiple iOS hardware display aspect ratios.
public struct ActivityZoneOverlayView: View {
  private enum Constants {
    static let defaultZoneOpacity: Double = 0.35
    static let backgroundPlaceholderOpacity: Double = 0.8
    static let customZoneFillOpacity: Double = 0.2
    static let customZoneStrokeLineWidth: Double = 2.5
    static let handleTouchTargetSize: CGFloat = 30
    static let handleTouchTargetOpacity: Double = 0.001
    static let handleOuterSize: CGFloat = 16
    static let handleInnerSize: CGFloat = 10
    static let handleShadowOpacity: Double = 0.3
    static let handleShadowRadius: CGFloat = 2
    static let handleShadowY: CGFloat = 1
  }
  /// Binding array of zones to render.
  @Binding public var zones: [ActivityZone]
  private let backgroundImage: UIImage?
  private let zoneMaxSize: CGSize
  private let editable: Bool
  private let inverse: Bool
  /// Primary constructor for rendering multiple active zones.
  ///
  /// - Parameters:
  ///   - zones: Binding array of zones.
  ///   - backgroundImage: The static snapshot image from the camera.
  ///   - zoneMaxSize: The native limits of the SDK coordinate system (e.g., 1920x1080).
  ///   - editable: If true, exposes interactive touch/drag handles on the vertices.
  ///   - inverse: If true, renders a semi-transparent background covering the entire view with holes punched out for custom zones (used to represent the Default Zone).
  public init(
    zones: Binding<[ActivityZone]>,
    backgroundImage: UIImage?,
    zoneMaxSize: CGSize,
    editable: Bool = false,
    inverse: Bool = false
  ) {
    self._zones = zones
    self.backgroundImage = backgroundImage
    self.zoneMaxSize = zoneMaxSize
    self.editable = editable
    self.inverse = inverse
  }
  /// Convenience constructor for visualizing a single activity zone binding.
  public init(
    zone: Binding<ActivityZone>,
    backgroundImage: UIImage?,
    zoneMaxSize: CGSize,
    editable: Bool = false
  ) {
    self.init(
      zones: Binding<[ActivityZone]>(
        get: { [zone.wrappedValue] },
        set: { newValue in
          if let updatedZone = newValue.first {
            zone.wrappedValue = updatedZone
          }
        }
      ),
      backgroundImage: backgroundImage,
      zoneMaxSize: zoneMaxSize,
      editable: editable,
      inverse: false
    )
  }
  /// Convenience constructor for rendering static, non-editable activity zones (no bindings required).
  public init(
    zones: [ActivityZone],
    backgroundImage: UIImage?,
    zoneMaxSize: CGSize,
    inverse: Bool = false
  ) {
    self.init(
      zones: .constant(zones),
      backgroundImage: backgroundImage,
      zoneMaxSize: zoneMaxSize,
      editable: false,
      inverse: inverse
    )
  }
  public var body: some View {
    let resolution = zoneMaxSize
    GeometryReader { geometry in
      ZStack {
        // Background Camera Snapshot
        if let backgroundImage {
          Image(uiImage: backgroundImage)
            .resizable()
            .aspectRatio(contentMode: .fill)
        } else {
          // Dynamic premium placeholder background when static feed is loading or missing
          Color.black.opacity(Constants.backgroundPlaceholderOpacity)
        }
        if inverse {
          // =============================================================
          // ADVANCED FEATURE: Inverse Mask Rendering (DestinationOut Canvas)
          // =============================================================
          // This renders the non-editable area covering the screen in a semi-transparent
          // blue mask while "punching holes" where custom active zones reside.
          let customZonePaths = zones.filter { !$0.isDefaultZone }.map { $0.vertices }
          Canvas { context, size in
            // 1. Draw base background mask
            let outerBoundsRect = Path(CGRect(origin: .zero, size: size))
            context.fill(outerBoundsRect, with: .color(Color.blue.opacity(Constants.defaultZoneOpacity)))
            // 2. Set blend mode to 'destinationOut' (any further draws will erase the base layer)
            context.blendMode = .destinationOut
            // 3. Punch holes for each custom zone shape
            for vertices in customZonePaths {
              let screenPoints = vertices.map { vertex in
                CGPoint(
                  x: (vertex.x / resolution.width) * size.width,
                  y: (vertex.y / resolution.height) * size.height
                )
              }
              if !screenPoints.isEmpty {
                var holeSubpath = Path()
                holeSubpath.move(to: screenPoints[0])
                holeSubpath.addLines(screenPoints)
                holeSubpath.closeSubpath()
                // Fills in black which completely erases the overlay on those bounds
                context.fill(holeSubpath, with: .color(.black))
              }
            }
          }
        } else {
          // =============================================================
          // STANDARD FEATURE: Render Custom Polygons and Drag Handles
          // =============================================================
          ForEach($zones) { $zone in
            let zoneValue = $zone.wrappedValue
            // Scale coordinates from absolute SDK coordinates to local viewport dimensions
            let screenPoints = zoneValue.vertices.map { vertex in
              CGPoint(
                x: (vertex.x / resolution.width) * geometry.size.width,
                y: (vertex.y / resolution.height) * geometry.size.height
              )
            }
            // 1. Draw Filled and Stroked Custom Zone Shape
            let polygonPath = Path { path in
              if !screenPoints.isEmpty {
                path.addLines(screenPoints)
                path.closeSubpath()
              }
            }
            polygonPath
              .fill(zoneValue.color.swiftUIColor.opacity(Constants.customZoneFillOpacity))
              .overlay(polygonPath.stroke(zoneValue.color.swiftUIColor, lineWidth: Constants.customZoneStrokeLineWidth))
            // 2. Draw interactive Handles for Editing Shape
            if editable {
              ForEach(Array(zoneValue.vertices.enumerated()), id: \.offset) { index, _ in
                ZStack {
                  // Large invisible touch target outer circle to satisfy ergonomics (30pt)
                  Circle()
                    .fill(Color.white.opacity(Constants.handleTouchTargetOpacity))
                    .frame(width: Constants.handleTouchTargetSize, height: Constants.handleTouchTargetSize)
                  // Visual ring handle
                  Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(Constants.handleShadowOpacity), radius: Constants.handleShadowRadius, x: 0, y: Constants.handleShadowY)
                    .frame(width: Constants.handleOuterSize, height: Constants.handleOuterSize)
                    .overlay(
                      Circle()
                        .fill(zoneValue.color.swiftUIColor)
                        .frame(width: Constants.handleInnerSize, height: Constants.handleInnerSize)
                    )
                }
                .position(screenPoints[index])
                .gesture(
                  DragGesture(coordinateSpace: .named("CanvasContainer"))
                    .onChanged { gestureState in
                      // Transform screen coordinate gesture updates back into standard SDK Cartesian coordinates
                      let rawX = (gestureState.location.x / geometry.size.width) * resolution.width
                      let rawY =
                        (gestureState.location.y / geometry.size.height) * resolution.height
                      // Enforce boundary clamping to prevent vertices from going off-screen
                      let clampedX = min(max(rawX, 0), resolution.width)
                      let clampedY = min(max(rawY, 0), resolution.height)
                      $zone.vertices[index].wrappedValue = CGPoint(x: clampedX, y: clampedY)
                    }
                )
              }
            }
          }
        }
      }
      .background(Color(uiColor: .darkGray))
    }
    .coordinateSpace(.named("CanvasContainer"))
    .aspectRatio(resolution.width / resolution.height, contentMode: .fit)
  }
}
