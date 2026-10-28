import Foundation

struct SubtitleStyle: Codable, Equatable {
    var font = "Arial"
    var size = 42.0
    var margin = 36.0
    var alignment = "center"
    var foreground = "#FFFFFFFF"
    var background = "#00000000"
    var outline = "#FF000000"
    var delay = 0.0
    var secondaryDelay = 0.0

    static func load() -> SubtitleStyle {
        guard let data = UserDefaults.standard.data(forKey: "AnPinime.subtitleStyle"),
              let value = try? JSONDecoder().decode(SubtitleStyle.self, from: data) else { return SubtitleStyle() }
        return value
    }
    func save() { if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: "AnPinime.subtitleStyle") } }
}
