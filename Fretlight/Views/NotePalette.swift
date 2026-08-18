import SwiftUI

enum NotePalette {
    static func color(for name: String) -> Color {
        switch name {
        case "C":  Color(red: 0.93, green: 0.32, blue: 0.30)
        case "C♯": Color(red: 0.94, green: 0.50, blue: 0.24)
        case "D":  Color(red: 0.89, green: 0.68, blue: 0.21)
        case "D♯": Color(red: 0.78, green: 0.78, blue: 0.25)
        case "E":  Color(red: 0.36, green: 0.77, blue: 0.34)
        case "F":  Color(red: 0.27, green: 0.74, blue: 0.51)
        case "F♯": Color(red: 0.27, green: 0.72, blue: 0.78)
        case "G":  Color(red: 0.26, green: 0.55, blue: 0.84)
        case "G♯": Color(red: 0.40, green: 0.41, blue: 0.84)
        case "A":  Color(red: 0.60, green: 0.42, blue: 0.83)
        case "A♯": Color(red: 0.75, green: 0.33, blue: 0.78)
        case "B":  Color(red: 0.86, green: 0.30, blue: 0.55)
        default: .orange
        }
    }
}
