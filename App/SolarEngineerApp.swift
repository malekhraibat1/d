import SwiftUI
import SwiftData

@main
struct SolarEngineerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView() // افترض أن لديك ContentView تنقلك للـ Overlay
        }
        .modelContainer(for: [
            AutoDetectedElement.self,
            RoofPlane.self,
            PersistentARMap.self,
            SunPathAnchor.self
        ])
    }
}

// واجهة بسيطة للانطلاق
struct ContentView: View {
    @Query var roofs: [RoofPlane]
    @Environment(\.modelContext) var ctx
    
    var body: some View {
        NavigationStack {
            List(roofs) { roof in
                NavigationLink(roof.label) {
                    ARRoofOverlayView(roof: roof)
                }
            }
            .navigationTitle("مشاريع السطوح")
            .toolbar {
                Button("إضافة سطح") {
                    let newRoof = RoofPlane(label: "سطح جديد \(roofs.count + 1)")
                    ctx.insert(newRoof)
                }
            }
        }
    }
}
