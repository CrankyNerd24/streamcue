import SwiftUI
import StoreKit

/// Presented from Settings when a free-tier user taps a premium feature.
/// A one-time, non-consumable unlock — not a subscription.
struct PaywallView: View {
    @Environment(PurchaseManager.self) private var purchases
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Household sharing", systemImage: "person.2")
                    Label("Automatic Reminders sync", systemImage: "bell.badge")
                } header: {
                    Text("StreamCue Premium")
                } footer: {
                    Text("A one-time unlock, not a subscription. Restores free on every device signed into this Apple ID.")
                }

                Section {
                    Button {
                        Task { await purchases.purchase() }
                    } label: {
                        HStack {
                            Text(purchases.product.map { "Unlock — \($0.displayPrice)" } ?? "Unlock")
                            if purchases.isWorking {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(purchases.isWorking || purchases.product == nil)

                    Button("Restore purchases") {
                        Task { await purchases.restore() }
                    }
                    .disabled(purchases.isWorking)
                }
            }
            .themedList()
            .navigationTitle("Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await purchases.loadProduct() }
            .onChange(of: purchases.isPremium) { _, unlocked in
                if unlocked { dismiss() }
            }
            .alert(
                "Couldn't complete purchase",
                isPresented: Binding(
                    get: { purchases.errorMessage != nil },
                    set: { if !$0 { purchases.errorMessage = nil } }
                )
            ) {
                Button("OK") { purchases.errorMessage = nil }
            } message: {
                Text(purchases.errorMessage ?? "")
            }
        }
    }
}
