import Foundation
import ARKit
import Vision
import simd

struct DetectionResult {
    var elements: [AutoDetectedElement]
    var processingTime: TimeInterval
    var frameCount: Int
}

@MainActor
final class AutoDetectionEngine: ObservableObject {

    // الإعدادات
    @Published var minWallArea: Double = 0.5        // م²
    @Published var minWallHeight: Double = 0.8      // م
    @Published var confidenceThreshold: Double = 0.6
    @Published var detectDoors: Bool = true
    @Published var detectWindows: Bool = true
    @Published var detectACUnits: Bool = true
    @Published var detectTanks: Bool = true
    @Published var detectEdges: Bool = true

    // الحالة
    @Published var isProcessing: Bool = false
    @Published var progress: Double = 0
    @Published var detectedCount: Int = 0
    @Published var statusMessage: String = ""

    // مكدس التتبع
    private var pendingResults: [AutoDetectedElement] = []
    private var processedHashes: Set<String> = []

    // MARK: - Main Detection Entry
    func processFrame(_ frame: ARFrame) async -> [AutoDetectedElement] {
        var detected: [AutoDetectedElement] = []

        // 1. Planes (الأساس)
        detected.append(contentsOf: detectPlanes(frame))

        // 2. Vision (كشف الأبواب/النوافذ)
        if detectDoors || detectWindows {
            if let vision = await detectWithVision(frame) {
                detected.append(contentsOf: vision)
            }
        }

        // 3. Deduplication
        return deduplicate(detected)
    }

    // MARK: - Plane Detection
    private func detectPlanes(_ frame: ARFrame) -> [AutoDetectedElement] {
        var results: [AutoDetectedElement] = []

        for anchor in frame.anchors {
            guard let plane = anchor as? ARPlaneAnchor,
                  plane.planeExtent.width > 0.1 else { continue }

            let width = Double(plane.planeExtent.width)
            let height = Double(plane.planeExtent.height)

            // فلترة حسب النوع
            let type: AutoElementType
            switch plane.alignment {
            case .horizontal:
                // التمييز بين أرضية وسقف عبر ارتفاع Y
                let y = plane.transform.columns.3.y
                if y < 0.5 {
                    type = .floor
                } else {
                    // تحقق من المساحة
                    if width * height > minWallArea {
                        type = .ceiling
                    } else {
                        continue
                    }
                }

            case .vertical:
                let wallHeight = plane.planeExtent.height
                guard wallHeight >= minWallHeight,
                      width * height >= minWallArea else { continue }
                type = .wall

            @unknown default:
                continue
            }

            // تحقق من عدم التكرار
            let hash = planeHash(plane)
            guard !processedHashes.contains(hash) else { continue }
            processedHashes.insert(hash)

            let element = AutoDetectedElement(
                type: type,
                center: SIMD3(
                    plane.transform.columns.3.x,
                    plane.transform.columns.3.y,
                    plane.transform.columns.3.z
                ),
                width: width,
                height: height
            )
            element.area = width * height
            element.depth = 0.02
            element.detectionMethod = "plane"
            element.confidence = Double(plane.confidence.rawValue) / 2 + 0.5

            // احفظ الدوران
            let q = simd_quatf(plane.transform)
            element.qx = q.imag.x
            element.qy = q.imag.y
            element.qz = q.imag.z
            element.qw = q.real

            // احفظ حدود المضلع
            let extent = plane.planeExtent
            let centerX = plane.center.x
            let centerZ = plane.center.z
            let halfW = extent.width / 2
            let halfH = extent.height / 2

            var polygon: [SIMD3<Float>] = []
            let corners = [
                SIMD2<Float>(-halfW, -halfH),
                SIMD2<Float>(halfW, -halfH),
                SIMD2<Float>(halfW, halfH),
                SIMD2<Float>(-halfW, halfH)
            ]

            for corner in corners {
                let localPoint = SIMD4<Float>(corner.x, 0, corner.y, 1)
                let worldPoint = plane.transform * localPoint
                polygon.append(SIMD3(worldPoint.x, worldPoint.y, worldPoint.z))
            }
            element.polygon = polygon

            results.append(element)
        }

        return results
    }

