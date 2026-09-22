import SwiftUI

/// "How to use" – dark sheet with cards that play real demonstrations of the app.
struct HelpCenterSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            PMTheme.darkSheet.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("How to use")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.top, 58)

                    HelpCard(
                        title: "Scan a circuit",
                        caption: "Fit the whole circuit inside the white corners. Photocircuits reads the parts and redraws a clean schematic for you to check before it solves."
                    ) {
                        DemoPlayer(duration: 6.5) { phase, playing in ScanDemo(phase: phase, playing: playing) }
                    }

                    HelpCard(
                        title: "Draw a circuit",
                        caption: "Lines are wires, a zigzag is a resistor, humps are a coil, a circle is a source. Draw a part on a wire and it slots in; tap it to set a value or change its type."
                    ) {
                        DemoPlayer(duration: 7.5) { phase, playing in DrawDemo(phase: phase, playing: playing) }
                    }

                    HelpCard(
                        title: "Solving steps",
                        caption: "Each step shows its equation and lights up the part of the circuit it talks about. Once the currents are known, watch them flow: faster where the current is larger, fading where energy is spent."
                    ) {
                        DemoPlayer(duration: 6) { phase, playing in StepsDemo(phase: phase, playing: playing) }
                    }

                    HelpCard(
                        title: "Advanced calculator",
                        caption: "Hold any key with a green dot to reach its extra functions."
                    ) {
                        DemoPlayer(duration: 4.2) { phase, playing in CalculatorDemo(phase: phase, playing: playing) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }

            PMCloseButton { dismiss() }
                .padding(.top, 14)
                .padding(.trailing, 16)
        }
    }
}

private struct HelpCard<Illustration: View>: View {
    let title: String
    let caption: String
    @ViewBuilder let illustration: () -> Illustration

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(PMTheme.ink)
                .padding(.horizontal, 20)
                .padding(.vertical, 18)

            illustration()
                .aspectRatio(1, contentMode: .fit)
                .clipped()

            Text(caption)
                .font(.system(size: 17))
                .foregroundStyle(PMTheme.ink)
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
        }
        .background(RoundedRectangle(cornerRadius: PMTheme.cardRadius, style: .continuous).fill(Color.white))
    }
}

#Preview {
    HelpCenterSheet()
}
