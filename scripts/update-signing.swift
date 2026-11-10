// Ed25519 signing for update archives (see UpdateSignature in AirCursorCore).
//
//   swift scripts/update-signing.swift generate <private-key-file>
//       Creates a key pair. Writes the private key (base64) to the file with 0600
//       permissions and prints only the public key, to paste into UpdateInstaller.swift.
//       Store the private key as the UPDATE_SIGNING_KEY repository secret, and keep a
//       backup somewhere safe: without it, future releases can't auto-install.
//
//   UPDATE_SIGNING_KEY=<base64> swift scripts/update-signing.swift sign <archive>
//       Prints the archive's signature (base64), the contents of <archive>.sig.
//
//   UPDATE_SIGNING_KEY=<base64> swift scripts/update-signing.swift public
//       Prints the public key that belongs to the private key.
import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

func privateKeyFromEnvironment() -> Curve25519.Signing.PrivateKey {
    guard let text = ProcessInfo.processInfo.environment["UPDATE_SIGNING_KEY"],
          let data = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: data)
    else { fail("UPDATE_SIGNING_KEY is missing or not a base64 Ed25519 private key") }
    return key
}

let args = CommandLine.arguments.dropFirst()
switch (args.first, args.dropFirst().first) {
case ("generate", let path?):
    let url = URL(fileURLWithPath: path)
    if FileManager.default.fileExists(atPath: url.path) { fail("\(path) already exists; not overwriting a key") }
    let key = Curve25519.Signing.PrivateKey()
    let created = FileManager.default.createFile(
        atPath: url.path,
        contents: Data((key.rawRepresentation.base64EncodedString() + "\n").utf8),
        attributes: [.posixPermissions: 0o600])
    guard created else { fail("couldn't write \(path)") }
    print(key.publicKey.rawRepresentation.base64EncodedString())

case ("sign", let path?):
    let key = privateKeyFromEnvironment()
    guard let data = FileManager.default.contents(atPath: path) else { fail("can't read \(path)") }
    let signature = try key.signature(for: data)
    guard key.publicKey.isValidSignature(signature, for: data) else { fail("signature self-check failed") }
    print(signature.base64EncodedString())

case ("public", _):
    print(privateKeyFromEnvironment().publicKey.rawRepresentation.base64EncodedString())

default:
    fail("usage: update-signing.swift generate <file> | sign <archive> | public")
}
