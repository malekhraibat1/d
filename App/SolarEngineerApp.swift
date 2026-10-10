import SwiftUI

@main
struct SolarEngineerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.layoutDirection, .rightToLeft)
        }
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("الرئيسية", systemImage: "sun.max.fill") }
            AboutView()
                .tabItem { Label("حول", systemImage: "info.circle.fill") }
        }
        .tint(.orange)
    }
}

struct HomeView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 90))
                    .foregroundStyle(.orange.gradient)

                Text("SolarEngineer")
                    .font(.largeTitle.bold())

                Text("مساعد مهندس الطاقة الشمسية")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    FeatureRow(icon: "square.grid.3x3.fill",
                               title: "تخطيط الألواح", color: .blue)
                    FeatureRow(icon: "arkit",
                               title: "الواقع المعزز", color: .purple)
                    FeatureRow(icon: "doc.text.fill",
                               title: "الفواتير", color: .green)
                    FeatureRow(icon: "chart.bar.fill",
                               title: "التقارير", color: .orange)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)

                Spacer()

                Text("الإصدار 1.0.0")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .navigationTitle("الرئيسية")
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(title).font(.body)
            Spacer()
        }
    }
}

struct AboutView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("عن التطبيق") {
                    LabeledContent("الاسم", value: "SolarEngineer")
                    LabeledContent("الإصدار", value: "1.0.0")
                }
            }
            .navigationTitle("حول")
        }
    }
}
