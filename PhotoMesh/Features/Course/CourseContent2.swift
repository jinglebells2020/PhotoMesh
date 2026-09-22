import Foundation

// MARK: - Module 5: Capacitors and inductors

extension Course {
    static let storage = CourseModule(
        id: "m5", number: 5, title: "Capacitors and inductors", subtitle: "The two elements that store energy instead of burning it, and how they behave when nothing changes.", isFree: false,
        lessons: [
            Lesson(id: "m5l1", title: "Capacitors", minutes: 8, scenes: [
                scene("Charge on two plates",
                      "A capacitor is two conductors separated by an insulator. Push charge onto one plate and an equal charge is pulled from the other; the separated charge sets up a voltage. The charge is proportional to the voltage, and the constant is the capacitance C, in farads.",
                      .concept(.capacitorCharging),
                      formula: "q = C \\, v", text: "q = C · v"),
                scene("Current is the rate of change of voltage",
                      "Since i = dq/dt, the capacitor current is C times how fast its voltage changes. A steady voltage means zero current: at DC a capacitor is an open circuit. And the voltage cannot jump, because that would need infinite current.",
                      formula: "i = C \\frac{dv}{dt}", text: "i = C · dv/dt"),
                scene("Energy stored",
                      "Charging a capacitor takes work, and all of it comes back when it discharges. The energy sits in the electric field between the plates.",
                      formula: "w = \\tfrac{1}{2} C v^2", text: "w = ½ C v²"),
                scene("Series and parallel",
                      "Capacitors in parallel add (more plate area). Capacitors in series combine like resistors in parallel (reciprocals add), because the same charge sits on each.",
                      formula: "C_{par} = C_1 + C_2, \\quad \\frac{1}{C_{ser}} = \\frac{1}{C_1} + \\frac{1}{C_2}", text: "parallel: C1 + C2;  series: 1/C1 + 1/C2"),
                scene("At DC",
                      "In a steady DC circuit no capacitor current flows, so Photocircuits solves the circuit with every capacitor removed and then reads the capacitor voltage as the difference of its node voltages. Here the capacitor simply sits at the divider voltage.",
                      .transient(DemoCircuits.rc, traces: [TransientTrace(kind: .elementVoltage, id: "C1", label: "V(C1)"), TransientTrace(kind: .elementCurrent, id: "R1", label: "I(R1)")])),
            ], quiz: [
                question("A 100 µF capacitor holds 12 V. Its charge is…", ["1.2 mC", "12 mC", "120 µC", "8.3 µC"], answer: 0, "q = C·v = 100 × 10⁻⁶ × 12 = 1.2 × 10⁻³ C."),
                question("At steady DC a capacitor behaves as…", ["a short circuit", "an open circuit", "a resistor", "a voltage source"], answer: 1, "With dv/dt = 0 the current is zero: an open circuit that holds a voltage."),
                question("Which quantity of a capacitor cannot change instantly?", ["its current", "its voltage", "its capacitance", "its charge per plate area"], answer: 1, "An instant change of voltage would require infinite current."),
                question("Two 10 µF capacitors in series give…", ["20 µF", "10 µF", "5 µF", "2.5 µF"], answer: 2, "Series capacitors combine by reciprocals: 1/(1/10 + 1/10) = 5 µF."),
            ]),

            Lesson(id: "m5l2", title: "Inductors", minutes: 8, scenes: [
                scene("A coil resists change in current",
                      "Current through a coil sets up a magnetic field. Changing the current changes the field, and the changing field induces a voltage that opposes the change (Lenz's law). The voltage is L times how fast the current changes; L is the inductance, in henrys.",
                      .concept(.inductorRise),
                      formula: "v = L \\frac{di}{dt}", text: "v = L · di/dt"),
                scene("At DC, a wire",
                      "A steady current means zero voltage: at DC an inductor is a short circuit. Its current cannot jump, because that would need infinite voltage. This is the dual of the capacitor: swap voltage and current and the statements exchange.",
                      formula: "w = \\tfrac{1}{2} L i^2", text: "energy stored: w = ½ L i²"),
                scene("Series and parallel",
                      "Inductors combine exactly like resistors: series inductances add, parallel inductances combine by reciprocals.",
                      formula: "L_{ser} = L_1 + L_2, \\quad \\frac{1}{L_{par}} = \\frac{1}{L_1} + \\frac{1}{L_2}", text: "series: L1 + L2;  parallel: 1/L1 + 1/L2"),
                scene("Switching a coil on",
                      "Connect a coil to a source through a resistor. The current starts at zero (it cannot jump) and grows toward V/R; the coil's voltage starts at the full V and fades to nothing as the current settles.",
                      .transient(DemoCircuits.rl, traces: [TransientTrace(kind: .elementCurrent, id: "L1", label: "I(L1)"), TransientTrace(kind: .elementVoltage, id: "L1", label: "V(L1)")])),
            ], quiz: [
                question("At steady DC an inductor behaves as…", ["an open circuit", "a short circuit", "a capacitor", "a large resistor"], answer: 1, "With di/dt = 0 the voltage is zero: a plain wire that carries a current."),
                question("Which quantity of an inductor cannot change instantly?", ["its voltage", "its current", "its inductance", "its resistance"], answer: 1, "An instant change of current would require infinite voltage."),
                question("The energy stored in a 2 H inductor carrying 3 A is…", ["3 J", "6 J", "9 J", "18 J"], answer: 2, "w = ½ L i² = 0.5 × 2 × 9 = 9 J."),
                question("A 4 mH and a 12 mH inductor in parallel give…", ["16 mH", "8 mH", "3 mH", "48 mH"], answer: 2, "Like resistors in parallel: 4 × 12 / 16 = 3 mH."),
            ]),
        ]
    )
}