    // MARK: - Vision Detection (doors, windows, AC units)
    private func detectWithVision(_ frame: ARFrame) async -> [AutoDetectedElement]? {
        let pixelBuffer = frame.capturedImage
        let viewportSize = CGSize(
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )

        var results: [AutoDetectedElement] = []

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let request = VNDetectRectanglesRequest { req, error in
                defer { continuation.resume() }

                guard let observations = req.results as? [VNRectangleObservation],
                      error == nil else { return }

                for obs in observations {
                    // فلترة حسب الثقة
                    guard Double(obs.confidence) >= self.confidenceThreshold else { continue }

                    // حول إحداثيات Vision إلى AR
                    if let element = self.convertVisionRect(
                        obs, frame: frame, viewportSize: viewportSize
                    ) {
                        results.append(element)
                    }
                }
            }

            // إعدادات
            request.maximumObservations = 15
            request.minimumConfidence = 0.5
            request.minimumAspectRatio = 0.2
            request.maximumAspectRatio = 5.0
            request.quadratureTolerance = 25
            request.minimumSize = 0.15
            request.minimumDuration = 0

            let handler = VNImageRequestHandler(
                cvPixelBuffer: pixelBuffer,
                orientation: .right,
                options: [:]
            )

            do {
                try handler.perform([request])
            } catch {
                continuation.resume()
            }
        }

