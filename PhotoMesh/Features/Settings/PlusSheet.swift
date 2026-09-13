import SwiftUI

/// Upsell screen. Purchases are not wired up yet – this is the layout only.
struct PlusSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                PMWordmark(size: 20, showsPlus: true)
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)

            Spacer(minLength: 12)

            PlusIllustration()
                .frame(height: 220)
                .padding(.horizontal, 24)

            VStack(alignment: .leading, spacing: 22) {
                FeatureRow(title: "Step-by-step mesh & nodal analysis", subtitle: "see every KVL and KCL equation, not just the answer")
                FeatureRow(title: "Unlimited scans", subtitle: "no daily limit on camera solves")
                FeatureRow(title: "Export to SPICE", subtitle: "send the recognized netlist straight to your simulator")
            }
            .padding(.horizontal, 32)
            .padding(.top, 34)

            Spacer(minLength: 12)

            VStack(spacing: 14) {
                Button("Unlock Plus") {
                    Haptics.notify(.warning)
                }
                .buttonStyle(PMBlackButtonStyle())

                Button("Not now") { dismiss() }
                    .font(.system(size: 13))
                    .foregroundStyle(PMTheme.secondaryText)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .background(Color.white)
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

private struct PlusIllustration: View {
    var body: some View {
        ZStack {
            // open "book" pages
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(white: 0.96))
                .frame(width: 210, height: 150)
                .rotationEffect(.degrees(-6))
                .offset(x: -30, y: 16)
                .shadow(color: .black.opacity(0.12), radius: 10, y: 6)
            RoundedRectangle(cornerRadius: 10)
                .fill(PMTheme.accent)
                .frame(width: 22, height: 150)
                .rotationEffect(.degrees(-6))
                .offset(x: -132, y: 22)

            // phone with solution card
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color.black)
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white).padding(6)
                VStack(alignment: .leading, spacing: 6) {
                    Text("SOLVING STEPS").font(.system(size: 6, weight: .semibold)).foregroundStyle(PMTheme.secondaryText)
                    Text("Find the loop current").font(.system(size: 9, weight: .bold))
                    MeshLoopGlyph()
                        .stroke(PMTheme.ink, lineWidth: 1.4)
                        .frame(width: 60, height: 34)
                        .padding(.vertical, 4)
                    HStack(spacing: 0) {
                        Rectangle().fill(PMTheme.accent).frame(width: 2)
                        Text("I = 37.5 mA").font(.system(size: 10, weight: .bold)).padding(.leading, 6)
                    }
                    Spacer()
                    HStack { Spacer(); Circle().fill(PMTheme.accent).frame(width: 16, height: 16); Spacer() }
                }
                .padding(14)
            }
            .frame(width: 110, height: 200)
            .rotationEffect(.degrees(8))
            .offset(x: 60, y: -4)
            .shadow(color: .black.opacity(0.2), radius: 12, y: 8)
        }
    }
}

#Preview {
    PlusSheet()
}
