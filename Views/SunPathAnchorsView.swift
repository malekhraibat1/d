import SwiftUI
import SwiftData

struct SunPathAnchorsView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    let roof: RoofPlane
    let service: ARRoofOverlayService

    @State private var showingRadiusPicker = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "sun.horizon.fill")
                            .foregroundStyle(.solarPrimary)
                        Text("إظهار كل مسارات الشمس")
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { service.sunPathPersistence.isVisible },
                            set: { service.sunPathPersistence.setVisibility($0) }
                        ))
                        .labelsHidden()
                        .tint(.solarPrimary)
                    }
                }

                Section {
                    ForEach(roof.sunPathAnchors ?? []) { anchor in
                        anchorRow(anchor)
                    }
                    .onDelete { idx in
                        let list = roof.sunPathAnchors ?? []
                        idx.forEach { i in
                            service.sunPathPersistence.delete(list[i], context: ctx)
                        }
                    }
                } header: {
                    Text("المسارات المحفوظة")
                } footer: {
                    Text("اضغط مطوّلًا على شاشة AR لإضافة مسار جديد في موقعك الحالي")
                }

                Section {
                    Button {
                        addAnchorAtCurrent()
                    } label: {
                        Label("إضافة مسار في موقعي الحالي",
                              systemImage: "plus.circle.fill")
                    }
                }
            }
            .navigationTitle("مسارات الشمس")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") { dismiss() }
                }
            }
        }
    }

    func anchorRow(_ anchor: SunPathAnchor) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "sun.horizon.fill")
                    .foregroundStyle(Color(hex: anchor.dayColorHex))
                Text(anchor.name)
                    .font(.bodyM)
                Spacer()
                if anchor.isPersistent {
                    Badge(text: "دائم",
                          color: .successGreen,
                          icon: "pin.fill")
                }
            }

            HStack(spacing: Spacing.md) {
                Label(String(format: "نصف قطر: %.1f م", anchor.radius),
                      systemImage: "circle.dashed")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Label(anchor.createdAt.formatted(date: .abbreviated, time: .omitted),
                      systemImage: "calendar")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Toggle("ثابت", isOn: Binding(
                    get: { anchor.isPersistent },
                    set: {
                        anchor.isPersistent = $0
                        service.sunPathPersistence.rebuild(for: anchor)
                        try? ctx.save()
                    }
                ))
                .font(.caption)
                .toggleStyle(.switch)

                Spacer()

                Button {
                    service.sunPathPersistence.rebuild(for: anchor)
                } label: {
                    Label("تحديث", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    func addAnchorAtCurrent() {
        // استخدم موقع الكاميرا الحالي
        guard let pos = service.raycastCenter() else { return }
        let _ = service.createSunPathAnchor(
            at: pos,
            radius: 8.0,
            context: ctx
        )
    }
}