        return results
    }

    private func convertVisionRect(_ obs: VNRectangleObservation,
                                    frame: ARFrame,
                                    viewportSize: CGSize) -> AutoDetectedElement? {
        // متوسط الأربع زوايا كـ center
        let corners = [
            obs.topLeft, obs.topRight, obs.bottomRight, obs.bottomLeft
        ]
        let avgX = corners.map { $0.x }.reduce(0, +) / 4
        let avgY = corners.map { $0.y }.reduce(0, +) / 4

        // Vision: 0,0 أسفل-يسار، AR: 0,0 أعلى-يسار
        let visionPoint = CGPoint(x: avgX, y: 1 - avgY)

        // raycast عبر الكاميرا
        guard let query = frame.raycastQuery(
            from: visionPoint,
            allowing: .estimatedPlane,
            alignment: .vertical
        ) else { return nil }

        let results = frame.session.raycast(query)
        guard let hit = results.first else { return nil }

        // حجم تقريبي من المسافة
        let distance = simd_distance(
            hit.worldTransform.columns.3.xyz,
            frame.camera.transform.columns.3.xyz
        )

        // تقدير الحجم
        let rectWidth = Double(obs.boundingBox.width) * Double(viewportSize.width)
        let rectHeight = Double(obs.boundingBox.height) * Double(viewportSize.height)

        let fx = Double(frame.camera.intrinsics[0][0])
        let fy = Double(frame.camera.intrinsics[1][1])

        let realWidth = (rectWidth / fx) * Double(distance) * 0.5
        let realHeight = (rectHeight / fy) * Double(distance) * 0.5

        // صنّف النوع حسب الأبعاد
        let type: AutoElementType
        if realHeight < 0.6 && realWidth < 0.6 {
            // صغير جدًا
            return nil
        } else if realHeight > 2.0 {
            // كبير جدًا - يبدو كجدار
            return nil
        } else if realWidth / realHeight > 0.5 && realWidth / realHeight < 2.5 {
            // قريب من مربع - باب أو نافذة
            type = realWidth > 1.0 ? .door : .window
        } else {
            type = .door
        }

        // فلترة النوع
        if type == .door && !detectDoors { return nil }
        if type == .window && !detectWindows { return nil }

        let element = AutoDetectedElement(
            type: type,
            center: hit.worldTransform.columns.3.xyz,
            width: realWidth,
            height: realHeight
        )
        element.area = realWidth * realHeight
        element.detectionMethod = "vision"
        element.confidence = Double(obs.confidence) * 0.8  // Vision أقل دقة من plane

        return element
    }

    // MARK: - Edge Detection (من mesh LiDAR)
    func detectEdgesFromMesh(meshAnchors: [ARMeshAnchor]) -> [AutoDetectedElement] {
        guard detectEdges else { return [] }

        var results: [AutoDetectedElement] = []
        var processedCount = 0

        for mesh in meshAnchors {
            let geometry = mesh.geometry
            let vertices = geometry.vertices
            let faces = geometry.faces

            // لكل face، احسب normal
            for faceIndex in 0..<faces.count {
                guard let faceVertices = extractFaceVertices(
                    face: faces[faceIndex], vertices: vertices
                ) else { continue }

                guard faceVertices.count >= 3 else { continue }

                // Normal من 3 نقاط
                let v1 = faceVertices[1] - faceVertices[0]
                let v2 = faceVertices[2] - faceVertices[0]
                let normal = simd_normalize(simd_cross(v1, v2))

                // احسب الميل
                let dotY = abs(normal.y)

                // نبحث عن أسطح شبه أفقية (سطح)
                guard dotY > 0.9 else { continue }
                // في ارتفاع معقول (2-50 متر)
                guard faceVertices[0].y > 1.5,
                      faceVertices[0].y < 50 else { continue }

                processedCount += 1
                guard processedCount % 20 == 0 else { continue }

                // احسب مركز وأبعاد
                let center = faceVertices.reduce(SIMD3<Float>(0, 0, 0), +)
                    / Float(faceVertices.count)

                let xs = faceVertices.map(\.x)
                let zs = faceVertices.map(\.z)
                let width = Double(xs.max()! - xs.min()!)
                let depth = Double(zs.max()! - zs.min()!)

                guard width > 0.5 && depth > 0.5 else { continue }

                let element = AutoDetectedElement(
                    type: .roofEdge,
                    center: center,
                    width: width,
                    height: depth
                )
                element.area = width * depth
                element.detectionMethod = "mesh"
                element.confidence = 0.9

                // Marker: خزّن النقاط كـ polygon
                var poly: [SIMD3<Float>] = []
                for v in faceVertices {
                    poly.append(v)
                }
                element.polygon = poly

                results.append(element)

                if results.count >= 50 { break }
            }

            if results.count >= 50 { break }
        }

        return results
    }

    private func extractFaceVertices(face: ARMeshGeometry.Face,
                                      vertices: ARMeshGeometry.VertexBuffer) -> [SIMD3<Float>]? {
        let indexCount = face.count
        guard indexCount >= 3 else { return nil }

        var result: [SIMD3<Float>] = []
        let indices = face.indices

        for i in 0..<indexCount {
            let idx = indices[i]
            guard idx < vertices.count else { continue }

            let vertex = vertices[idx]
            let position = vertex.position
            result.append(SIMD3(position.x, position.y, position.z))
        }

        return result.isEmpty ? nil : result
    }

    // MARK: - Helpers
    private func planeHash(_ plane: ARPlaneAnchor) -> String {
        let x = Int(plane.center.x * 100)
        let y = Int(plane.center.y * 100)
        let z = Int(plane.center.z * 100)
        let w = Int(plane.planeExtent.width * 100)
        return "\(x)_\(y)_\(z)_\(w)"
    }

    private func deduplicate(_ elements: [AutoDetectedElement]) -> [AutoDetectedElement] {
        var result: [AutoDetectedElement] = []

        for element in elements {
            let isDuplicate = result.contains { existing in
                let distance = simd_distance(existing.center, element.center)
                let sameType = existing.type == element.type
                return sameType && distance < 0.3
            }
            if !isDuplicate {
                result.append(element)
            }
        }

        return result
    }

    func reset() {
        pendingResults.removeAll()
        processedHashes.removeAll()
        detectedCount = 0
        progress = 0
    }
}

// MARK: - SIMD4 Extension
extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> {
        SIMD3(x, y, z)
    }
}
