import Foundation
import ARKit
import SwiftData
import Combine

@MainActor
final class ARMapPersistenceService: ObservableObject {

    enum MapState: Equatable {
        case idle
        case capturing(progress: Double)
        case loading(progress: Double)
        case ready
        case failed(String)

        var description: String {
            switch self {
            case .idle: return "جاهز"
            case .capturing(let p): return "جاري الحفظ... \(Int(p * 100))%"
            case .loading(let p): return "جاري التحميل... \(Int(p * 100))%"
            case .ready: return "تم الاسترجاع بنجاح"
            case .failed(let msg): return "فشل: \(msg)"
            }
        }
        static func == (lhs: MapState, rhs: MapState) -> Bool {
            lhs.description == rhs.description
        }
    }

    @Published var state: MapState = .idle
    @Published var currentMap: PersistentARMap?
    @Published var hasActiveMap: Bool = false

    // MARK: - Capture
    func captureWorldMap(session: ARSession,
                          roof: RoofPlane,
                          name: String = "") async throws -> PersistentARMap {

        state = .capturing(progress: 0)

        // 1. احصل على worldMap
        let worldMap: ARWorldMap = try await withCheckedThrowingContinuation { cont in
            session.getCurrentWorldMap { map, error in
                if let error = error {
                    cont.resume(throwing: error)
                } else if let map = map {
                    cont.resume(returning: map)
                } else {
                    cont.resume(throwing: NSError(domain: "ARMap", code: -1,
                                                    userInfo: [NSLocalizedDescriptionKey: "لا يوجد world map"]))
                }
            }
        }

        state = .capturing(progress: 0.5)

        // 2. شفّر
        let data = try NSKeyedArchiver.archivedData(
            withRootObject: worldMap,
            requiringSecureCoding: true
        )

        state = .capturing(progress: 0.8)

        // 3. أنشئ record
        let record = PersistentARMap(
            name: name.isEmpty ? "خريطة \(Date().formatted(date: .abbreviated, time: .shortened))" : name
        )
        record.worldMapData = data
        record.roof = roof
        record.savedAnchorsCount = (roof.arAnchors ?? []).count
        record.savedSketchesCount = (roof.drawing?.sketches ?? []).count
        record.areaCoveredM2 = roof.drawing?.netUsableArea ?? 0
        record.savedDateOnCapture = Date()

        state = .capturing(progress: 1.0)
        state = .ready

        return record
    }

    // MARK: - Load
    func loadWorldMap(from record: PersistentARMap,
                       session: ARSession) async throws {
        guard let data = record.worldMapData else {
            throw NSError(domain: "ARMap", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "الخريطة فارغة"])
        }

        state = .loading(progress: 0.3)

        // فك التشفير
        guard let worldMap = try? NSKeyedUnarchiver.unarchivedObject(
            ofClass: ARWorldMap.self,
            from: data
        ) else {
            state = .failed("فشل فك التشفير")
            throw NSError(domain: "ARMap", code: -3,
                          userInfo: [NSLocalizedDescriptionKey: "فك التشفير فشل"])
        }

        state = .loading(progress: 0.6)

        // أعد التشغيل بـ initialWorldMap
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        config.initialWorldMap = worldMap

        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = .meshWithClassification
        } else if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }

        session.run(config, options: [.resetTracking, .removeExistingAnchors])

        state = .loading(progress: 1.0)
        state = .ready

        currentMap = record
        hasActiveMap = true

        // تحديث lastUsedAt
        record.lastUsedAt = Date()
    }

    // MARK: - Detect relocalization
    func checkRelocalization(frame: ARFrame) {
        guard hasActiveMap else { return }

        switch frame.camera.trackingState {
        case .normal:
            if state != .ready {
                state = .ready
            }
        case .limited(let reason):
            if reason == .relocalizing {
                state = .loading(progress: 0.5)
            }
        case .notAvailable:
            break
        }
    }

    // MARK: - Reset
    func reset() {
        state = .idle
        currentMap = nil
        hasActiveMap = false
    }

    // MARK: - Delete
    func delete(_ record: PersistentARMap, context: ModelContext) {
        context.delete(record)
        try? context.save()
        if currentMap?.id == record.id {
            reset()
        }
    }
}
