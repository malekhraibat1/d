import Foundation
import SwiftData

@Model
final class PersistentARMap {
    var id: UUID = UUID()
    var name: String = ""
    var worldMapData: Data? = nil
    var savedDateOnCapture: Date = Date()
    var lastUsedAt: Date = Date()
    
    var savedAnchorsCount: Int = 0
    var savedSketchesCount: Int = 0
    var areaCoveredM2: Double = 0
    
    var roof: RoofPlane?
    
    init(name: String) {
        self.name = name
    }
    
    var summary: String {
        "\(savedAnchorsCount) عنصر، \(String(format: "%.1f", areaCoveredM2)) م²"
    }
}
