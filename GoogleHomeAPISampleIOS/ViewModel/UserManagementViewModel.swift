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

/// A view model that manages user authorization for structures.
@MainActor
public class UserManagementViewModel: ObservableObject {
  private let home: Home

  // User Management parameters
  @Published public var invitationID: String = ""
  @Published public var generatedInvitationToken: String?
  @Published public var structures: [Structure] = []
  @Published public var selectedStructureID: String?

  /// The list of users associated with a structure.
  @Published public var users: [GoogleHomeTypes.Google.StructureUserManagementTrait.UserMetadata] = []

  /// The list of invitations associated with a structure.
  @Published public var invitations: [GoogleHomeTypes.Google.StructureUserManagementTrait.InvitationDetails] = []

  /// The signed-in user metadata values.
  @Published public var signedInUserMetadata: StructureScopedPermissionsController.UserMetadata?

  /// Status message for showing alerts in SwiftUI.
  @Published public var statusMessage: String?

  /// Returns the users excluding the currently signed-in user.
  public var otherUsers: [GoogleHomeTypes.Google.StructureUserManagementTrait.UserMetadata] {
    guard let signedInUserId = signedInUserMetadata?.userId else {
      return users
    }
    return users.filter { $0.userId != signedInUserId }
  }

  /// Initializes the view model with a Home instance.
  public init(home: Home) {
    self.home = home
  }

  // MARK: - Public Helper

  /// Shows a status alert message.
  public func showStatus(_ message: String) {
    self.statusMessage = message
  }

  /// Loads the structures associated with the given Home instance.
  public func loadStructures() async {
    do {
      let structuresList = Array(try await home.structures().list()).sorted(by: {
        $0.name < $1.name
      })
      self.structures = structuresList
      self.selectedStructureID = structuresList.first?.id
    } catch {
      showStatus("Failed to load structures: \(error.localizedDescription)")
    }
  }

  /// Fetches users and invitations when structure selection changes.
  public func structureSelectionChanged() async {
    await fetchUsers()
    await fetchInvitations()
  }

  /// Accepts an invitation to join a structure using the `invitationID`.
  public func acceptInvitation() async -> Home? {
    do {
      return try await Home.acceptInvitation(self.invitationID)
    } catch {
      showStatus("Auth error: \(error.localizedDescription)")
      return nil
    }
  }

  /// Generates an invitation ID for the selected structure.
  public func generateInvitationID() async {
    do {
      if let structure = try await home.structures().list().first(where: {
        $0.id == selectedStructureID
      }) {
        guard let userMgmtTrait = await structure.traits.get(
          GoogleHomeTypes.Google.StructureUserManagementTrait.self
        ) else {
          showStatus("Error: Structure User Management Trait not found.")
          return
        }
        let response = try await userMgmtTrait.createInvitation(intendedUserRole: .admin)
        self.generatedInvitationToken = response.token
      }
    } catch {
      showStatus("Error generating invitation: \(error.localizedDescription)")
    }
  }

  /// Fetches the list of users for the selected structure.
  public func fetchUsers() async {
    guard let structureId = self.selectedStructureID else {
      showStatus("Error listing users: Structure ID is missing.")
      return
    }
    do {
      if let structure = try await home.structures().list().first(where: { $0.id == structureId }) {
        guard let userManagementTrait = await structure.traits.get(
          GoogleHomeTypes.Google.StructureUserManagementTrait.self
        ) else {
          showStatus("Error: Structure User Management Trait not found.")
          return
        }
        let response = try await userManagementTrait.listUsersInStructure(
          structureId: structure.id)
        self.users = response.userMetadataArray
      }
    } catch {
      showStatus("Error listing users: \(error.localizedDescription)")
    }
    await userMetadata(structureId: structureId)
  }

  /// Removes a user from the selected structure.
  public func removeUser(userId: String?) async {
    guard let validUserId = userId, !validUserId.isEmpty else {
      showStatus("Error removing user: Invalid or missing User ID.")
      return
    }
    guard let structureId = self.selectedStructureID else {
      showStatus("Error removing user: Structure ID is missing.")
      return
    }
    do {
      if let structure = try await home.structures().list().first(where: { $0.id == structureId }) {
        guard let userManagementTrait = await structure.traits.get(
          GoogleHomeTypes.Google.StructureUserManagementTrait.self
        ) else {
          showStatus("Error: Structure User Management Trait not found.")
          return
        }
        try await userManagementTrait.removeUser(
          structureId: structure.id,
          obfuscatedUserId: validUserId)
        showStatus("User removed successfully.")
        await fetchUsers()
      }
    } catch {
      showStatus("Error removing user: \(error.localizedDescription)")
    }
  }

