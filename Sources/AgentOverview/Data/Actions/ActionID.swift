import Foundation

/// Ids for actions created in Settings. An id is made once, from the name the action was added
/// with, and never changes afterwards (renaming keeps it): it names the face's seed and the
/// `launch-<id>.command` file, so it has to stay stable and safe in a file name.
extension ActionItem {
    /// Longest slug taken from a name, before any `-2` suffix.
    static let idSlugLimit = 32

    /// Fallback slug for a name without a single letter or digit (only symbols or emoji).
    static let idFallback = "action"

    /// The slug of `name`: transliterated to Latin, diacritics and case folded, every run of
    /// characters other than `a-z` and `0-9` turned into one `-`, no `-` at either end, at most
    /// `idSlugLimit` characters. Empty becomes `idFallback`.
    static func slug(for name: String) -> String {
        var text = name.replacingOccurrences(of: "ß", with: "ss")
        text = text.applyingTransform(.toLatin, reverse: false) ?? text
        text = text.applyingTransform(.stripDiacritics, reverse: false) ?? text
        text = text.lowercased()

        var slug = ""
        var pendingDash = false
        for scalar in text.unicodeScalars {
            let isAllowed = ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar)
            if isAllowed {
                if pendingDash, !slug.isEmpty { slug.append("-") }
                pendingDash = false
                slug.unicodeScalars.append(scalar)
            } else {
                pendingDash = true
            }
        }
        if slug.count > idSlugLimit {
            slug = String(slug.prefix(idSlugLimit))
            while slug.hasSuffix("-") { slug.removeLast() }
        }
        return slug.isEmpty ? idFallback : slug
    }

    /// A new id for an action named `name`: its slug, or the slug with `-2`, `-3` and so on when an id
    /// in `existing` already has it. Compared without regard to case, because the launch files of
    /// `Review` and `review` would be one file on a case-insensitive disk.
    static func makeID(for name: String, existing: some Sequence<String>) -> String {
        let taken = Set(existing.map { $0.lowercased() })
        let base = slug(for: name)
        guard taken.contains(base) else { return base }
        var number = 2
        while taken.contains("\(base)-\(number)") { number += 1 }
        return "\(base)-\(number)"
    }
}
