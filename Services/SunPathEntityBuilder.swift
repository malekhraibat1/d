import RealityKit
import UIKit

struct SunPathEntityBuilder {
    static func build(from data: SunPathData, color: UIColor) -> Entity {
        let container = Entity()
        
        for i in 0..<(data.points.count - 1) {
            let start = data.points[i]
            let end = data.points[i+1]
            
            let mesh = MeshResource.generateSphere(radius: 0.02)
            let material = SimpleMaterial(color: color, isMetallic: false)
            let model = ModelEntity(mesh: mesh, materials: [material])
            
            model.position = start
            container.addChild(model)
        }
        return container
    }
}
