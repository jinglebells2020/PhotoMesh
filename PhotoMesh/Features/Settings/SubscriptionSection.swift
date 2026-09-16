import SwiftUI
import RevenueCat
import RevenueCatUI

/// Settings → SUBSCRIPTION. Subscribers get the Customer Center (change plan, cancel, refund,
/// redeem a code); everyone else gets the paywall and a restore button.
struct SubscriptionSettingsSection: View {
    @State private var presentingPaywall = false
    @State private var presentingCustomerCenter = false
    @State private var restoring = false
    @State private var restoreMessage: String?

    private var store: Subscriptions { Subscriptions.shared }

    var body: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PhotoMesh Plus").foregroundStyle(PMTheme.ink)
                    Text(store.status.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(PMTheme.secondaryText)
                }
                Spacer()
                if store.isPro {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(PMTheme.plusOrange)
                }
            }

            if store.isPro {
                Button("Manage subscription") { presentingCustomerCenter = true }
                    .foregroundStyle(PMTheme.accent)
            } else {
                Button("See plans") { presentingPaywall = true }
                    .foregroundStyle(PMTheme.accent)
                Button {
                    restore()
                } label: {
                    HStack {
                        Text("Restore purchases").foregroundStyle(PMTheme.accent)
                        if restoring {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(restoring)
            }
        } header: {
            Text("SUBSCRIPTION")
        } footer: {
            Text(restoreMessage ?? "Plus removes the beta scan limit and unlocks every solving method. Subscriptions renew through your Apple Account until cancelled.")
                .foregroundStyle(restoreMessage == nil ? PMTheme.secondaryText : PMTheme.whyOrange)
        }
        .task { await store.refresh() }
        .sheet(isPresented: $presentingPaywall) {
            PaywallView(displayCloseButton: true)
                .onPurchaseCompleted { _ in
                    Haptics.notify(.success)
                    presentingPaywall = false
                }
        }
        .presentCustomerCenter(isPresented: $presentingCustomerCenter, onDismiss: {
            presentingCustomerCenter = false
        })
    }

    private func restore() {
        restoring = true
        restoreMessage = nil
        Task {
            let restored = await store.restore()
            restoring = false
            restoreMessage = restored ? nil : (store.lastError ?? "Nothing to restore.")
            if restored { Haptics.notify(.success) }
        }
    }
}
