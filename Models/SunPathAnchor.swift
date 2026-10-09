import Foundation
import SwiftData
import simd

@Model
final class SunPathAnchor {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()

    // موقع الـ anchor
    var positionX: Float = 0
    var positionY: Float = 0
    var positionZ: Float = 0

    // نصف قطر المسار
    var radius: Double = 8.0

    // هل يظهر دائمًا؟
    var isPersistent: Bool = true
    var showHourMarkers: Bool = true
    var showSunriseSunset: Bool = true

    // المظهر
    var dayColorHex: String = "FF9F0A"
    var nightColorHex: String = "8E8E93"
    var opacity: Double = 1.0

    // ربط
    var roof: RoofPlane?
    var linkedMap: PersistentARMap?

    init(position: SIMD3<Float> = .zero,
         radius: Double = 8.0,
         name: String = "مسار الشمس") {
        self.positionX = position.x
        self.positionY = position.y
        self.positionZ = position.z
        self.radius = radius
        self.name = name
    }

    var position: SIMD3<Float> {
        SIMD3(positionX, positionY, positionZ)
    }
}
