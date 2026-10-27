import Foundation

/// Local history is partitioned by provider, just like search results.
struct SearchHistory {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func queries(for source: ContentSource) -> [String] {
        defaults.stringArray(forKey: key(source)) ?? []
    }

    func record(_ query: String, source: ContentSource) {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        var values = queries(for: source).filter { $0.caseInsensitiveCompare(clean) != .orderedSame }
        values.insert(clean, at: 0)
        defaults.set(Array(values.prefix(20)), forKey: key(source))
    }

    func remove(_ query: String, source: ContentSource) {
        defaults.set(queries(for: source).filter { $0 != query }, forKey: key(source))
    }

    func clear(source: ContentSource) { defaults.removeObject(forKey: key(source)) }
    private func key(_ source: ContentSource) -> String { "AnPinime.searchHistory." + source.rawValue }
}
