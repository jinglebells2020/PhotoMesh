import Foundation
import Observation
import SwiftUI

/// What PhotoMesh Plus unlocks. Each case is one gate in the app; the paywall lists them in
/// this order, so the copy here is the single source of truth for what a subscriber gets.
enum PlusFeature: String, CaseIterable, Identifiable {
    case unlimitedScans
    case lab
    case course
    case exports

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unlimitedScans: return "Unlimited scans"
        case .lab: return "Circuit lab: tweak and simulate"
        case .course: return "The full circuits course"
        case .exports: return "Export to LTspice and PDF"
        }
    }

    var detail: String {
        switch self {
        case .unlimitedScans:
            return "No hourly or daily cap on camera solves. Drawn circuits are always free."
        case .lab:
            return "Drag any value and watch every current and voltage follow. Flip switches, then play the circuit in time: capacitors charging, coils resisting, curves you can scrub."
        case .course:
            return "The whole first-year circuits course as animated lessons with quizzes, from charge and Ohm's law to nodal and mesh analysis, Thévenin, RC and RL transients and phasors. The first module is free."
        case .exports:
            return "Save any solved circuit as an LTspice schematic and netlist, or share the complete step-by-step solution as a PDF."
        }
    }

    var systemImage: String {
        switch self {
        case .unlimitedScans: return "camera.viewfinder"
        case .lab: return "slider.horizontal.below.square.and.square.filled"
        case .course: return "graduationcap"
        case .exports: return "square.and.arrow.up"
        }
    }

    /// One line for a locked spot in the app ("Unlock the circuit lab").
    var unlockPrompt: String {
        switch self {
        case .unlimitedScans: return "Unlock unlimited scans"
        case .lab: return "Unlock the circuit lab"
        case .course: return "Unlock the full course"
        case .exports: return "Unlock exports"
        }
    }
}

/// Answers "may this user use that feature right now": the subscription, plus a developer
/// override so testers can walk through the paid paths without a purchase.
@MainActor
enum PlusAccess {
    static let pretendKey = "developer.pretendPlus"

    /// Developer options: behave as a subscriber on this device.
    static var pretendPlus: Bool {
        get { DeveloperOptions.enabled && UserDefaults.standard.bool(forKey: pretendKey) }
        set { UserDefaults.standard.set(newValue, forKey: pretendKey) }
    }

    static var hasPlus: Bool { Subscriptions.shared.isPro || pretendPlus }

    static func allows(_ feature: PlusFeature) -> Bool { hasPlus }

    /// Records that a locked feature was tapped, so the paywall's usefulness can be judged.
    static func notedLockedTap(_ feature: PlusFeature) {
        Analytics.shared.track("plus_gate", ["feature": .string(feature.rawValue)])
    }
}

/// Non-isolated mirror for code running off the main actor (the solver pipeline).
enum PlusAccessCached {
    nonisolated static var hasPlus: Bool {
        Subscriptions.isProCached || (DeveloperOptions.enabled && UserDefaults.standard.bool(forKey: PlusAccess.pretendKey))
    }
}

// MARK: - Locked-feature card

/// The card shown in place of a Plus feature: what it does, one tap to the paywall.
struct PlusLockCard: View {
    let feature: PlusFeature
    var compact = false
    @State private var presentingPaywall = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            HStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(PMTheme.plusOrange)
                Text("Photocircuits Plus")
                    .font(.system(size: 12, weight: .semibold))
                    .kerning(0.6)
                    .foregroundStyle(PMTheme.plusOrange)
            }
            Text(feature.title)
                .font(.system(size: compact ? 16 : 19, weight: .bold))
                .foregroundStyle(PMTheme.ink)
            Text(feature.detail)
                .font(.system(size: compact ? 13 : 14))
                .foregroundStyle(PMTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                PlusAccess.notedLockedTap(feature)
                presentingPaywall = true
            } label: {
                HStack(spacing: 8) {
                    Text(feature.unlockPrompt)
                    Image(systemName: "arrow.right").font(.system(size: 14, weight: .semibold))
                }
            }
            .buttonStyle(PMBlackButtonStyle())
            .padding(.top, 4)
        }
        .padding(compact ? 14 : 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: PMTheme.cardRadius, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.08), radius: 10, y: 3)
        )
        .sheet(isPresented: $presentingPaywall) {
            PlusSheet()
        }
    }
}

/// Small orange "PLUS" tag for menu rows and headers.
struct PlusTag: View {
    var body: some View {
        Text("PLUS")
            .font(.system(size: 9, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule().fill(PMTheme.plusOrange))
    }
}
