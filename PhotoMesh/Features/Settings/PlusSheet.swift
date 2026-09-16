import SwiftUI
import RevenueCat
import RevenueCatUI

/// PhotoMesh Plus.
///
/// Subscribers see what they have. Everyone else gets the RevenueCat paywall, so plans, prices
/// and copy come from the dashboard. If there is no current offering yet, the sheet falls back to
/// a plain list built from `availablePackages` and says what is missing, rather than showing an
/// empty screen — empty offerings are nearly always a dashboard or App Store Connect setup issue.
struct PlusSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var presentingCustomerCenter = false
    @State private var busyPackage: Package?

    private var store: Subscriptions { Subscriptions.shared }

    var body: some View {
        Group {
            if store.isPro {
                subscribed
            } else if store.offerings?.current != nil {
                // Handles its own loading, purchase and restore flows.
                PaywallView(displayCloseButton: true)
            } else {
                fallback
            }
        }
        .onPurchaseCompleted { _ in
            Haptics.notify(.success)
            Analytics.shared.track("purchase_completed")
            dismiss()
        }
        .onRestoreCompleted { info in
            Analytics.shared.track("purchase_restored", [
                "active": .string(info.entitlements[Subscriptions.entitlement]?.isActive == true ? "yes" : "no")
            ])
        }
        .task { await store.refresh() }
    }

    // MARK: Already subscribed

    private var subscribed: some View {
        VStack(spacing: 0) {
            header

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

    // MARK: No dashboard paywall yet

    private var fallback: some View {
        VStack(spacing: 0) {
            header

            VStack(alignment: .leading, spacing: 18) {
                FeatureRow(title: "Unlimited scans", subtitle: "no hourly or daily limit on camera solves")
                FeatureRow(title: "Every solving method", subtitle: "nodal, mesh and series/parallel, step by step")
            }
            .padding(.horizontal, 32)
            .padding(.top, 26)

            Spacer(minLength: 16)

            if store.availablePackages.isEmpty {
                VStack(spacing: 10) {
                    ProgressView()
                    if let problem = store.offeringProblem {
                        Text(problem)
                            .font(.system(size: 13))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(PMTheme.secondaryText)
                            .padding(.horizontal, 32)
                    }
                }
                .padding(.bottom, 20)
            } else {
                VStack(spacing: 10) {
                    // Prices, durations and intro offers all come from StoreKit; nothing is hardcoded.
                    ForEach(store.availablePackages, id: \.identifier) { package in
                        PackageButton(package: package, busy: busyPackage?.identifier == package.identifier) {
                            buy(package)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

            if let error = store.lastError {
                Text(error)
                    .font(.system(size: 12))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(PMTheme.whyOrange)
                    .padding(.horizontal, 24)
                    .padding(.top, 10)
            }

            Button("Not now") { dismiss() }
                .font(.system(size: 13))
                .foregroundStyle(PMTheme.secondaryText)
                .padding(.top, 14)
                .padding(.bottom, 20)
        }
        .background(Color.white)
    }

    private var header: some View {
        HStack {
            Spacer()
            PMWordmark(size: 20, showsPlus: true)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
    }

    private func buy(_ package: Package) {
        busyPackage = package
        Task {
            let bought = await store.purchase(package)
            busyPackage = nil
            if bought {
                Haptics.notify(.success)
                Analytics.shared.track("purchase_completed")
                dismiss()
            }
        }
    }
}

/// One plan: duration, price, and an intro-offer hint when StoreKit reports one.
private struct PackageButton: View {
    let package: Package
    let busy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(durationName)
                        .font(.system(size: 16, weight: .semibold))
                    if package.storeProduct.introductoryDiscount != nil {
                        Text("Intro offer available")
                            .font(.system(size: 12))
                            .foregroundStyle(PMTheme.plusOrange)
                    }
                }
                Spacer()
                if busy {
                    ProgressView()
                } else {
                    Text(package.storeProduct.localizedPriceString)
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 58)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14).stroke(PMTheme.accent, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .foregroundStyle(PMTheme.ink)
        .disabled(busy)
    }

    /// Standard package types carry the duration; anything custom falls back to the store title.
    private var durationName: String {
        switch package.packageType {
        case .monthly: return "Monthly"
        case .twoMonth: return "2 months"
        case .threeMonth: return "3 months"
        case .sixMonth: return "6 months"
        case .annual: return "Yearly"
        case .weekly: return "Weekly"
        case .lifetime: return "Lifetime"
        default: return package.storeProduct.localizedTitle
        }
    }
}

private struct FeatureRow: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "checkmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(PMTheme.plusOrange)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(PMTheme.ink)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(PMTheme.secondaryText)
            }
        }
    }
}

#Preview {
    PlusSheet()
}
