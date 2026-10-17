/// The only three values Claude Code ever writes to `status` in a registry file.
enum RegistryStatus: String, Codable, Sendable {
    case busy
    case idle
    case waiting
}
