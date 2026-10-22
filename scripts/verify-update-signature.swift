// Checks that an EdDSA signature from Sparkle's sign_update verifies with a public key, so a release
// signed with another private key than the one matching Info.plist's SUPublicEDKey never ships: the
// installed apps would refuse that update and every later one signed the same way.
//
//   swift scripts/verify-update-signature.swift <public key base64> <signature base64> <file>
//
// Exits 0 when the signature is valid, 1 otherwise.
import CryptoKit
import Foundation

let arguments = CommandLine.arguments.dropFirst()
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: verify-update-signature.swift <public key> <signature> <file>\n".utf8))
    exit(2)
}
let values = Array(arguments)
guard let keyData = Data(base64Encoded: values[0]), let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
      let signature = Data(base64Encoded: values[1]),
      let file = FileManager.default.contents(atPath: values[2]) else {
    FileHandle.standardError.write(Data("verify-update-signature: unreadable key, signature or file\n".utf8))
    exit(1)
}
exit(key.isValidSignature(signature, for: file) ? 0 : 1)
