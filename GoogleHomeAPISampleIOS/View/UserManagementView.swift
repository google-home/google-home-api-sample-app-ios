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

import SwiftUI
import GoogleHomeSDK
import GoogleHomeTypes

/// A view that displays a dashboard for managing structure invitations, user membership, and permissions.
@MainActor
struct UserManagementView: View {
  let home: Home
  let dismissAction: () -> Void

  @StateObject private var viewModel: UserManagementViewModel

  init(home: Home, dismissAction: @escaping () -> Void) {
    self.home = home
    self.dismissAction = dismissAction
    self._viewModel = StateObject(wrappedValue: UserManagementViewModel(home: home))
  }

  var body: some View {
    Form {
      acceptInvitationSection
      structureSelectionSection
      generateInvitationSection
      structureUsersSection
      structureInvitationsSection
    }
    .navigationBarTitle("User Management", displayMode: .inline)
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        Button("Done") { dismissAction() }
      }
    }
    .task {
      await viewModel.loadStructures()
    }
    .onChange(of: viewModel.selectedStructureID) {
      Task {
        await viewModel.structureSelectionChanged()
      }
    }
    .alert(
      "Status",
      isPresented: Binding<Bool>(
        get: { viewModel.statusMessage != nil },
        set: { isPresented in
          if !isPresented {
            DispatchQueue.main.async {
              viewModel.statusMessage = nil
            }
          }
        }
      )
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(viewModel.statusMessage ?? "")
    }
  }

  // MARK: - Sections

  @ViewBuilder
  private var acceptInvitationSection: some View {
    Section(header: Text("Accept Structure Invitation")) {
      HStack {
        TextField("Invitation ID", text: $viewModel.invitationID)
          .textInputAutocapitalization(.never)
        Button("Accept invitation") {
          Task {
            if let _ = await viewModel.acceptInvitation() {
              dismissAction()
            }
          }
        }
      }
    }
  }

  @ViewBuilder
  private var structureSelectionSection: some View {
    Section(header: Text("Select Structure")) {
      if !viewModel.structures.isEmpty {
        Picker("Structure", selection: $viewModel.selectedStructureID) {
          ForEach(viewModel.structures, id: \.id) { structure in
            Text(structure.name).tag(Optional(structure.id))
          }
        }
        .pickerStyle(.menu)
      } else {
        Text("No structures found.")
          .foregroundColor(.secondary)
      }
    }
  }

  @ViewBuilder
  private var generateInvitationSection: some View {
    Section(header: Text("Generate Invitation for Selected Structure")) {
      Button("Generate Invitation Token") {
        Task {
          await viewModel.generateInvitationID()
        }
      }

      if let generatedInvitationToken = viewModel.generatedInvitationToken {
        HStack {
          Text(generatedInvitationToken)
          Spacer()
          Button("Copy") {
            UIPasteboard.general.string = generatedInvitationToken
            viewModel.statusMessage = "Invitation Token copied to clipboard."
          }
        }
      }
    }
  }

  @ViewBuilder
  private var structureUsersSection: some View {
    Section(header: Text("List Users in Selected Structure")) {
      Button("List Users in Structure") {
        Task {
          await viewModel.fetchUsers()
        }
      }

      if viewModel.signedInUserMetadata == nil && viewModel.users.isEmpty {
        Text("No users found in this structure.")
          .foregroundColor(.secondary)
      } else {
        if let metadata = viewModel.signedInUserMetadata {
          HStack {
            Image(systemName: "person.circle.fill")
              .font(.title)
              .foregroundColor(.blue)

            VStack(alignment: .leading) {
              let name = metadata.name ?? "Unknown Name"
              let email = metadata.email ?? "Unknown Email"
              let userId = metadata.userId ?? "Unknown ID"
              Text(name)
                .font(.headline)
              Text(email)
                .font(.subheadline)
                .foregroundColor(.secondary)
              Text("ID: \(userId)")
                .font(.caption)
                .foregroundColor(.secondary)
            }
            Spacer()
            Text("Self")
              .foregroundColor(.secondary)
          }
        }

        ForEach(viewModel.otherUsers, id: \.self) { user in
          HStack {
            Image(systemName: "person.circle.fill")
              .font(.title)
              .foregroundColor(.blue)

            VStack(alignment: .leading) {
              let name = user.name ?? "Unknown Name"
              let email = user.email ?? "Unknown Email"
              let userId = user.userId ?? "Unknown ID"
              Text(name)
                .font(.headline)
              Text(email)
                .font(.subheadline)
                .foregroundColor(.secondary)
              Text("ID: \(userId)")
                .font(.caption)
                .foregroundColor(.secondary)
            }
            Spacer()
            Button(role: .destructive) {
              Task {
                await viewModel.removeUser(userId: user.userId)
              }
            } label: {
              Text("Remove")
            }
            .disabled(user.userId?.isEmpty ?? true)
            .accessibilityLabel("Remove \(user.name ?? "Unknown User")")
          }
        }
      }
    }
  }

  @ViewBuilder
  private var structureInvitationsSection: some View {
    Section(header: Text("List Invitations in Selected Structure")) {
      Button("List Invitations in Structure") {
        Task {
          await viewModel.fetchInvitations()
        }
      }

      if viewModel.invitations.isEmpty {
        Text("No invitations found in this structure.")
          .foregroundColor(.secondary)
      } else {
        ForEach(viewModel.invitations, id: \.self) { invitation in
          HStack {
            let status = invitation.status ?? .invitationStatusUnspecified
            Image(systemName: status.systemIconName)
              .foregroundColor(status.iconColor)
              .font(.title)
              .accessibilityHidden(true)

            VStack(alignment: .leading) {
              let invId = invitation.invitationId ?? "Unknown Invitation ID"
              Text("ID: \(invId)")
                .font(.headline)
              invitationDetailsView(for: invitation)
            }
            Spacer()
            Button(role: .destructive) {
              Task {
                await viewModel.revokeInvitation(invitationId: invitation.invitationId)
              }
            } label: {
              Text("Revoke")
            }
            .buttonStyle(.borderless)
            .disabled(!viewModel.canRevoke(invitation: invitation))
          }
        }
      }
    }
  }

  @ViewBuilder
  private func invitationDetailsView(
    for invitation: GoogleHomeTypes.Google.StructureUserManagementTrait.InvitationDetails
  ) -> some View {
    ForEach(viewModel.detailsToDisplay(for: invitation), id: \.self) { detail in
      switch detail {
      case .date(let prefix, let value):
        Text("\(prefix) \(value, style: .date) \(value, style: .time)")
          .font(.caption)
          .foregroundColor(.secondary)
      case .text(let prefix, let value):
        Text("\(prefix) \(value)")
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
  }
}

// MARK: - Extension for InvitationStatus

extension GoogleHomeTypes.Google.StructureUserManagementTrait.InvitationStatus {
  /// Returns the system name of the SF Symbol icon associated with the invitation status.
  public var systemIconName: String {
    switch self {
    case .pending:
      return "clock.fill"
    case .accepted:
      return "checkmark.circle.fill"
    case .revoked:
      return "xmark.circle.fill"
    case .invitationStatusUnspecified:
      return "questionmark.circle.fill"
    default:
      return "questionmark.circle.fill"
    }
  }

  /// Returns the SwiftUI Color associated with the invitation status.
  public var iconColor: Color {
    switch self {
    case .pending:
      return .orange
    case .accepted:
      return .green
    case .revoked:
      return .red
    case .invitationStatusUnspecified:
      return .secondary
    default:
      return .secondary
    }
  }
}