// MARK: - Module 6: First-order circuits

extension Course {
    static let firstOrder = CourseModule(
        id: "m6", number: 6, title: "First-order circuits", subtitle: "RC and RL circuits in time: exponential rise and decay, and the time constant that sets the pace.", isFree: false,
        lessons: [
            Lesson(id: "m6l1", title: "The source-free RC circuit", minutes: 8, scenes: [
                scene("A charged capacitor left to itself",
                      "Take a capacitor charged to V₀ and connect it across a resistor. Charge flows out through R, the voltage falls, so the current falls, so the voltage falls more slowly: an exponential decay.",
                      .concept(.capacitorDischarging),
                      formula: "v(t) = V_0 \\, e^{-t/\\tau}, \\quad \\tau = R C", text: "v(t) = V0 · e^(−t/τ) with τ = R·C"),
                scene("The time constant",
                      "τ = RC has units of seconds. After one τ the voltage is down to 37% of where it started; after five it is under 1%, and the circuit is considered settled. Larger R or larger C means a slower decay.",
                      .concept(.timeConstant)),
                scene("Where it comes from",
                      "KCL at the capacitor's top node: the capacitor current C dv/dt plus the resistor current v/R is zero. That first-order differential equation has the exponential as its only solution, with the initial voltage fixing the constant.",
                      formula: "C \\frac{dv}{dt} + \\frac{v}{R} = 0", text: "C · dv/dt + v/R = 0"),
                scene("Simulated",
                      "The capacitor charges through the switch, then the switch opens at 0.5 s and it drains through the 2 kΩ resistor with τ = 2 kΩ × 100 µF = 0.2 s. Watch the plates empty and the current dots slow down.",
                      .transient(DemoCircuits.rcSwitch, traces: [TransientTrace(kind: .elementVoltage, id: "C1", label: "V(C1)"), TransientTrace(kind: .elementCurrent, id: "R2", label: "I(R2)")], switchAt: 0.5)),
            ], quiz: [
                question("A 10 µF capacitor discharges through 100 kΩ. The time constant is…", ["1 ms", "0.1 s", "1 s", "10 s"], answer: 2, "τ = RC = 10⁵ × 10⁻⁵ = 1 s."),
                question("After one time constant a discharging capacitor's voltage is about…", ["63% of its start", "50% of its start", "37% of its start", "zero"], answer: 2, "e⁻¹ ≈ 0.368."),
                question("A source-free RC circuit is considered settled after about…", ["one τ", "two τ", "five τ", "it never settles"], answer: 2, "After 5τ less than 1% remains."),
                question("Doubling R in a discharging RC circuit…", ["halves the decay time", "doubles the time constant", "does not change the time constant", "doubles the initial voltage"], answer: 1, "τ = RC scales with R."),
            ]),

            Lesson(id: "m6l2", title: "The source-free RL circuit", minutes: 7, scenes: [
                scene("A coil with current, left to itself",
                      "An inductor carrying I₀ is switched onto a resistor. The current cannot stop at once; the coil drives it on through R while its magnetic energy drains into heat. The current decays exponentially with τ = L/R.",
                      formula: "i(t) = I_0 \\, e^{-t/\\tau}, \\quad \\tau = \\frac{L}{R}", text: "i(t) = I0 · e^(−t/τ) with τ = L/R"),
                scene("The dual of RC",
                      "Everything about the RC circuit carries over with voltage and current exchanged: the inductor current is the quantity that cannot jump, the time constant is L/R instead of RC, and a larger R now makes the decay faster.",
                      .concept(.timeConstant)),
                scene("Simulated",
                      "With the switch closed the coil settles to 0.2 A. At 0.1 s the switch opens; the current keeps flowing round the coil and the 50 Ω resistor and dies away with τ = 0.5 H / 50 Ω = 10 ms. Notice the inductor voltage flips sign the instant the switch opens.",
                      .transient(DemoCircuits.rlDecay, traces: [TransientTrace(kind: .elementCurrent, id: "L1", label: "I(L1)"), TransientTrace(kind: .elementVoltage, id: "L1", label: "V(L1)")], switchAt: 0.1)),
            ], quiz: [
                question("A 2 H coil discharges through 100 Ω. Its time constant is…", ["200 s", "50 ms", "20 ms", "2 ms"], answer: 2, "τ = L/R = 2/100 = 0.02 s."),
                question("In a source-free RL circuit, increasing R…", ["slows the decay", "speeds up the decay", "has no effect", "stops the current instantly"], answer: 1, "τ = L/R falls as R grows: the energy is burnt faster."),
                question("The moment a coil carrying current is disconnected from its source and left with only a resistor, its current…", ["drops to zero", "reverses", "continues at the same value and then decays", "doubles"], answer: 2, "Inductor current cannot change instantly; it decays from its initial value."),
            ]),

            Lesson(id: "m6l3", title: "Step response of an RC circuit", minutes: 8, scenes: [
                scene("Switching a source onto a capacitor",
                      "Connect a source V through R to an empty capacitor. At the first instant the capacitor looks like a short (its voltage is still zero), so the full current V/R flows. As charge builds up the voltage rises and the current falls; the voltage approaches V exponentially.",
                      .concept(.capacitorCharging),
                      formula: "v(t) = V + (V_0 - V) \\, e^{-t/\\tau}", text: "v(t) = V + (V0 − V) · e^(−t/τ)"),
                scene("Three numbers",
                      "Every first-order response is fixed by three numbers: the initial value (just after the switch), the final value (the DC steady state, capacitor open), and the time constant (R seen by the capacitor, times C). Write them down and the formula follows.",
                      formula: "\\tau = R_{th} C", text: "τ = Rth · C, with Rth the resistance the capacitor sees"),
                scene("Simulated",
                      "10 V through 1 kΩ into 100 µF: τ = 0.1 s. The current starts at 10 mA and dies away; the capacitor voltage reaches 6.3 V at 0.1 s and 9.9 V by 0.5 s.",
                      .transient(DemoCircuits.rc, traces: [TransientTrace(kind: .elementVoltage, id: "C1", label: "V(C1)"), TransientTrace(kind: .elementCurrent, id: "C1", label: "I(C1)")])),
            ], quiz: [
                question("Just after an empty capacitor is switched onto a source through R, the current is…", ["zero", "V/R", "infinite", "V·R"], answer: 1, "The capacitor voltage is still zero, so the whole source voltage sits across R."),
                question("A capacitor charging through 1 kΩ toward 10 V reaches about 6.3 V after…", ["one time constant", "two time constants", "half a time constant", "five time constants"], answer: 0, "1 − e⁻¹ ≈ 0.632."),
                question("The final value of the capacitor voltage in a step response is found by…", ["setting t = τ", "treating the capacitor as an open circuit and solving the DC circuit", "treating it as a short circuit", "doubling the initial value"], answer: 1, "At steady state no capacitor current flows."),
            ]),

            Lesson(id: "m6l4", title: "Step response of an RL circuit", minutes: 6, scenes: [
                scene("Switching a source onto a coil",
                      "At the first instant the coil carries no current (it cannot jump), so the full source voltage appears across it. The current then grows toward V/R while the coil voltage decays to zero.",
                      .concept(.inductorRise),
                      formula: "i(t) = \\frac{V}{R} \\left(1 - e^{-t/\\tau}\\right), \\quad \\tau = \\frac{L}{R}", text: "i(t) = (V/R)(1 − e^(−t/τ)), τ = L/R"),
                scene("Simulated",
                      "10 V through 100 Ω into 1 H: τ = 10 ms, final current 100 mA. The coil voltage starts at 10 V and fades as the current settles.",
                      .transient(DemoCircuits.rl, traces: [TransientTrace(kind: .elementCurrent, id: "L1", label: "I(L1)"), TransientTrace(kind: .elementVoltage, id: "L1", label: "V(L1)")])),
                scene("The general recipe",
                      "For any first-order circuit: find the initial value x(0⁺), the final value x(∞), and τ. Then x(t) = x(∞) + [x(0⁺) − x(∞)] e^(−t/τ). The lab's Simulate mode shows the full curve for any circuit you draw.",
                      formula: "x(t) = x(\\infty) + \\left[x(0^+) - x(\\infty)\\right] e^{-t/\\tau}", text: "x(t) = x(∞) + [x(0⁺) − x(∞)] · e^(−t/τ)"),
            ], quiz: [
                question("Just after a coil is switched onto a source through R, the coil voltage is…", ["zero", "the full source voltage", "half the source voltage", "negative"], answer: 1, "No current yet means no drop across R: all of V is across L."),
                question("The final current in an RL step response is…", ["zero", "V/R", "V·L", "V/L"], answer: 1, "At DC the coil is a wire and the resistor sets the current."),
                question("A 50 mH coil and 25 Ω give a time constant of…", ["2 ms", "1.25 s", "0.5 ms", "20 ms"], answer: 0, "τ = L/R = 0.05/25 = 0.002 s."),
            ]),
        ]
    )
}

