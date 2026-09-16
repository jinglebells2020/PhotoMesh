import SwiftUI
import RevenueCat
import RevenueCatUI

/// PhotoMesh Plus. Subscribers see what they have; everyone else sees the RevenueCat paywall,
/// so the plans, prices and copy are whatever the dashboard's current offering says.
struct PlusSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var presentingCustomerCenter = false

    private var store: Subscriptions { Subscriptions.shared }

    var body: some View {
        Group {
            if store.isPro {
                subscribed
            } else {
                // Handles its own loading, purchase and restore flows.
                PaywallView(displayCloseButton: true)
            }
        }
        .onPurchaseCompleted { _ in
            Haptics.notify(.success)
            Analytics.shared.track("purchase_completed")
            dismiss()
        }
        .onRestoreCompleted { info in
            // The paywall closes itself when the entitlement is active; this is just for the log.
            Analytics.shared.track("purchase_restored", [
                "active": .string(info.entitlements[Subscriptions.entitlement]?.isActive == true ? "yes" : "no")
            ])
        }
        .task { await store.refresh() }
    }

    private var subscribed: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                PMWordmark(size: 20, showsPlus: true)
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)

            Spacer(minLength: 12)

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(PMTheme.plusOrange)
                .padding(.bottom, 18)

            Text("You have PhotoMesh Plus")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(PMTheme.ink)
            Text(store.status.detail)
                .font(.system(size: 14))
                .foregroundStyle(PMTheme.secondaryText)
                .padding(.top, 4)

            Spacer(minLength: 12)

            VStack(spacing: 14) {
                Button("Manage subscription") { presentingCustomerCenter = true }
                    .buttonStyle(PMBlackButtonStyle())
                Button("Done") { dismiss() }
                    .font(.system(size: 13))
                    .foregroundStyle(PMTheme.secondaryText)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .background(Color.white)
        .presentCustomerCenter(isPresented: $presentingCustomerCenter, onDismiss: {
            presentingCustomerCenter = false
        })
    }
}

#Preview {
    PlusSheet()
}
