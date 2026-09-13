import SwiftUI

/// Dotted square used as an operand placeholder inside composite key glyphs.
struct PlaceholderBox: View {
    var size: CGFloat = 9

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [1.6, 1.6]))
            .foregroundStyle(PMTheme.ink.opacity(0.75))
            .frame(width: size, height: size)
    }
}

/// Renders a `KeyLabel` in the key cell (or larger inside the press bubble).
struct KeyLabelView: View {
    let label: KeyLabel
    var scale: CGFloat = 1

    private var mainFont: Font { .system(size: 22 * scale, weight: .regular) }
    private var smallFont: Font { .system(size: 13 * scale, weight: .regular) }
    private var italicSmall: Font { .system(size: 13 * scale, weight: .regular, design: .serif).italic() }

    var body: some View {
        Group {
            switch label {
            case .text(let s):
                Text(s)
                    .font(s.count > 3 ? .system(size: 15 * scale) : mainFont)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            case .symbol(let name):
                Image(systemName: name).font(.system(size: 19 * scale))
            case .parens:
                HStack(spacing: 1) { Text("(").font(mainFont); PlaceholderBox(); Text(")").font(mainFont) }
            case .brackets:
                HStack(spacing: 1) { Text("[").font(mainFont); PlaceholderBox(); Text("]").font(mainFont) }
            case .fraction:
                VStack(spacing: 2.5) { PlaceholderBox(); bar(width: 14); PlaceholderBox() }
            case .sqrt:
                radical(index: nil)
            case .cubeRoot:
                radical(index: "3")
            case .nthRoot:
                HStack(alignment: .top, spacing: -2) { PlaceholderBox(size: 6).padding(.top, 2); radical(index: nil) }
            case .square:
                HStack(alignment: .top, spacing: 1) { PlaceholderBox(size: 11).padding(.top, 6); Text("2").font(.system(size: 11 * scale)) }
            case .cube:
                HStack(alignment: .top, spacing: 1) { PlaceholderBox(size: 11).padding(.top, 6); Text("3").font(.system(size: 11 * scale)) }
            case .power:
                HStack(alignment: .top, spacing: 1) { PlaceholderBox(size: 11).padding(.top, 6); PlaceholderBox(size: 7) }
            case .reciprocal:
                HStack(alignment: .top, spacing: 1) { PlaceholderBox(size: 11).padding(.top, 6); Text("-1").font(.system(size: 10 * scale)) }
            case .abs:
                HStack(spacing: 3) { Text("|").font(mainFont); PlaceholderBox(); Text("|").font(mainFont) }
            case .logBase:
                HStack(alignment: .bottom, spacing: 1) { Text("log").font(.system(size: 15 * scale)); PlaceholderBox(size: 6); PlaceholderBox(size: 9).padding(.leading, 2).padding(.bottom, 3) }
            case .exp:
                HStack(alignment: .top, spacing: 1) { Text("e").font(mainFont); PlaceholderBox(size: 7).padding(.top, 2) }
            case .floor:
                HStack(spacing: 2) { Text("⌊").font(mainFont); PlaceholderBox(); Text("⌋").font(mainFont) }
            case .ceil:
                HStack(spacing: 2) { Text("⌈").font(mainFont); PlaceholderBox(); Text("⌉").font(mainFont) }
            case .derivative:
                HStack(spacing: 3) { stackedFraction(top: "d", bottom: "dx"); PlaceholderBox() }
            case .derivativeGeneric:
                HStack(spacing: 3) {
                    VStack(spacing: 1) { Text("d").font(italicSmall); bar(width: 16); HStack(spacing: 0) { Text("d").font(italicSmall); PlaceholderBox(size: 7) } }
                    PlaceholderBox()
                }
            case .secondDerivative:
                HStack(spacing: 3) { stackedFraction(top: "d²", bottom: "dx²"); PlaceholderBox() }
            case .integral:
                HStack(spacing: 2) { Text("∫").font(.system(size: 24 * scale)); PlaceholderBox(); Text("dx").font(italicSmall) }
            case .definiteIntegral:
                HStack(spacing: 2) {
                    VStack(spacing: 0) { PlaceholderBox(size: 5); Text("∫").font(.system(size: 20 * scale)); PlaceholderBox(size: 5) }
                    PlaceholderBox()
                    Text("d").font(italicSmall)
                    PlaceholderBox(size: 6)
                }
            case .doubleIntegral:
                HStack(spacing: 2) { Text("∬").font(.system(size: 24 * scale)); PlaceholderBox() }
            case .limit:
                limitGlyph(suffix: nil)
            case .limitRight:
                limitGlyph(suffix: "+")
            case .limitLeft:
                limitGlyph(suffix: "−")
            case .sum:
                VStack(spacing: 0) {
                    PlaceholderBox(size: 5)
                    Text("Σ").font(.system(size: 18 * scale))
                    HStack(spacing: 1) { PlaceholderBox(size: 5); Text("=").font(.system(size: 7 * scale)); PlaceholderBox(size: 5) }
                }
            case .product:
                VStack(spacing: 0) {
                    PlaceholderBox(size: 5)
                    Text("∏").font(.system(size: 18 * scale))
                    HStack(spacing: 1) { PlaceholderBox(size: 5); Text("=").font(.system(size: 7 * scale)); PlaceholderBox(size: 5) }
                }
            case .subscriptN:
                HStack(alignment: .bottom, spacing: 1) { Text("a").font(mainFont); Text("n").font(.system(size: 12 * scale)).padding(.bottom, 2) }
            case .dyDx:
                stackedFraction(top: "dy", bottom: "dx")
            case .empty:
                EmptyView()
            }
        }
        .foregroundStyle(PMTheme.ink)
    }

    private func bar(width: CGFloat) -> some View {
        Rectangle().fill(PMTheme.ink).frame(width: width, height: 1.2)
    }

    private func stackedFraction(top: String, bottom: String) -> some View {
        VStack(spacing: 1) {
            Text(top).font(italicSmall)
            bar(width: 18)
            Text(bottom).font(italicSmall)
        }
    }

    private func radical(index: String?) -> some View {
        HStack(alignment: .top, spacing: -1) {
            if let index {
                Text(index).font(.system(size: 9 * scale)).padding(.top, 2)
            }
            Text("√").font(.system(size: 22 * scale))
            VStack(spacing: 1) {
                Rectangle().fill(PMTheme.ink).frame(width: 12, height: 1.2)
                PlaceholderBox(size: 9)
            }
            .padding(.top, 3)
        }
    }

    private func limitGlyph(suffix: String?) -> some View {
        VStack(spacing: 0) {
            Text("lim").font(.system(size: 14 * scale))
            HStack(spacing: 1) {
                PlaceholderBox(size: 6)
                Text("→").font(.system(size: 9 * scale))
                PlaceholderBox(size: 6)
                if let suffix {
                    Text(suffix).font(.system(size: 8 * scale)).baselineOffset(4)
                }
            }
        }
    }
}