// MARK: - Module 7: Second-order circuits

extension Course {
    static let secondOrder = CourseModule(
        id: "m7", number: 7, title: "Second-order circuits", subtitle: "RLC circuits: energy sloshing between coil and capacitor, damping, and the three kinds of response.", isFree: false,
        lessons: [
            Lesson(id: "m7l1", title: "The series RLC circuit", minutes: 9, scenes: [
                scene("Two energy stores",
                      "With both a capacitor and an inductor, energy can swing back and forth: the capacitor's electric field empties into the coil's magnetic field and back again, while the resistor bleeds a little away on each pass. The result can oscillate.",
                      .concept(.rlcRinging)),
                scene("Two parameters",
                      "KVL around the loop gives a second-order differential equation. Two numbers describe it: the neper frequency α = R/2L, which says how fast energy is lost, and the resonant frequency ω₀ = 1/√(LC), which says how fast it would swing with no loss.",
                      formula: "\\alpha = \\frac{R}{2L}, \\quad \\omega_0 = \\frac{1}{\\sqrt{LC}}", text: "α = R/(2L), ω0 = 1/√(LC)"),
                scene("Three kinds of response",
                      "If α > ω₀ the circuit is overdamped: it creeps to its final value without overshoot. If α = ω₀ it is critically damped: fastest without overshoot. If α < ω₀ it is underdamped: it rings at ω_d = √(ω₀² − α²), each swing smaller by e^(−αt).",
                      formula: "\\omega_d = \\sqrt{\\omega_0^2 - \\alpha^2}", text: "ωd = √(ω0² − α²)"),
                scene("Underdamped, simulated",
                      "10 Ω, 1 mH, 10 µF: α = 5000 s⁻¹, ω₀ = 10 000 s⁻¹, so it rings at 8660 rad/s and overshoots to about 11.6 V before settling at 10 V.",
                      .transient(DemoCircuits.rlc, traces: [TransientTrace(kind: .elementVoltage, id: "C1", label: "V(C1)"), TransientTrace(kind: .elementCurrent, id: "L1", label: "I(L1)")])),
                scene("Overdamped, simulated",
                      "Raise R to 50 Ω: α = 25 000 s⁻¹ is now larger than ω₀ and the capacitor voltage rises without any overshoot. Same L and C, different damping.",
                      .transient(DemoCircuits.rlcOverdamped, traces: [TransientTrace(kind: .elementVoltage, id: "C1", label: "V(C1)"), TransientTrace(kind: .elementCurrent, id: "L1", label: "I(L1)")])),
            ], quiz: [
                question("A series RLC has R = 20 Ω, L = 2 mH. Its neper frequency α is…", ["5000 s⁻¹", "10 000 s⁻¹", "40 s⁻¹", "0.01 s⁻¹"], answer: 0, "α = R/2L = 20/(0.004) = 5000 s⁻¹."),
                question("With L = 1 mH and C = 1 µF, ω₀ is…", ["1000 rad/s", "31 623 rad/s", "1 000 000 rad/s", "10 rad/s"], answer: 1, "ω₀ = 1/√(10⁻³ × 10⁻⁶) = 1/√10⁻⁹ ≈ 31 623 rad/s."),
                question("An underdamped response…", ["never reaches its final value", "overshoots and oscillates with decreasing swings", "rises fastest without overshoot", "has α > ω₀"], answer: 1, "α < ω₀: the energy swings between L and C while the resistor damps it."),
                question("Increasing R in a series RLC circuit…", ["increases the damping", "increases ω₀", "makes it oscillate more", "changes nothing"], answer: 0, "α = R/2L grows with R; enough R makes the circuit overdamped."),
            ]),

            Lesson(id: "m7l2", title: "Parallel RLC and the general picture", minutes: 5, scenes: [
                scene("The parallel case",
                      "A resistor, coil and capacitor across the same two nodes obey a dual equation: KCL instead of KVL. The resonant frequency is the same ω₀ = 1/√(LC), but now α = 1/(2RC): a larger parallel R means less damping, the opposite of the series case.",
                      formula: "\\alpha = \\frac{1}{2RC}, \\quad \\omega_0 = \\frac{1}{\\sqrt{LC}}", text: "parallel RLC: α = 1/(2RC), ω0 = 1/√(LC)"),
                scene("Reading any second-order response",
                      "Whatever the topology: find α and ω₀, compare them to know the shape, take the initial values (capacitor voltage and inductor current cannot jump) and the final DC values, and fit the two constants. The Simulate mode will draw it for you first.",
                      .concept(.rlcRinging)),
            ], quiz: [
                question("In a parallel RLC circuit, increasing R…", ["increases damping", "decreases damping", "changes ω₀", "stops oscillation"], answer: 1, "α = 1/(2RC) falls as R grows: the parallel resistor drains less current."),
                question("The resonant frequency ω₀ depends on…", ["R only", "L and C only", "R, L and C", "the source voltage"], answer: 1, "ω₀ = 1/√(LC) in both series and parallel circuits."),
            ]),
        ]
    )
}

