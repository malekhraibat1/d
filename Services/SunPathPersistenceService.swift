import Foundation
import ARKit
import RealityKit
import SwiftData
import Combine

@MainActor
final class SunPathPersistenceService: ObservableObject {

    @Published var activeAnchors: [SunPathAnchor] = []
    @Published var isVisible: Bool = true
    @Published var autoUpdateHourly: Bool = true

    private var anchorEntities: [UUID: Entity] = []
    private weak var rootAnchor: AnchorEntity?
    private var updateTimer: Timer?

    // MARK: - Setup
    func attach(to root: AnchorEntity) {
        self.rootAnchor = root
    }

    // MARK: - Load for roof
    func loadAnchors(for roof: RoofPlane) {
        activeAnchors = roof.sunPathAnchors ?? []
        rebuildAll()
    }

    // MARK: - Create New
    func createAnchor(at position: SIMD3<Float>,
                       radius: Double = 8.0,
                       for roof: RoofPlane,
                       context: ModelContext) -> SunPathAnchor {
        let anchor = SunPathAnchor(
            position: position,
            radius: radius,
            name: "مسار \(roof.label) \(activeAnchors.count + 1)"
        )
        anchor.roof = roof
        context.insert(anchor)
        roof.sunPathAnchors?.append(anchor)
        activeAnchors.append(anchor)

        try? context.save()
        buildEntity(for: anchor)
        return anchor
    }

    // MARK: - Build Entity
    private func buildEntity(for anchor: SunPathAnchor) {
        guard let root = rootAnchor else { return }

        // احذف القديم
        anchorEntities[anchor.id]?.removeFromParent()

        // استخدم تاريخ اليوم الحقيقي
        let data = SunPathGenerator.generate(
            latitude: anchor.roof?.latitude ?? 24.7,
            longitude: 46.7,
            date: Date(),
            anchorPosition: anchor.position,
            radius: Float(anchor.radius)
        )

        let entity = SunPathEntityBuilder.build(
            from: data,
            color: UIColor(hex: anchor.dayColorHex)
        )
        entity.name = "SunPath_\(anchor.id.uuidString)"
        entity.isEnabled = isVisible && anchor.isPersistent

        root.addChild(entity)
        anchorEntities[anchor.id] = entity
    }

    // MARK: - Rebuild All
    private func rebuildAll() {
        for entity in anchorEntities.values {
            entity.removeFromParent()
        }
        anchorEntities.removeAll()

        for anchor in activeAnchors {
            buildEntity(for: anchor)
        }
    }

    // MARK: - Update
    func rebuild(for anchor: SunPathAnchor) {
        buildEntity(for: anchor)
    }

    func rebuildAllNow() {
        rebuildAll()
    }

    // MARK: - Visibility
    func setVisibility(_ visible: Bool) {
        isVisible = visible
        for entity in anchorEntities.values {
            entity.isEnabled = visible
        }
    }

    func toggleVisibility() {
        setVisibility(!isVisible)
    }

    // MARK: - Delete
    func delete(_ anchor: SunPathAnchor, context: ModelContext) {
        anchorEntities[anchor.id]?.removeFromParent()
        anchorEntities.removeValue(forKey: anchor.id)
        activeAnchors.removeAll { $0.id == anchor.id }

        anchor.roof?.sunPathAnchors?.removeAll { $0.id == anchor.id }
        context.delete(anchor)
        try? context.save()
    }

    // MARK: - Auto Update
    func startAutoUpdate() {
        guard autoUpdateHourly else { return }
        updateTimer?.invalidate()

        // حدّث كل ساعة
        updateTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.rebuildAllNow()
            }
        }
    }

    func stopAutoUpdate() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    deinit {
        updateTimer?.invalidate()
    }
}
