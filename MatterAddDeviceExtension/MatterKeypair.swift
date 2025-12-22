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
import Foundation
import Matter
import OSLog
import Security

/// Implementation of the `MTRKeypair` protocol from the Matter SDK to be used for testing 3P fabric
/// commissioning.
class MatterKeypair: NSObject, MTRKeypair {

  private var storedPrivateKey: SecKey?
  private var storedPublicKey: SecKey?

  // MARK: - Public

  public var isInitialized: Bool {
    return self.storedPrivateKey != nil && self.storedPublicKey != nil
  }

  public func initialize() throws {
    Logger().info("Initializing the MatterKeypair instance.")

    guard !self.isInitialized else {
      Logger().info("Not re-initializing the MatterKeypair instance, already initialized.")
      return
    }

    let privateKey = try Self.generatePrivateKey()

    guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
      Logger().error("Failed to copy public key.")
      throw Error.copyPublicKeyFailed
    }

    self.storedPublicKey = publicKey
    self.storedPrivateKey = privateKey

    Logger().info("Finished initializing the MatterKeypair.")
  }

  // MARK: - `MTRKeypair`

  /// Signs a hash using ECDSA.
  ///
  public func signMessageECDSA_DER(_ message: Data) -> Data {
    Logger().info("`signMessageECDSA_DER` called before `initialize`.")

    guard let privateKey = self.storedPrivateKey else {
      Logger().error("Stored private key is nil.")
      return Data()
    }

    Logger().info("Running signMessageECDSA_DER for message: \(message).")

    var error: Unmanaged<CFError>? = nil
    let signedMessage = SecKeyCreateSignature(
      privateKey,
      .ecdsaSignatureMessageX962SHA256,
      message as CFData,
      &error
    )

    if error != nil {
      Logger().error("Failed to sign hash.")
      return Data()
    }

    guard let signedMessage = signedMessage else {
      Logger().info("SecKeyCreateSignature returned nil.")
      return Data()
    }

    Logger().info("Signed message: \(signedMessage as Data).")
    return signedMessage as Data
  }

  /// Returns the keypair's public key.
  public func publicKey() -> Unmanaged<SecKey> {
    Logger().info("`publicKey` called before `initialize`.")

    return Unmanaged.passRetained(self.storedPublicKey!).autorelease()
  }

  // MARK: - Private

  /// Generates a new keypair to be stored in memory.
  ///
  /// Since this doesn't store the keypair in the keychain, it cannot be reused across app launches.
  /// This is fine since it is just for the purpose of testing commissioning.
  ///
  /// - Throws: An error if the keypair could not be generated.
  /// - Returns: The generated private key.
  private static func generatePrivateKey() throws -> SecKey {

    let attributes: [CFString: Any] = [
      kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
      kSecAttrKeyClass: kSecAttrKeyClassPrivate,
      kSecAttrKeySizeInBits: 256,
      kSecAttrIsPermanent: false,
    ]

    var error: Unmanaged<CFError>? = nil

    let secKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error)

    if error != nil {
      Logger().error("Failed to create new private key.")
      throw Error.generatePrivateKeyFailed
    }

    guard let secKey = secKey else {
      Logger().error("SecKeyCreateRandomKey returned nil.")
      throw Error.generatePrivateKeyReturnedNil
    }

    return secKey
  }
}

// MARK: - `MatterKeypair.Error`

extension MatterKeypair {

  /// Namespaced errors produced by `MatterKeypair`.
  public enum Error: Swift.Error {

    case copyPublicKeyFailed
    case generatePrivateKeyFailed
    case generatePrivateKeyReturnedNil
  }
}