// MARK: - Module 8: AC steady state

extension Course {
    static let alternating = CourseModule(
        id: "m8", number: 8, title: "Alternating current", subtitle: "Sinusoids, phasors and impedance: how the DC methods carry over to circuits driven by sine waves.", isFree: false,
        lessons: [
            Lesson(id: "m8l1", title: "Sinusoids", minutes: 6, scenes: [
                scene("Describing a sine wave",
                      "Mains power and radio signals are sinusoids. Three numbers describe one: the amplitude Vm (the peak), the angular frequency ω = 2πf (how fast it turns, in radians per second), and the phase φ (where it is at t = 0).",
                      .concept(.sineWave),
                      formula: "v(t) = V_m \\sin(\\omega t + \\phi)", text: "v(t) = Vm · sin(ωt + φ)"),
                scene("Period and frequency",
                      "The period T is the time of one cycle, and f = 1/T is the number of cycles per second, in hertz. Mains is 50 or 60 Hz, so ω ≈ 314 or 377 rad/s.",
                      formula: "T = \\frac{2\\pi}{\\omega}, \\quad f = \\frac{1}{T}", text: "T = 2π/ω, f = 1/T"),
                scene("RMS",
                      "A sinusoid delivers the same average power to a resistor as a DC voltage of Vm/√2. That effective value is called the RMS value; 230 V mains has a peak of about 325 V.",
                      formula: "V_{rms} = \\frac{V_m}{\\sqrt{2}}", text: "Vrms = Vm/√2"),
            ], quiz: [
                question("A sinusoid has ω = 314 rad/s. Its frequency is about…", ["314 Hz", "50 Hz", "100 Hz", "2 Hz"], answer: 1, "f = ω/2π ≈ 50 Hz."),
                question("The RMS value of a 10 V peak sinusoid is…", ["10 V", "7.07 V", "5 V", "14.1 V"], answer: 1, "Vrms = Vm/√2 ≈ 7.07 V."),
                question("The phase φ tells…", ["the peak value", "how fast the wave turns", "where in its cycle the wave is at t = 0", "the period"], answer: 2, "Phase shifts the wave in time without changing its shape."),
            ]),

            Lesson(id: "m8l2", title: "Phasors", minutes: 7, scenes: [
                scene("A sine wave is a turning arrow",
                      "A vector of length Vm turning at ω rad/s traces a sinusoid when you watch its height. In a circuit driven at one frequency every voltage and current turns at the same ω, so all that distinguishes them is their length (amplitude) and angle (phase). That frozen arrow is the phasor.",
                      .concept(.phasor),
                      formula: "v(t) = V_m \\cos(\\omega t + \\phi) \\;\\leftrightarrow\\; \\mathbf{V} = V_m e^{j\\phi}", text: "v(t) = Vm cos(ωt + φ) corresponds to the phasor V = Vm∠φ"),
                scene("Why it helps",
                      "Differentiation in time becomes multiplication by jω, so the differential equations of L and C become algebra. KCL and KVL hold for phasors, and every DC method (nodal, mesh, Thévenin) works unchanged with complex numbers.",
                      formula: "\\frac{d}{dt} \\;\\leftrightarrow\\; j\\omega", text: "d/dt becomes multiplication by jω"),
                scene("Leading and lagging",
                      "When two phasors are at different angles, the one further round the circle is said to lead. In an inductor the current lags the voltage by 90°; in a capacitor it leads by 90°; in a resistor they are in phase.",
                      .concept(.phasor)),
            ], quiz: [
                question("Two sinusoids at the same frequency differ by 90°. Their phasors…", ["have the same angle", "are perpendicular", "have the same length", "cannot be compared"], answer: 1, "Phase difference is the angle between the phasors."),
                question("In an inductor the current…", ["leads the voltage by 90°", "lags the voltage by 90°", "is in phase with the voltage", "is zero"], answer: 1, "v = L di/dt: the voltage peaks when the current changes fastest, a quarter cycle before the current peaks."),
                question("Phasors can be used…", ["for any waveform", "for sinusoids of a single frequency in steady state", "only for DC", "only for resistors"], answer: 1, "The method assumes one frequency and that transients have died away."),
            ]),

            Lesson(id: "m8l3", title: "Impedance", minutes: 8, scenes: [
                scene("Ohm's law for phasors",
                      "For each element the ratio of voltage phasor to current phasor is its impedance Z, a complex number in ohms. A resistor's is R. An inductor's is jωL: it grows with frequency. A capacitor's is 1/(jωC): it shrinks with frequency.",
                      formula: "\\mathbf{Z}_R = R, \\quad \\mathbf{Z}_L = j\\omega L, \\quad \\mathbf{Z}_C = \\frac{1}{j\\omega C}", text: "Z_R = R, Z_L = jωL, Z_C = 1/(jωC)"),
                scene("Resistance and reactance",
                      "Z = R + jX. The real part is resistance and dissipates power; the imaginary part is reactance and only stores and returns it. The magnitude |Z| relates the amplitudes, the angle θ is the phase between voltage and current.",
                      .concept(.impedanceTriangle),
                      formula: "|\\mathbf{Z}| = \\sqrt{R^2 + X^2}, \\quad \\theta = \\arctan\\frac{X}{R}", text: "|Z| = √(R² + X²), θ = arctan(X/R)"),
                scene("Combining impedances",
                      "Impedances in series add; in parallel their reciprocals (admittances) add, exactly like resistors. Voltage and current division, Thévenin and nodal analysis all carry over with Z in place of R.",
                      formula: "\\mathbf{Z}_{ser} = \\mathbf{Z}_1 + \\mathbf{Z}_2, \\quad \\frac{1}{\\mathbf{Z}_{par}} = \\frac{1}{\\mathbf{Z}_1} + \\frac{1}{\\mathbf{Z}_2}", text: "series: Z1 + Z2;  parallel: 1/Z1 + 1/Z2"),
                scene("Resonance",
                      "In a series RLC the reactances of L and C cancel when ωL = 1/(ωC), that is at ω₀ = 1/√(LC): the impedance is then just R, the smallest it can be, and the current is largest. This is how a radio picks one station.",
                      formula: "\\omega_0 L = \\frac{1}{\\omega_0 C}", text: "ω0·L = 1/(ω0·C) at resonance"),
            ], quiz: [
                question("The impedance of a 10 mH inductor at ω = 1000 rad/s is…", ["10 Ω", "j10 Ω", "−j10 Ω", "100 Ω"], answer: 1, "Z_L = jωL = j × 1000 × 0.01 = j10 Ω."),
                question("As frequency rises, a capacitor's impedance…", ["rises", "falls", "stays the same", "becomes real"], answer: 1, "|Z_C| = 1/(ωC) shrinks with ω: capacitors pass high frequencies more easily."),
                question("Z = 3 + j4 Ω has magnitude…", ["7 Ω", "5 Ω", "1 Ω", "12 Ω"], answer: 1, "√(3² + 4²) = 5 Ω, with θ = 53°."),
                question("At resonance a series RLC circuit's impedance is…", ["zero", "R only", "jωL only", "infinite"], answer: 1, "The inductive and capacitive reactances cancel, leaving the resistance."),
            ]),

            Lesson(id: "m8l4", title: "AC power", minutes: 6, scenes: [
                scene("Average power",
                      "With a phase angle θ between voltage and current, only the in-phase part of the current does work. The average (real) power is Vrms·Irms·cos θ; cos θ is the power factor. A pure inductor or capacitor has θ = 90° and takes no average power at all.",
                      .concept(.phasor),
                      formula: "P = V_{rms} I_{rms} \\cos\\theta", text: "P = Vrms · Irms · cos θ"),
                scene("Apparent and reactive power",
                      "Vrms·Irms is the apparent power, in volt-amperes, what the wires must carry. Its component at right angles, Q = Vrms·Irms·sin θ, is the reactive power that sloshes back and forth without doing work. Utilities dislike a low power factor because it means large currents for little real power.",
                      .concept(.impedanceTriangle),
                      formula: "S = V_{rms} I_{rms}, \\quad Q = S \\sin\\theta, \\quad P = S\\cos\\theta", text: "S = Vrms·Irms; Q = S·sin θ; P = S·cos θ"),
                scene("Where to go next",
                      "You now have the whole first course: the laws, the two methods, the theorems, energy storage, transients and the phasor view of AC. Every one of these tools is inside Photocircuits: scan or draw a circuit, follow the steps, tweak it in the lab, and watch it in time.",
                      .concept(.chargeFlow)),
            ], quiz: [
                question("A load draws 2 A rms at 230 V rms with a power factor of 0.8. Its real power is…", ["460 W", "368 W", "276 W", "184 W"], answer: 1, "P = V·I·cos θ = 230 × 2 × 0.8 = 368 W."),
                question("A pure capacitor's average power is…", ["V·I", "zero", "V·I/2", "negative"], answer: 1, "With θ = 90°, cos θ = 0: it stores and returns energy but dissipates none."),
                question("Apparent power is measured in…", ["watts", "volt-amperes", "vars", "joules"], answer: 1, "S = Vrms·Irms in VA; real power is in W and reactive power in var."),
            ]),
        ]
    )
}