  /// Fetches the list of pending invitations for the selected structure.
  public func fetchInvitations() async {
    self.invitations = []
    guard let structureId = self.selectedStructureID else {
      showStatus("Error listing invitations: Structure ID is missing.")
      return
    }
    do {
      if let structure = try await home.structures().list().first(where: { $0.id == structureId }) {
        guard let userManagementTrait = await structure.traits.get(
          GoogleHomeTypes.Google.StructureUserManagementTrait.self
        ) else {
          showStatus("Error: Structure User Management Trait not found.")
          return
        }
        let response = try await userManagementTrait.listInvitations()
        let fetchedInvitations = response.invitationDetailsArray
        self.invitations = fetchedInvitations.sorted {
          $0.status != .revoked && $1.status == .revoked
        }
      }
    } catch {
      showStatus("Error listing invitations: \(error.localizedDescription)")
    }
  }

  /// Revokes a pending invitation.
  public func revokeInvitation(invitationId: String?) async {
    guard let validInvitationId = invitationId, !validInvitationId.isEmpty else {
      showStatus("Error revoking invitation: Invalid or missing Invitation ID.")
      return
    }
    guard let structureId = self.selectedStructureID else {
      showStatus("Error revoking invitation: Structure ID is missing.")
      return
    }
    do {
      if let structure = try await home.structures().list().first(where: { $0.id == structureId }) {
        guard let userManagementTrait = await structure.traits.get(
          GoogleHomeTypes.Google.StructureUserManagementTrait.self
        ) else {
          showStatus("Error: User Management Trait not found.")
          return
        }
        try await userManagementTrait.revokeInvitation(
          invitationId: validInvitationId
        )
        showStatus("Invitation revoked successfully.")
        await fetchInvitations()
      } else {
        showStatus("Error revoking invitation: Structure not found.")
      }
    } catch {
      showStatus("Error revoking invitation: \(error.localizedDescription)")
    }
  }

  /// Fetches the current signed-in user's metadata.
  public func userMetadata(structureId: String?) async {
    guard let structureId = structureId else {
      showStatus("Error fetching user metadata: Structure ID is missing.")
      return
    }
    do {
      if let structure = try await home.structures().list().first(where: { $0.id == structureId }) {
        let userMetadata = try await structure.permissions.currentUserMetadata()
        self.signedInUserMetadata = userMetadata
      } else {
        showStatus("Error: Structure not found.")
      }
    } catch {
      showStatus("Error fetching user metadata: \(error.localizedDescription)")
    }
  }

  /// Determines whether a given invitation can be revoked based on its current status and ID.
  public func canRevoke(invitation: GoogleHomeTypes.Google.StructureUserManagementTrait.InvitationDetails) -> Bool {
    let hasValidId = !(invitation.invitationId?.isEmpty ?? true)
    return hasValidId && invitation.status != .accepted && invitation.status != .revoked
  }

  /// Extracts the acceptor user ID from an invitation if it has been accepted.
  public func acceptorIdToDisplay(
    for invitation: GoogleHomeTypes.Google.StructureUserManagementTrait.InvitationDetails
  ) -> String? {
    guard invitation.status == .accepted,
      let acceptorId = invitation.acceptorUserId,
      !acceptorId.isEmpty
    else {
      return nil
    }
    return acceptorId
  }

  /// Extracts the revoker user ID from an invitation if it has been revoked.
  public func revokerIdToDisplay(
    for invitation: GoogleHomeTypes.Google.StructureUserManagementTrait.InvitationDetails
  ) -> String? {
    guard invitation.status == .revoked,
      let revokerId = invitation.revokerUserId,
      !revokerId.isEmpty
    else {
      return nil
    }
    return revokerId
  }

  /// Represents a detail item (either a Date or a String) to be displayed for an invitation.
  public enum InvitationDetailItem: Hashable {
    case date(prefix: String, value: Date)
    case text(prefix: String, value: String)
  }

  /// Computes the list of details to display for a given invitation.
  public func detailsToDisplay(
    for invitation: GoogleHomeTypes.Google.StructureUserManagementTrait.InvitationDetails
  ) -> [InvitationDetailItem] {
    var details: [InvitationDetailItem] = []

    if let creationDate = invitation.creationTimestamp {
      details.append(.date(prefix: "Created:", value: creationDate))
    }

    if let expirationDate = invitation.expirationTimestamp {
      details.append(.date(prefix: "Expires:", value: expirationDate))
    }

    if let acceptorId = acceptorIdToDisplay(for: invitation) {
      details.append(.text(prefix: "Acceptor ID:", value: acceptorId))
    }

    if let revokerId = revokerIdToDisplay(for: invitation) {
      details.append(.text(prefix: "Revoker ID:", value: revokerId))
    }

    return details
  }
}
