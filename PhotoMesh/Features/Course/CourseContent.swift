import Foundation

/// The course. It opens with the water-in-pipes picture (CourseWater.swift) and then follows the
/// order of the classic first-year texts (Alexander & Sadiku, Nilsson & Riedel, Hayt & Kemmerly):
/// basic concepts, the two laws, the two methods, the theorems, the energy-storing elements,
/// transients, and the first look at AC. Every new idea is met in water first, then in symbols.
/// Every circuit shown is solved live by the app's engine; the concept animations are drawn.
enum Course {
    static let modules: [CourseModule] = [
        waterAndWires, foundations, basicLaws, methods, theorems, storage, firstOrder, secondOrder, alternating,
    ]
}

// MARK: - Authoring helpers

func scene(_ title: String, _ body: String, _ illustration: Illustration = .none, formula: String? = nil, text: String? = nil,
           analogy: [(String, String)] = [], remember: String? = nil) -> LessonScene {
    LessonScene(title: title, body: body, illustration: illustration, formula: formula, formulaText: text,
                analogy: analogy.map { AnalogyPair(water: $0.0, electric: $0.1) }, remember: remember)
}

func question(_ prompt: String, _ options: [String], answer: Int, _ explanation: String) -> QuizQuestion {
    QuizQuestion(prompt: prompt, options: options, answer: answer, explanation: explanation)
}

func keyframe(_ caption: String, _ highlight: DemoKeyframe.Highlight, seconds: Double? = nil) -> DemoKeyframe {
    DemoKeyframe(caption: caption, highlight: highlight, seconds: seconds)
}

// MARK: - Demo circuits

enum DemoCircuits {
    static let single = CircuitDemoSpec(id: "single", json: """
    {"components":[{"id":"V1","type":"voltage_source","value":12,"positive_node":"a","negative_node":"0"},
    {"id":"R1","type":"resistor","value":4,"node_a":"a","node_b":"0"}],"ground_node":"0","question":"Find the current."}
    """)

    static let series = CircuitDemoSpec(id: "series", json: """
    {"components":[{"id":"V1","type":"voltage_source","value":12,"positive_node":"a","negative_node":"0"},
    {"id":"R1","type":"resistor","value":100,"node_a":"a","node_b":"b"},
    {"id":"R2","type":"resistor","value":220,"node_a":"b","node_b":"0"}],"ground_node":"0","question":"Find the current."}
    """)

    static let divider = CircuitDemoSpec(id: "divider", json: """
    {"components":[{"id":"V1","type":"voltage_source","value":9,"positive_node":"a","negative_node":"0"},
    {"id":"R1","type":"resistor","value":1000,"node_a":"a","node_b":"b"},
    {"id":"R2","type":"resistor","value":2000,"node_a":"b","node_b":"0"}],"ground_node":"0","question":"Find the voltage across R2."}
    """)

    static let parallel = CircuitDemoSpec(id: "parallel", json: """
    {"components":[{"id":"V1","type":"voltage_source","value":12,"positive_node":"a","negative_node":"0"},
    {"id":"R1","type":"resistor","value":100,"node_a":"a","node_b":"0"},
    {"id":"R2","type":"resistor","value":300,"node_a":"a","node_b":"0"}],"ground_node":"0","question":"Find the current through each resistor."}
    """)

    static let twoLoops = CircuitDemoSpec(id: "twoLoops", json: """
    {"components":[{"id":"V1","type":"voltage_source","value":10,"positive_node":"a","negative_node":"0"},
    {"id":"R1","type":"resistor","value":2,"node_a":"a","node_b":"b"},
    {"id":"R2","type":"resistor","value":4,"node_a":"b","node_b":"0"},
    {"id":"R3","type":"resistor","value":3,"node_a":"b","node_b":"c"},
    {"id":"V2","type":"voltage_source","value":5,"positive_node":"c","negative_node":"0"}],
    "ground_node":"0","meshes":[["V1","R1","R2"],["R2","R3","V2"]],"unknowns":[{"kind":"current","element":"R2"}],"question":"Find the current through R2."}
    """)

    static let currentSource = CircuitDemoSpec(id: "currentSource", json: """
    {"components":[{"id":"I1","type":"current_source","value":2,"from_node":"0","to_node":"a"},
    {"id":"R1","type":"resistor","value":10,"node_a":"a","node_b":"b"},
    {"id":"R2","type":"resistor","value":20,"node_a":"b","node_b":"0"},
    {"id":"R3","type":"resistor","value":30,"node_a":"b","node_b":"0"}],
    "ground_node":"0","unknowns":[{"kind":"voltage","element":"R2"}],"question":"Find the voltage across R2."}
    """)

    static let supernode = CircuitDemoSpec(id: "supernode", json: """
    {"components":[{"id":"V1","type":"voltage_source","value":12,"positive_node":"a","negative_node":"0"},
    {"id":"R1","type":"resistor","value":2000,"node_a":"a","node_b":"b"},
    {"id":"V2","type":"voltage_source","value":5,"positive_node":"c","negative_node":"b"},
    {"id":"R2","type":"resistor","value":4000,"node_a":"b","node_b":"0"},
    {"id":"R3","type":"resistor","value":1000,"node_a":"c","node_b":"0"}],
    "ground_node":"0","unknowns":[{"kind":"voltage","node":"c"}],"question":"Find the voltage at node c."}
    """)

    static let supermesh = CircuitDemoSpec(id: "supermesh", json: """
    {"components":[{"id":"V1","type":"voltage_source","value":20,"positive_node":"a","negative_node":"0"},
    {"id":"R1","type":"resistor","value":4,"node_a":"a","node_b":"b"},
    {"id":"I1","type":"current_source","value":3,"from_node":"0","to_node":"b"},
    {"id":"R2","type":"resistor","value":6,"node_a":"b","node_b":"c"},
    {"id":"R3","type":"resistor","value":2,"node_a":"c","node_b":"0"}],
    "ground_node":"0","unknowns":[{"kind":"current","element":"R3"}],"question":"Find the current through R3."}
    """)

    static let bridge = CircuitDemoSpec(id: "bridge", json: """
    {"components":[{"id":"V1","type":"voltage_source","value":10,"positive_node":"a","negative_node":"0"},
    {"id":"R1","type":"resistor","value":1,"node_a":"a","node_b":"b"},
    {"id":"R2","type":"resistor","value":2,"node_a":"b","node_b":"0"},
    {"id":"R3","type":"resistor","value":3,"node_a":"a","node_b":"c"},
    {"id":"R4","type":"resistor","value":4,"node_a":"c","node_b":"0"},
    {"id":"R5","type":"resistor","value":5,"node_a":"b","node_b":"c"}],
    "ground_node":"0","unknowns":[{"kind":"current","element":"R5"}],"question":"Find the current through R5."}
    """)

    static let thevenin = CircuitDemoSpec(id: "thevenin", json: """
    {"components":[{"id":"V1","type":"voltage_source","value":12,"positive_node":"a","negative_node":"0"},
    {"id":"R1","type":"resistor","value":4,"node_a":"a","node_b":"b"},
    {"id":"R2","type":"resistor","value":4,"node_a":"b","node_b":"0"},
    {"id":"RL","type":"resistor","value":2,"node_a":"b","node_b":"0"}],
    "ground_node":"0","unknowns":[{"kind":"current","element":"RL"}],"question":"Find the current through the load RL."}
    """)

    static let theveninEquivalent = CircuitDemoSpec(id: "theveninEq", json: """
    {"components":[{"id":"Vth","type":"voltage_source","value":6,"positive_node":"a","negative_node":"0"},
    {"id":"Rth","type":"resistor","value":2,"node_a":"a","node_b":"b"},
    {"id":"RL","type":"resistor","value":2,"node_a":"b","node_b":"0"}],
    "ground_node":"0","unknowns":[{"kind":"current","element":"RL"}],"question":"Find the current through the load RL."}
    """)

    static let norton = CircuitDemoSpec(id: "norton", json: """
    {"components":[{"id":"IN","type":"current_source","value":3,"from_node":"0","to_node":"a"},
    {"id":"RN","type":"resistor","value":2,"node_a":"a","node_b":"0"},
    {"id":"RL","type":"resistor","value":2,"node_a":"a","node_b":"0"}],
    "ground_node":"0","unknowns":[{"kind":"current","element":"RL"}],"question":"Find the current through the load RL."}
    """)

    static let superpositionBoth = CircuitDemoSpec(id: "superBoth", json: """
    {"components":[{"id":"V1","type":"voltage_source","value":12,"positive_node":"a","negative_node":"0"},
    {"id":"R1","type":"resistor","value":2,"node_a":"a","node_b":"b"},
    {"id":"R2","type":"resistor","value":4,"node_a":"b","node_b":"0"},
    {"id":"R3","type":"resistor","value":2,"node_a":"b","node_b":"c"},
    {"id":"V2","type":"voltage_source","value":6,"positive_node":"c","negative_node":"0"}],
    "ground_node":"0","unknowns":[{"kind":"current","element":"R2"}],"question":"Find the current through R2."}
    """)

    static let superpositionV1 = CircuitDemoSpec(id: "superV1", json: """
    {"components":[{"id":"V1","type":"voltage_source","value":12,"positive_node":"a","negative_node":"0"},
    {"id":"R1","type":"resistor","value":2,"node_a":"a","node_b":"b"},
    {"id":"R2","type":"resistor","value":4,"node_a":"b","node_b":"0"},
    {"id":"R3","type":"resistor","value":2,"node_a":"b","node_b":"0"}],
    "ground_node":"0","unknowns":[{"kind":"current","element":"R2"}],"question":"V1 alone (V2 replaced by a wire)."}
    """)

    static let superpositionV2 = CircuitDemoSpec(id: "superV2", json: """
    {"components":[{"id":"R1","type":"resistor","value":2,"node_a":"0","node_b":"b"},
    {"id":"R2","type":"resistor","value":4,"node_a":"b","node_b":"0"},
    {"id":"R3","type":"resistor","value":2,"node_a":"b","node_b":"c"},
    {"id":"V2","type":"voltage_source","value":6,"positive_node":"c","negative_node":"0"}],
    "ground_node":"0","unknowns":[{"kind":"current","element":"R2"}],"question":"V2 alone (V1 replaced by a wire)."}
    """)

    static let sourceV = CircuitDemoSpec(id: "sourceV", json: """
    {"components":[{"id":"V1","type":"voltage_source","value":12,"positive_node":"a","negative_node":"0"},
    {"id":"R1","type":"resistor","value":3,"node_a":"a","node_b":"b"},
    {"id":"RL","type":"resistor","value":6,"node_a":"b","node_b":"0"}],
    "ground_node":"0","unknowns":[{"kind":"current","element":"RL"}],"question":"Find the load current."}
    """)

    static let sourceI = CircuitDemoSpec(id: "sourceI", json: """
    {"components":[{"id":"I1","type":"current_source","value":4,"from_node":"0","to_node":"b"},
    {"id":"R1","type":"resistor","value":3,"node_a":"b","node_b":"0"},
    {"id":"RL","type":"resistor","value":6,"node_a":"b","node_b":"0"}],
    "ground_node":"0","unknowns":[{"kind":"current","element":"RL"}],"question":"Find the load current."}
    """)

    static let rc = CircuitDemoSpec(id: "rc", json: """
    {"components":[{"id":"V1","type":"voltage_source","value":10,"positive_node":"a","negative_node":"0"},
    {"id":"R1","type":"resistor","value":1000,"node_a":"a","node_b":"b"},
    {"id":"C1","type":"capacitor","value":0.0001,"node_a":"b","node_b":"0"}],"ground_node":"0","question":"Charge the capacitor."}
    """)

    static let rcSwitch = CircuitDemoSpec(id: "rcSwitch", json: """
    {"components":[{"id":"V1","type":"voltage_source","value":10,"positive_node":"a","negative_node":"0"},
    {"id":"S1","type":"switch_closed","node_a":"a","node_b":"b"},
    {"id":"R1","type":"resistor","value":1000,"node_a":"b","node_b":"c"},
    {"id":"C1","type":"capacitor","value":0.0001,"node_a":"c","node_b":"0"},
    {"id":"R2","type":"resistor","value":2000,"node_a":"c","node_b":"0"}],"ground_node":"0","question":"Charge, then open the switch."}
    """)

    static let rl = CircuitDemoSpec(id: "rl", json: """
    {"components":[{"id":"V1","type":"voltage_source","value":10,"positive_node":"a","negative_node":"0"},
    {"id":"R1","type":"resistor","value":100,"node_a":"a","node_b":"b"},
    {"id":"L1","type":"inductor","value":1,"node_a":"b","node_b":"0"}],"ground_node":"0","question":"Switch the coil on."}
    """)

    static let rlDecay = CircuitDemoSpec(id: "rlDecay", json: """
    {"components":[{"id":"V1","type":"voltage_source","value":10,"positive_node":"a","negative_node":"0"},
    {"id":"S1","type":"switch_closed","node_a":"a","node_b":"b"},
    {"id":"R1","type":"resistor","value":50,"node_a":"b","node_b":"c"},
    {"id":"L1","type":"inductor","value":0.5,"node_a":"c","node_b":"0"},
    {"id":"R2","type":"resistor","value":50,"node_a":"c","node_b":"0"}],"ground_node":"0","question":"Build up the current, then open the switch."}
    """)

    static let rlc = CircuitDemoSpec(id: "rlc", json: """
    {"components":[{"id":"V1","type":"voltage_source","value":10,"positive_node":"a","negative_node":"0"},
    {"id":"R1","type":"resistor","value":10,"node_a":"a","node_b":"b"},
    {"id":"L1","type":"inductor","value":0.001,"node_a":"b","node_b":"c"},
    {"id":"C1","type":"capacitor","value":0.00001,"node_a":"c","node_b":"0"}],"ground_node":"0","question":"Switch the RLC circuit on."}
    """)

    static let rlcOverdamped = CircuitDemoSpec(id: "rlcOver", json: """
    {"components":[{"id":"V1","type":"voltage_source","value":10,"positive_node":"a","negative_node":"0"},
    {"id":"R1","type":"resistor","value":50,"node_a":"a","node_b":"b"},
    {"id":"L1","type":"inductor","value":0.001,"node_a":"b","node_b":"c"},
    {"id":"C1","type":"capacitor","value":0.00001,"node_a":"c","node_b":"0"}],"ground_node":"0","question":"The same circuit with more resistance."}
    """)

    static func with(_ spec: CircuitDemoSpec, _ keyframes: [DemoKeyframe], loop: Double = 10) -> CircuitDemoSpec {
        var copy = spec
        copy.keyframes = keyframes
        copy.loopSeconds = loop
        return copy
    }
}

// MARK: - Module 2: Foundations

extension Course {
    static let foundations = CourseModule(
        id: "m1", number: 2, title: "Foundations", subtitle: "The water ideas get their proper names: charge, current, voltage and power, one at a time.", isFree: true,
        lessons: [
            Lesson(id: "m1l1", title: "Charge and current", minutes: 6, scenes: [
                scene("What is actually flowing",
                      "In the pipes it was water. In a wire it is electric charge: tiny bits of it, far too small to see, that sit inside every metal and are free to move. A battery pushes them and they shuffle along the wire together. That shuffle is the current.",
                      .concept(.chargeFlow)),
                scene("A bucket of charge",
                      "Water is measured in buckets or litres. Charge is measured in coulombs, written C. One coulomb is an enormous number of the tiny charges, but you can simply think of it as one bucket of charge.",
                      remember: "A coulomb is a bucket of charge."),
                scene("Current is buckets per second",
                      "One ampere means one coulomb passes each second. Two amps: two coulombs every second. That is exactly the flow rate from the water lessons, with buckets of charge instead of buckets of water. In symbols, current is charge divided by time.",
                      formula: "I = \\frac{Q}{t}", text: "I = Q / t  (one ampere is one coulomb per second)",
                      analogy: [
                          ("Buckets of water", "Coulombs of charge (C)"),
                          ("Buckets per second", "Amperes (A)"),
                      ]),
                scene("Which way the arrow points",
                      "We draw the current arrow from the battery's + end, through the circuit, to its − end. In a metal wire the moving particles, the electrons, actually drift the opposite way. Both stories give the same numbers, so every book and every meter uses the arrow direction, called conventional current."),
                scene("A negative current is fine",
                      "If your arrow turns out to point against the real flow, nothing breaks: the number simply comes out negative. −2 A pointing left means 2 A pointing right. Watch this loop: the same current passes every part of it.",
                      .circuit(DemoCircuits.with(DemoCircuits.series, [
                          keyframe("One current, round the whole loop.", .flow),
                          keyframe("Through R1 …", .elements(["R1"])),
                          keyframe("… and through R2: the very same 37.5 mA.", .elements(["R2"])),
                          keyframe("The dots move at the same rate before and after each resistor.", .flow),
                      ])),
                      remember: "Current is the same everywhere along one path. A minus sign only means the arrow was drawn the other way."),
            ], quiz: [
                question("A wire carries 2 A. How much charge passes a point in 5 seconds?", ["0.4 C", "2 C", "10 C", "25 C"], answer: 2, "I = Q / t, so Q = I × t = 2 A × 5 s = 10 coulombs: ten buckets."),
                question("Conventional current arrows point…", ["the way electrons drift", "from + to −, outside the battery", "always clockwise", "nowhere in particular"], answer: 1, "Conventional current goes out of the + end, round the circuit, into the − end. Electrons drift the other way."),
                question("You drew an arrow to the right and worked out −1.5 A. That means…", ["you made a mistake", "1.5 A flows to the left", "no current flows", "the wire is broken"], answer: 1, "A negative value means the real flow is opposite to the arrow you chose."),
                question("Two lamps sit one after the other in a single loop. The current through the second lamp is…", ["half the current through the first", "the same as through the first", "double", "zero"], answer: 1, "One path, one current. Charge is not used up on the way."),
            ]),

            Lesson(id: "m1l2", title: "Voltage", minutes: 7, scenes: [
                scene("Height, pressure, voltage",
                      "Water at the top of a hill has energy to give as it runs down. Water under high pressure has energy to give as it flows. Charge at the + end of a battery has energy to give as it goes round. Voltage is that energy, per coulomb: a 9 V battery hands 9 joules to every coulomb it pushes out.",
                      .concept(.potentialHill),
                      formula: "V = \\frac{W}{Q}", text: "V = W / Q  (one volt is one joule per coulomb)"),
                scene("Always between two points",
                      "Just like pressure, a voltage is a difference. \"9 V across the battery\" means its + end is 9 V higher than its − end. \"3 V across the resistor\" means one end is 3 V higher than the other. A single point has no voltage until you say what you compare it with.",
                      .circuit(DemoCircuits.with(DemoCircuits.divider, [
                          keyframe("Three points: the bottom wire, a and b.", .nodes(["0", "a", "b"])),
                          keyframe("a is 9 V above the bottom wire …", .nodes(["a"])),
                          keyframe("… b is 6 V above it …", .nodes(["b"])),
                          keyframe("… so R1 has 9 − 6 = 3 V across it, and R2 has 6 V.", .flowWithPolarity),
                      ])),
                      remember: "A voltage is always the difference between two points."),
                scene("Sea level for voltage",
                      "Heights are measured from sea level. Voltages are measured from one chosen point of the circuit, called the reference or ground and drawn with a small rake symbol. It is 0 V by definition. Every other point then has one number: how far above ground it sits. Choose a different reference and all the numbers shift together, but no difference changes.",
                      .circuit(DemoCircuits.with(DemoCircuits.twoLoops, [
                          keyframe("The bottom wire is the reference: 0 V by choice.", .nodes(["0"])),
                          keyframe("Each other point gets one number, measured from it.", .nodes(["a", "b", "c"])),
                          keyframe("The voltage across each part is the difference of two of those numbers.", .flowWithPolarity),
                      ]))),
                scene("Two kinds of pump",
                      "A battery is a pump that holds a fixed pressure: 12 V whether a little current or a lot is drawn. There is a second kind of ideal source that holds a fixed flow instead, pushing with whatever voltage that takes. It is called a current source. It is rarer in real life, but useful in circuit problems.",
                      .circuit(DemoCircuits.with(DemoCircuits.currentSource, [
                          keyframe("A current source forces 2 A into the circuit, no matter what.", .elements(["I1"])),
                          keyframe("The circuit decides what voltage that needs: here 44 V.", .flow),
                      ])),
                      analogy: [
                          ("A pump that holds a fixed pressure", "Voltage source (a battery)"),
                          ("A pump that holds a fixed flow", "Current source"),
                      ]),
            ], quiz: [
                question("One volt is…", ["one bucket per second", "one joule of energy per coulomb", "one ohm per amp", "one coulomb"], answer: 1, "Voltage is energy per unit charge: 1 V = 1 J/C."),
                question("Point a is at 9 V and point b at 6 V, both measured from the same reference. Across a part joining them there is…", ["15 V", "9 V", "3 V, a being the higher end", "3 V, b being the higher end"], answer: 2, "A voltage across a part is the difference of its two end voltages: 9 − 6 = 3 V, with a the + end."),
                question("If you choose a different point as the 0 V reference…", ["all the currents change", "the voltage across each part changes", "the point numbers shift together and nothing physical changes", "the battery voltage changes"], answer: 2, "Only differences are physical. A new reference adds the same amount to every point."),
                question("An ideal 5 V battery is connected first to a small resistor, then to a large one. Its voltage is…", ["5 V both times", "higher with the large resistor", "lower with the large resistor", "zero with the small one"], answer: 0, "An ideal voltage source keeps its voltage whatever the current."),
            ]),

            Lesson(id: "m1l3", title: "Power and energy", minutes: 6, scenes: [
                scene("Push times flow",
                      "A water wheel gets more power from more pressure, or from more flow. Both matter, and they multiply. In a circuit it is the same: each coulomb carries V joules and I coulombs go by every second, so V × I joules are delivered every second. That rate is the power, in watts.",
                      .concept(.powerBalance),
                      formula: "P = V \\cdot I", text: "P = V · I",
                      analogy: [
                          ("Pressure × flow at a water wheel", "Voltage × current in a part"),
                          ("Watts", "Watts (the very same unit)"),
                      ]),
                scene("Giving and taking",
                      "Sources give power; resistors take it and turn it into heat or light. To tell the two apart from the numbers alone, draw the current arrow entering the + end of each part. Then a positive V × I means the part is taking power, and a negative one means it is giving. This bookkeeping rule is called the passive sign convention.",
                      .circuit(DemoCircuits.with(DemoCircuits.twoLoops, [
                          keyframe("Each resistor: the current enters at its + mark, so it takes power.", .flowWithPolarity),
                          keyframe("V1: the current comes out of its + end. It gives power.", .elements(["V1"])),
                          keyframe("V2: the current is pushed in at its + end. It is being charged, so it takes power.", .elements(["V2"])),
                      ]))),
                scene("Nothing is lost",
                      "Whatever the sources give, the rest of the circuit takes: the two totals are always equal. Photocircuits checks this at the end of every solution. If they did not match, a sign or a value would be wrong somewhere.",
                      formula: "P_{given} = P_{taken}", text: "power given by the sources = power taken by everything else",
                      remember: "Power given equals power taken. Always."),
                scene("Energy: power over time",
                      "Power is a rate, like a flow. Energy is the total delivered over a stretch of time: power times time. A 60 W lamp on for 2 hours uses 120 watt-hours. The electricity meter at home counts thousands of these, kilowatt-hours.",
                      formula: "W = P \\cdot t", text: "W = P · t"),
            ], quiz: [
                question("A resistor has 6 V across it and 0.5 A through it. It takes…", ["3 W", "12 W", "0.083 W", "6.5 W"], answer: 0, "P = V × I = 6 × 0.5 = 3 W, turned into heat."),
                question("With the current arrow entering the + end, P = −20 W means the part…", ["takes 20 W", "gives 20 W", "is a resistor", "has no voltage"], answer: 1, "A negative result under the passive sign convention means the part is supplying power."),
                question("The sources in a circuit give 45 W in total. Everything else takes…", ["less than 45 W", "exactly 45 W", "more than 45 W", "it cannot be known"], answer: 1, "Energy is conserved: power taken equals power given."),
                question("A 100 W lamp is on for 30 minutes. The energy used is…", ["3000 J", "50 Wh", "100 Wh", "0.5 kWh"], answer: 1, "Energy = power × time = 100 W × 0.5 h = 50 Wh."),
            ]),

            Lesson(id: "m1l4", title: "Reading a circuit diagram", minutes: 5, scenes: [
                scene("A diagram is a map of connections",
                      "A circuit diagram, or schematic, shows what is connected to what. It does not show shape or size. Stretch a wire, move a resistor to the other side of its loop, draw the whole thing upside down: nothing electrical changes. When you scan a circuit, Photocircuits reads exactly this: which parts meet where.",
                      .circuit(DemoCircuits.with(DemoCircuits.bridge, [
                          keyframe("Six parts, four meeting points.", .all),
                          keyframe("Point b is where R1, R2 and R5 meet.", .nodes(["b"])),
                          keyframe("Point c is where R3, R4 and R5 meet.", .nodes(["c"])),
                      ]))),
                scene("Wires are perfect pipes",
                      "On a diagram a wire is a perfect, wide, frictionless pipe: no resistance, so no voltage difference along it, however long it is drawn. Everything joined by wire is at one and the same voltage. That single fact is what makes circuits solvable.",
                      .circuit(DemoCircuits.with(DemoCircuits.twoLoops, [
                          keyframe("Every point of this wire is one place, b, at one voltage.", .nodes(["b"])),
                          keyframe("The whole bottom wire is one place too: the reference.", .nodes(["0"])),
                      ])),
                      remember: "Everything joined by wire is at the same voltage."),
                scene("The symbols",
                      "You have met the main ones: the battery (a long and a short line, + at the long one), the resistor (a zigzag), the switch (a gap that can close) and the ground rake for the reference. Later come the capacitor (two plates) and the inductor (a coil). Parts that give power are called active; parts that only take or store it are passive.",
                      .circuit(DemoCircuits.with(DemoCircuits.twoLoops, [
                          keyframe("Active: the two sources.", .elements(["V1", "V2"])),
                          keyframe("Passive: the three resistors.", .elements(["R1", "R2", "R3"])),
                      ]))),
                scene("What comes next",
                      "You now have the whole foundation: a closed loop, a push (voltage), a flow (current), things that resist (resistance) and the one relationship between them. The next module turns these into three short laws that solve any simple circuit.",
                      analogy: [
                          ("Pump", "Battery: a voltage source"),
                          ("Pressure difference", "Voltage (V)"),
                          ("Flow rate", "Current (A)"),
                          ("Narrow pipe", "Resistance (Ω)"),
                          ("Flow = push ÷ narrowness", "Ohm's law: I = V / R"),
                      ]),
            ], quiz: [
                question("Which of these is an active part?", ["a resistor", "a capacitor", "a battery", "a wire"], answer: 2, "Sources give power; resistors, capacitors and inductors only take or store it."),
                question("The voltage between the two ends of an ideal wire is…", ["proportional to its length", "zero", "the battery voltage", "unknown"], answer: 1, "No resistance, no voltage difference: the two ends are the same point electrically."),
                question("Redrawing a diagram with the same connections but a different shape…", ["changes the currents", "changes the voltages", "changes nothing electrical", "adds a connection"], answer: 2, "Only the connections matter to the circuit."),
            ]),
        ]
    )
}

// MARK: - Module 3: Basic laws

extension Course {
    static let basicLaws = CourseModule(
        id: "m2", number: 3, title: "Basic laws", subtitle: "Ohm's law and Kirchhoff's two laws, each met in water first, then in symbols; series, parallel and the dividers follow.", isFree: false,
        lessons: [
            Lesson(id: "m2l1", title: "Ohm's law", minutes: 6, scenes: [
                scene("Push, flow and pipe, once more",
                      "You met this in the water lessons: for one pipe, the flow rises with the push and falls with the narrowness. For a resistor, the current rises with the voltage and falls with the resistance. In this module the law is written the way the textbooks write it, voltage first, and used properly.",
                      .concept(.waterOhm)),
                scene("Voltage is proportional to current",
                      "For a resistor, the voltage across it is directly proportional to the current through it. The constant of proportionality is the resistance R, in ohms. Double the voltage and the current doubles; double the resistance and it halves.",
                      .concept(.ohmLine),
                      formula: "v = R \\cdot i", text: "v = R · i"),
                scene("Conductance, shorts and opens",
                      "The reciprocal of resistance is conductance G = 1/R, in siemens: how easily current passes. A short circuit is R = 0 (any current, no voltage); an open circuit is R = ∞ (any voltage, no current). Both are limiting cases of the same law.",
                      formula: "i = G \\cdot v, \\quad G = \\frac{1}{R}", text: "i = G · v with G = 1/R"),
                scene("Power in a resistor",
                      "Combine p = v·i with v = R·i and the resistor's power can be written three ways. It is always positive: a resistor only ever absorbs, turning electrical energy into heat.",
                      formula: "p = v i = i^2 R = \\frac{v^2}{R}", text: "p = v·i = i²·R = v²/R"),
                scene("Ohm's law in a real solve",
                      "Once the node voltages are known, every resistor current is one division: the voltage difference across it over its resistance. That is how Photocircuits reads off the currents at the end of the node-voltage method.",
                      .circuit(DemoCircuits.with(DemoCircuits.twoLoops, [
                          keyframe("R1 sits between 10 V and 6.154 V: (10 − 6.154)/2 = 1.923 A.", .elements(["R1"])),
                          keyframe("R2: 6.154 V across 4 Ω gives 1.538 A.", .elements(["R2"])),
                          keyframe("R3: (6.154 − 5)/3 = 0.385 A.", .elements(["R3"])),
                          keyframe("The currents, moving.", .flow),
                      ]))),
            ], quiz: [
                question("A 220 Ω resistor carries 50 mA. The voltage across it is…", ["4.4 V", "11 V", "0.23 V", "440 V"], answer: 1, "v = R·i = 220 × 0.05 = 11 V."),
                question("A resistor dissipates 2 W with 10 V across it. Its resistance is…", ["5 Ω", "20 Ω", "50 Ω", "200 Ω"], answer: 2, "p = v²/R, so R = v²/p = 100/2 = 50 Ω."),
                question("An open circuit has…", ["zero resistance", "zero voltage", "infinite resistance and no current", "infinite current"], answer: 2, "An open is a break: no current can pass whatever the voltage, which is R = ∞."),
                question("If the resistance is doubled and the voltage kept the same, the current…", ["doubles", "halves", "stays the same", "becomes zero"], answer: 1, "i = v/R: doubling R halves i."),
            ]),

            Lesson(id: "m2l2", title: "Nodes, branches and loops", minutes: 5, scenes: [
                scene("Branches",
                      "A branch is a single element: one resistor, one source. Counting branches counts the elements.",
                      .circuit(DemoCircuits.with(DemoCircuits.twoLoops, [
                          keyframe("Five branches: V1, R1, R2, R3, V2.", .elements(["V1", "R1", "R2", "R3", "V2"])),
                      ], loop: 5))),
                scene("Nodes",
                      "A node is a point where two or more branches meet, together with all the wire attached to it. A long wire with three things hanging off it is one node, not three.",
                      .circuit(DemoCircuits.with(DemoCircuits.twoLoops, [
                          keyframe("Node a: where V1 meets R1.", .nodes(["a"])),
                          keyframe("Node b: R1, R2 and R3 meet here.", .nodes(["b"])),
                          keyframe("Node c: R3 and V2.", .nodes(["c"])),
                          keyframe("The whole bottom rail is the fourth node, the reference.", .nodes(["0"])),
                      ]))),
                scene("Loops and meshes",
                      "A loop is any closed path that does not pass a node twice. A mesh is a loop with no other loop inside it, a window of the drawing. Meshes are the loops the mesh-current method uses.",
                      .circuit(DemoCircuits.with(DemoCircuits.twoLoops, [
                          keyframe("Mesh 1: V1, R1, R2.", .mesh(0)),
                          keyframe("Mesh 2: R2, R3, V2.", .mesh(1)),
                          keyframe("The outer path V1–R1–R3–V2 is a loop too, but not a mesh.", .meshes),
                      ]))),
                scene("How many equations",
                      "With b branches, n nodes and l independent loops, b = l + n − 1 always holds. Nodal analysis writes n − 1 equations; mesh analysis writes b − n + 1. For this circuit: 5 = 2 + 4 − 1.",
                      formula: "b = l + n - 1", text: "b = l + n − 1"),
            ], quiz: [
                question("A circuit has 7 branches and 4 nodes. How many independent loops (meshes, if planar) does it have?", ["3", "4", "7", "11"], answer: 1, "l = b − n + 1 = 7 − 4 + 1 = 4."),
                question("Three resistors hang from one long wire. That wire counts as…", ["three nodes", "one node", "a branch", "a loop"], answer: 1, "A node includes all the wire that is joined together; how many things attach to it does not matter."),
                question("A mesh is…", ["any closed path", "a closed path with no other closed path inside it", "a node with three branches", "the reference node"], answer: 1, "Meshes are the windows of a planar drawing."),
            ]),

            Lesson(id: "m2l3", title: "Kirchhoff's current law", minutes: 6, scenes: [
                scene("Water at a junction",
                      "Where a pipe splits, the water splits too, and none is lost: what flows in flows out. That is all Kirchhoff's current law says, for charge instead of water. Everything else in this lesson is about writing it down neatly.",
                      .concept(.waterJunction)),
                scene("Charge does not pile up",
                      "At any node, the total current flowing in equals the total flowing out. Charge cannot accumulate at a junction, so what comes in must leave.",
                      .concept(.kclJunction),
                      formula: "\\sum i_{in} = \\sum i_{out}", text: "sum of currents in = sum of currents out"),
                scene("Writing it with signs",
                      "The usual way to write KCL is to call every current leaving the node positive and set the sum to zero. A current that actually flows in then appears with a minus sign. Any consistent choice works; \"leaving = positive\" is the one Photocircuits uses.",
                      formula: "\\sum_{k} i_k = 0", text: "the algebraic sum of the currents at a node is zero"),
                scene("KCL at a real node",
                      "At node b three currents meet. Written with Ohm's law, each is (this node − other node)/R, which is exactly the equation the node-voltage method solves. Watch the dots: what arrives at b through R1 leaves through R2 and R3.",
                      .circuit(DemoCircuits.with(DemoCircuits.twoLoops, [
                          keyframe("Node b: R1 brings 1.923 A in.", .nodes(["b"])),
                          keyframe("R2 takes 1.538 A and R3 takes 0.385 A out: 1.538 + 0.385 = 1.923.", .flow),
                      ]))),
                scene("KCL for a region",
                      "The law also holds for any closed boundary, not just a point: whatever current enters a region leaves it. That is what makes the supernode trick possible later on.",
                      .circuit(DemoCircuits.with(DemoCircuits.supernode, [
                          keyframe("Draw a boundary round nodes b and c: the currents through it still sum to zero.", .supernode(nodes: ["b", "c"], elements: ["V2"])),
                      ], loop: 5))),
            ], quiz: [
                question("Three wires meet at a node. 4 A enters through one and 1 A enters through another. The third carries…", ["3 A in", "3 A out", "5 A in", "5 A out"], answer: 3, "In = out: 4 + 1 = 5 A must leave through the third wire."),
                question("Writing KCL as \"sum of currents leaving = 0\", a current of 2 A flowing into the node is written as…", ["+2 A", "−2 A", "0", "2 A in either sign"], answer: 1, "Entering currents get the opposite sign to leaving ones."),
                question("KCL applies to…", ["nodes only", "meshes only", "any node or any closed region", "the reference node only"], answer: 2, "Conservation of charge holds for any closed surface, which is why supernodes work."),
            ]),

            Lesson(id: "m2l4", title: "Kirchhoff's voltage law", minutes: 6, scenes: [
                scene("Pressure once round the loop",
                      "Follow the pressure once round a water loop. The pump raises it; each narrow section uses some up; back at the pump you are at the pressure you started from. Around a circuit loop the voltage does the same: what the sources raise, the resistors use up.",
                      .concept(.waterSeries)),
                scene("Back where you started",
                      "Walk once round any closed loop, adding the voltage rises and subtracting the drops. You arrive at the potential you left from, so the total is zero. Voltage is like height: a round trip has no net climb.",
                      .concept(.kvlStaircase),
                      formula: "\\sum_{k} v_k = 0", text: "the algebraic sum of voltages around a loop is zero"),
                scene("Signs",
                      "Pick a direction. Crossing a source from − to + is a rise; crossing a resistor in the direction of its current is a drop of R·I. The mesh-current method writes exactly this sum for every mesh.",
                      .circuit(DemoCircuits.with(DemoCircuits.twoLoops, [
                          keyframe("Around mesh 1: +10 V from V1, −2·I₁ across R1, −4·(I₁ − I₂) across R2 = 0.", .mesh(0)),
                          keyframe("Around mesh 2: −4·(I₂ − I₁), −3·I₂, −5 V from V2 = 0.", .mesh(1)),
                      ]))),
                scene("Series voltages add",
                      "A direct consequence: elements in series (one after the other) share the current, and their voltages add up to the total. The 12 V of this source is split between R1 and R2 as 3.75 V + 8.25 V.",
                      .circuit(DemoCircuits.with(DemoCircuits.series, [
                          keyframe("3.75 V across R1…", .elements(["R1"])),
                          keyframe("… plus 8.25 V across R2 = 12 V, the source.", .elements(["R2"])),
                      ]))),
            ], quiz: [
                question("A loop contains a 12 V source and two resistors with 4 V and x V across them (all drops in the direction of the current). x is…", ["16 V", "8 V", "4 V", "12 V"], answer: 1, "Rises equal drops around the loop: 12 = 4 + x, so x = 8 V."),
                question("Crossing a resistor in the direction of its current, the potential…", ["rises by R·I", "drops by R·I", "does not change", "drops by I/R"], answer: 1, "Current flows from higher to lower potential through a resistor: a drop of R·I."),
                question("KVL is a statement of…", ["conservation of charge", "conservation of energy (potential is single-valued)", "Ohm's law", "the passive sign convention"], answer: 1, "A round trip returns to the same potential; the net energy per coulomb around any loop is zero."),
            ]),

            Lesson(id: "m2l5", title: "Series resistors and voltage division", minutes: 7, scenes: [
                scene("Narrow sections one after the other",
                      "Two narrow sections in one pipe: the same flow through both, and each uses up a share of the push, the narrower one the bigger share. Resistors one after the other, in series, do exactly this: one current, and the voltage split between them.",
                      .concept(.waterSeries)),
                scene("Same current, voltages add",
                      "Resistors in series carry the same current. By KVL their voltages add, and by Ohm's law each voltage is R times that current. So the resistances simply add.",
                      .concept(.seriesBulbs),
                      formula: "R_{eq} = R_1 + R_2 + \\cdots + R_N", text: "R_eq = R1 + R2 + … + RN"),
                scene("Voltage division",
                      "The total voltage splits in proportion to the resistances: the larger resistor takes the larger share. This rule is worth knowing by heart; it is the first thing to reach for in a series circuit.",
                      .concept(.voltageDivider),
                      formula: "v_2 = \\frac{R_2}{R_1 + R_2} \\, v", text: "v2 = v · R2 / (R1 + R2)"),
                scene("Watch the engine do it",
                      "Photocircuits' simplest method combines series and parallel pairs one at a time, then works back. Here it is on a divider: combine, apply Ohm's law, split the voltage.",
                      .steps(DemoCircuits.divider, method: .reduction)),
            ], quiz: [
                question("100 Ω, 220 Ω and 680 Ω in series make…", ["1000 Ω", "1 kΩ exactly 1000", "1 kΩ (1000 Ω)", "68 Ω"], answer: 2, "Series resistances add: 100 + 220 + 680 = 1000 Ω = 1 kΩ."),
                question("A 12 V source feeds 1 kΩ and 3 kΩ in series. The voltage across the 3 kΩ is…", ["3 V", "4 V", "9 V", "12 V"], answer: 2, "Voltage division: 12 × 3/(1 + 3) = 9 V. The larger resistor takes the larger share."),
                question("Two identical lamps in series across a 12 V supply each see…", ["12 V", "6 V", "24 V", "3 V"], answer: 1, "Equal resistances split the voltage equally: 6 V each, so each glows at a quarter of its normal power."),
            ]),

            Lesson(id: "m2l6", title: "Parallel resistors and current division", minutes: 7, scenes: [
                scene("Pipes side by side",
                      "Two pipes between the same two points feel the same push, and the flow shares itself between them, more through the wide one. Together they pass more than either alone. Resistors side by side, in parallel, do exactly this.",
                      .concept(.waterParallel)),
                scene("Same voltage, currents add",
                      "Resistors in parallel connect the same two nodes, so they have the same voltage. By KCL their currents add; by Ohm's law each current is v/R. Conductances add, which for two resistors is the product-over-sum rule.",
                      .concept(.parallelBulbs),
                      formula: "\\frac{1}{R_{eq}} = \\frac{1}{R_1} + \\frac{1}{R_2}, \\quad R_{eq} = \\frac{R_1 R_2}{R_1 + R_2}", text: "1/R_eq = 1/R1 + 1/R2, so R_eq = R1·R2/(R1 + R2)"),
                scene("Always smaller",
                      "The parallel combination is smaller than the smallest member: adding another path can only make it easier for current to pass. Two equal resistors in parallel give half of one.",
                      .circuit(DemoCircuits.with(DemoCircuits.parallel, [
                          keyframe("100 Ω and 300 Ω between the same nodes.", .elements(["R1", "R2"])),
                          keyframe("Together: 100·300/400 = 75 Ω, less than either.", .flow),
                      ]))),
                scene("Current division",
                      "The current splits inversely to resistance: the smaller resistor takes the larger share. For two resistors, the share of R1 is R2 over the sum.",
                      .circuit(DemoCircuits.with(DemoCircuits.parallel, [
                          keyframe("160 mA arrives at the top node.", .nodes(["a"])),
                          keyframe("R1 (100 Ω) takes 120 mA, R2 (300 Ω) takes 40 mA.", .flow),
                      ])),
                      formula: "i_1 = \\frac{R_2}{R_1 + R_2} \\, i", text: "i1 = i · R2 / (R1 + R2)"),
                scene("The engine's version",
                      "Combine the parallel pair, apply Ohm's law to the whole, then share the voltage back out and divide the current.",
                      .steps(DemoCircuits.parallel, method: .reduction)),
            ], quiz: [
                question("6 Ω in parallel with 3 Ω is…", ["9 Ω", "4.5 Ω", "2 Ω", "1 Ω"], answer: 2, "Product over sum: 6 × 3 / (6 + 3) = 2 Ω, smaller than both."),
                question("Two equal resistors R in parallel make…", ["2R", "R", "R/2", "R/4"], answer: 2, "Two equal paths halve the resistance."),
                question("A 3 A current splits between 2 Ω and 4 Ω in parallel. The 2 Ω takes…", ["1 A", "1.5 A", "2 A", "3 A"], answer: 2, "Current division: 3 × 4/(2 + 4) = 2 A. The smaller resistor takes the larger share."),
                question("Adding one more resistor in parallel to an existing group…", ["raises the total resistance", "lowers the total resistance", "leaves it unchanged", "depends on its value"], answer: 1, "Another path always lets more current through: the equivalent resistance falls."),
            ]),

            Lesson(id: "m2l7", title: "Wye–delta transformation", minutes: 5, scenes: [
                scene("When nothing is in series or parallel",
                      "Some networks, such as a bridge, contain no two resistors in series or in parallel. Three resistors joined in a Y (star) can be replaced by three in a Δ (triangle) that look identical from the outside, and vice versa. That often unlocks a series-parallel reduction.",
                      .concept(.wyeDelta)),
                scene("The formulas",
                      "Each Y resistor is the product of the two adjacent Δ resistors over the Δ sum. Each Δ resistor is the sum of the pairwise products of the Y resistors over the opposite Y resistor. With three equal resistors, R_Δ = 3 R_Y.",
                      formula: "R_1 = \\frac{R_b R_c}{R_a + R_b + R_c}, \\quad R_a = \\frac{R_1 R_2 + R_2 R_3 + R_3 R_1}{R_1}", text: "R1 = Rb·Rc/(Ra + Rb + Rc);  Ra = (R1R2 + R2R3 + R3R1)/R1"),
                scene("Or just use a method",
                      "Photocircuits does not need the transformation: when a network is not series-parallel, it skips the reduction method and solves with nodal or mesh analysis directly. Here is a bridge, solved.",
                      .circuit(DemoCircuits.with(DemoCircuits.bridge, [
                          keyframe("No two resistors here are in series or in parallel.", .all),
                          keyframe("Nodal or mesh analysis handles it without any transformation.", .flow),
                      ]))),
            ], quiz: [
                question("Three 9 Ω resistors in a Y are equivalent to a Δ of…", ["3 Ω each", "9 Ω each", "27 Ω each", "81 Ω each"], answer: 2, "For equal resistors R_Δ = 3 R_Y = 27 Ω."),
                question("A Wheatstone bridge with all five resistors different…", ["is a series-parallel network", "is not series-parallel, but nodal or mesh analysis solves it", "cannot be solved", "has no meshes"], answer: 1, "The bridge resistor breaks the series-parallel pattern; a Y–Δ transformation or a general method is needed."),
            ]),
        ]
    )
}

// MARK: - Module 4: Methods of analysis

extension Course {
    static let methods = CourseModule(
        id: "m3", number: 4, title: "Methods of analysis", subtitle: "Nodal and mesh analysis: the two systematic ways to solve any circuit, exactly as Photocircuits does it.", isFree: false,
        lessons: [
            Lesson(id: "m3l1", title: "Nodal analysis", minutes: 9, scenes: [
                scene("The idea",
                      "Choose a reference node. The unknowns are the voltages of the other nodes. Write KCL at each of them with every current expressed through Ohm's law as (this node − other node)/R. Solve. Everything else, every current and voltage, follows in one line each.",
                      .circuit(DemoCircuits.with(DemoCircuits.twoLoops, [
                          keyframe("Reference: the bottom node, 0 V.", .nodes(["0"])),
                          keyframe("Unknowns Va, Vb, Vc, but Va and Vc are fixed by the sources.", .nodes(["a", "b", "c"])),
                          keyframe("One KCL equation at b gives everything.", .nodes(["b"])),
                      ]))),
                scene("Step by step",
                      "Follow the engine through the whole method: nodes, reference, sources that fix a node, KCL with the fractions cleared, the solution, and the currents read off at the end.",
                      .steps(DemoCircuits.twoLoops, method: .nodal)),
                scene("Two unknowns",
                      "With two unknown nodes there are two KCL equations. Multiplying each by a common multiple of its resistances turns it into whole numbers, and the pair is solved by elimination. Here the current source injects 2 A at node a.",
                      .steps(DemoCircuits.currentSource, method: .nodal)),
                scene("When to like it",
                      "Nodal analysis needs n − 1 equations for n nodes, fewer still when sources fix some nodes. It is the natural choice when the circuit has many parallel branches and few nodes, and it is what circuit simulators use internally.",
                      formula: "\\frac{V_b - V_a}{R_1} + \\frac{V_b}{R_2} + \\frac{V_b - V_c}{R_3} = 0", text: "(Vb − Va)/R1 + Vb/R2 + (Vb − Vc)/R3 = 0"),
            ], quiz: [
                question("In nodal analysis the unknowns are…", ["the currents in each mesh", "the voltages of the non-reference nodes", "the resistances", "the powers"], answer: 1, "One voltage per node other than the reference; every current follows from them."),
                question("A circuit has 5 nodes, none fixed by a source. Nodal analysis needs…", ["5 equations", "4 equations", "1 equation", "6 equations"], answer: 1, "n − 1 = 4 KCL equations; the reference node contributes none."),
                question("The KCL term for a resistor R between the node being analysed (voltage Vb) and a node at Vc is…", ["R·(Vb − Vc)", "(Vb − Vc)/R as a current leaving", "(Vc − Vb)·R", "Vb/R only"], answer: 1, "Ohm's law: the current leaving Vb toward Vc is (Vb − Vc)/R."),
                question("A voltage source between a node and the reference…", ["makes nodal analysis impossible", "fixes that node's voltage, so no KCL is needed there", "must be converted to a current source", "adds two unknowns"], answer: 1, "The node voltage is simply the source voltage; it is substituted into the other equations."),
            ]),

            Lesson(id: "m3l2", title: "Supernodes", minutes: 7, scenes: [
                scene("The problem",
                      "A voltage source between two non-reference nodes fixes their difference but not either voltage, and Ohm's law says nothing about the current through it. KCL cannot be written at either node alone.",
                      .circuit(DemoCircuits.with(DemoCircuits.supernode, [
                          keyframe("V2 floats between b and c; its current is unknown.", .elements(["V2"])),
                      ], loop: 4))),
                scene("Draw a boundary",
                      "Enclose both nodes in one region: a supernode. KCL for the region does not involve the source current at all, because it stays inside. The source still contributes an equation: Vc − Vb = 5 V.",
                      .circuit(DemoCircuits.with(DemoCircuits.supernode, [
                          keyframe("One KCL equation for the region b–c…", .supernode(nodes: ["b", "c"], elements: ["V2"])),
                          keyframe("… plus the constraint Vc − Vb = 5 V: two equations, two unknowns.", .nodes(["b", "c"])),
                      ]))),
                scene("Worked through",
                      "The engine forms the supernode, sums the currents leaving it, adds the source relation and solves the pair.",
                      .steps(DemoCircuits.supernode, method: .nodal)),
            ], quiz: [
                question("A supernode is needed when…", ["a current source lies between two nodes", "a voltage source lies between two non-reference nodes", "two resistors are in parallel", "the reference node has many branches"], answer: 1, "Only a floating voltage source blocks KCL at a single node."),
                question("How many equations does a supernode made of two nodes contribute?", ["none", "one KCL for the region plus one constraint from the source", "two KCL equations", "three"], answer: 1, "KCL around the boundary, and the fixed voltage difference across the source."),
                question("Inside the supernode boundary, the current through the voltage source…", ["must be found first", "never appears in the KCL equation", "is zero", "equals the source voltage divided by R"], answer: 1, "It enters and leaves within the region, so it cancels; that is the whole point of the boundary."),
            ]),

            Lesson(id: "m3l3", title: "Mesh analysis", minutes: 9, scenes: [
                scene("The idea",
                      "Give every mesh (window) its own circulating current, all clockwise. An element on the outside carries its mesh current; an element between two meshes carries their difference. Write KVL around each mesh and solve for the mesh currents.",
                      .circuit(DemoCircuits.with(DemoCircuits.twoLoops, [
                          keyframe("Two meshes, two clockwise currents I₁ and I₂.", .meshes),
                          keyframe("R2 is shared: it carries I₁ − I₂.", .elements(["R2"])),
                      ]))),
                scene("Step by step",
                      "KVL around each mesh, element by element: a resistor drops R times the net current through it, a source is a rise or a drop depending on which way you cross it. Then two equations, elimination, back-substitution.",
                      .steps(DemoCircuits.twoLoops, method: .mesh)),
                scene("Reading the signs",
                      "A mesh current that comes out negative simply circulates the other way. Keep the sign in the algebra and use the direction when describing the answer.",
                      formula: "2 I_1 + 4 (I_1 - I_2) - 10 = 0", text: "2·I1 + 4·(I1 − I2) − 10 = 0 around mesh 1"),
                scene("When to like it",
                      "Mesh analysis needs b − n + 1 equations, one per window. It suits planar circuits with many series elements and few meshes. It cannot be applied to a circuit that cannot be drawn without crossings.",
                      .circuit(DemoCircuits.with(DemoCircuits.bridge, [
                          keyframe("Three windows: three mesh equations for the bridge.", .meshes),
                      ], loop: 5))),
            ], quiz: [
                question("In mesh analysis, an element shared by meshes 1 and 2 (both clockwise) carries…", ["I₁ + I₂", "I₁ − I₂ (or I₂ − I₁, depending on direction)", "I₁ × I₂", "the larger of the two"], answer: 1, "Clockwise neighbours run through a shared element in opposite directions, so their currents subtract."),
                question("A planar circuit with 6 branches and 4 nodes needs how many mesh equations?", ["2", "3", "4", "6"], answer: 1, "b − n + 1 = 6 − 4 + 1 = 3."),
                question("A mesh current of −0.4 A means…", ["the calculation failed", "0.4 A circulating counter-clockwise", "0.4 A flowing into the reference node", "the mesh has no source"], answer: 1, "Negative just reverses the assumed clockwise direction."),
                question("Mesh analysis can be used…", ["for any circuit", "only for planar circuits", "only for circuits with one source", "only for circuits without resistors"], answer: 1, "Meshes are windows of a planar drawing; a non-planar circuit has none."),
            ]),

            Lesson(id: "m3l4", title: "Supermeshes", minutes: 7, scenes: [
                scene("The problem",
                      "A current source between two meshes has an unknown voltage across it, so KVL cannot be written through it. If it lies in only one mesh, that mesh current is simply known; if it is shared, a different trick is needed.",
                      .circuit(DemoCircuits.with(DemoCircuits.supermesh, [
                          keyframe("I1 lies between the two meshes.", .elements(["I1"])),
                      ], loop: 4))),
                scene("Merge the meshes",
                      "Write KVL around the outside of both meshes together, a supermesh, so the current source is never crossed. The source then supplies the missing equation: the difference of the two mesh currents equals its value.",
                      .circuit(DemoCircuits.with(DemoCircuits.supermesh, [
                          keyframe("One KVL around the outer path…", .meshes),
                          keyframe("… and I₁ − I₂ = 3 A from the source.", .elements(["I1"])),
                      ]))),
                scene("Worked through",
                      "The engine walks the supermesh, skips the source, and solves the pair with the constraint.",
                      .steps(DemoCircuits.supermesh, method: .mesh)),
            ], quiz: [
                question("A supermesh is needed when…", ["a voltage source lies between two nodes", "a current source is shared by two meshes", "a resistor is shared by two meshes", "there is only one mesh"], answer: 1, "KVL cannot cross a current source of unknown voltage, so the two meshes are combined."),
                question("The extra equation for a supermesh comes from…", ["Ohm's law across the current source", "the current source: the mesh currents through it differ by its value", "KCL at the reference node", "the power balance"], answer: 1, "The source fixes the net mesh current through it."),
                question("A current source that lies in only one mesh…", ["needs a supermesh", "makes that mesh current known immediately", "must be removed", "doubles the number of equations"], answer: 1, "The mesh current equals the source current (with the sign for direction)."),
            ]),

            Lesson(id: "m3l5", title: "Choosing a method", minutes: 4, scenes: [
                scene("Count the equations",
                      "Nodal analysis: n − 1 unknowns, minus one for each node fixed by a grounded voltage source. Mesh analysis: b − n + 1 unknowns, minus one for each current source in a single mesh. Pick the smaller count.",
                      .circuit(DemoCircuits.with(DemoCircuits.twoLoops, [
                          keyframe("Nodal: 3 nodes, 2 fixed by sources → 1 equation.", .nodes(["b"])),
                          keyframe("Mesh: 2 windows → 2 equations. Nodal wins here.", .meshes),
                      ]))),
                scene("What Photocircuits does",
                      "It runs every applicable method and compares the element currents. Agreement between independent methods is the best check there is; the Solutions screen shows whether they agree, and the reduction method appears whenever the network is series-parallel with one source.",
                      .circuit(DemoCircuits.with(DemoCircuits.bridge, [
                          keyframe("Bridge: nodal needs 2 equations, mesh needs 3.", .nodes(["b", "c"])),
                      ], loop: 5))),
            ], quiz: [
                question("A circuit has 4 nodes (one grounded source fixes one node) and 3 meshes. Fewer equations come from…", ["nodal: 2", "mesh: 3", "they are equal", "neither can be used"], answer: 0, "Nodal: 4 − 1 − 1 = 2 unknowns. Mesh: 3 unknowns."),
                question("Two independent methods give the same element currents. This…", ["proves nothing", "is a strong check that the solution is right", "means one method was unnecessary", "means the circuit is trivial"], answer: 1, "Independent derivations agreeing is the standard way to catch a sign or arithmetic slip."),
            ]),
        ]
    )
}

// MARK: - Module 4: Circuit theorems

extension Course {
    static let theorems = CourseModule(
        id: "m4", number: 5, title: "Circuit theorems", subtitle: "Superposition, source transformation, Thévenin, Norton and maximum power: shortcuts that follow from linearity.", isFree: false,
        lessons: [
            Lesson(id: "m4l1", title: "Linearity and superposition", minutes: 8, scenes: [
                scene("Linear circuits",
                      "Resistors, capacitors, inductors and independent sources make linear circuits: double every source and every voltage and current doubles. That single property is behind every theorem in this module.",
                      .concept(.superposition)),
                scene("One source at a time",
                      "In a linear circuit, any voltage or current is the sum of the contributions of each independent source acting alone. To switch a source off: replace a voltage source by a wire (0 V) and a current source by a gap (0 A). Solve once per source and add.",
                      .circuit(DemoCircuits.with(DemoCircuits.superpositionBoth, [
                          keyframe("Two sources; we want the current in R2.", .elements(["R2"])),
                          keyframe("Both on: 1.8 A through R2.", .flow),
                      ]))),
                scene("V1 alone",
                      "With V2 replaced by a wire, R3 goes straight to the reference. The engine solves this reduced circuit: R2 carries 1.2 A.",
                      .circuit(DemoCircuits.with(DemoCircuits.superpositionV1, [
                          keyframe("V2 → wire. R2 carries 1.2 A.", .flow),
                      ], loop: 5))),
                scene("V2 alone, then add",
                      "With V1 replaced by a wire, R2 carries 0.6 A in the same direction. Add: 1.2 + 0.6 = 1.8 A, exactly what the full circuit gave. Note that powers do not add this way; only voltages and currents do.",
                      .circuit(DemoCircuits.with(DemoCircuits.superpositionV2, [
                          keyframe("V1 → wire. R2 carries 0.6 A.", .flow),
                      ], loop: 5)),
                      formula: "i = i' + i''", text: "i = i′ + i″"),
            ], quiz: [
                question("To switch off an independent voltage source for superposition, replace it by…", ["an open circuit", "a short circuit (wire)", "a resistor", "a current source"], answer: 1, "A voltage source at 0 V is a wire. A current source at 0 A is an open."),
                question("Superposition applies to…", ["voltages and currents in linear circuits", "powers", "any circuit, linear or not", "circuits with one source only"], answer: 0, "Power is quadratic in current, so it does not superpose; the method also needs linearity."),
                question("Source A alone gives 3 mA to the right through R; source B alone gives 1 mA to the left. Together R carries…", ["4 mA right", "2 mA right", "2 mA left", "3 mA right"], answer: 1, "Add with signs: 3 − 1 = 2 mA to the right."),
            ]),

            Lesson(id: "m4l2", title: "Source transformation", minutes: 6, scenes: [
                scene("Two faces of one source",
                      "A voltage source V in series with R behaves, at its terminals, exactly like a current source I = V/R in parallel with the same R. Either can replace the other; the rest of the circuit cannot tell the difference.",
                      .circuit(DemoCircuits.with(DemoCircuits.sourceV, [
                          keyframe("12 V in series with 3 Ω, feeding a 6 Ω load: 1.333 A.", .flow),
                      ], loop: 5)),
                      formula: "I = \\frac{V}{R}, \\quad V = I R", text: "I = V/R and V = I·R, with the same R"),
                scene("The other face",
                      "The same load sees 4 A in parallel with 3 Ω: current division gives the 6 Ω load 4 × 3/9 = 1.333 A. Same current, same voltage, same power in the load.",
                      .circuit(DemoCircuits.with(DemoCircuits.sourceI, [
                          keyframe("4 A in parallel with 3 Ω: the load still gets 1.333 A.", .flow),
                      ], loop: 5))),
                scene("Why bother",
                      "Transforming back and forth lets you combine sources and resistors in series or in parallel until a circuit collapses to one source and one resistor. The + terminal of the voltage source and the arrow of the current source must point the same way.",
                      .concept(.theveninBox)),
            ], quiz: [
                question("A 10 V source in series with 5 Ω is equivalent at its terminals to…", ["2 A in parallel with 5 Ω", "50 A in parallel with 5 Ω", "2 A in series with 5 Ω", "10 A in parallel with 0.5 Ω"], answer: 0, "I = V/R = 2 A, with the same 5 Ω now in parallel."),
                question("After a source transformation, the current in an external load…", ["doubles", "is unchanged", "reverses", "becomes zero"], answer: 1, "The two forms are indistinguishable from outside; only the inside of the source changes."),
                question("An ideal voltage source with no series resistor…", ["transforms to an ideal current source", "cannot be transformed (R = 0)", "transforms to a 1 A source", "is the same as an open circuit"], answer: 1, "I = V/R would be infinite; ideal sources without resistance have no dual form."),
            ]),

            Lesson(id: "m4l3", title: "Thévenin's theorem", minutes: 9, scenes: [
                scene("Any two terminals",
                      "Seen from any pair of terminals, a linear circuit behaves like a single voltage source Vth in series with a single resistor Rth. Whatever you connect across the terminals cannot tell the difference. This is the most used result in circuit analysis.",
                      .concept(.theveninBox)),
                scene("Finding Vth and Rth",
                      "Vth is the open-circuit voltage at the terminals with nothing connected. Rth is the resistance seen looking into the terminals with every independent source switched off (voltage sources → wires, current sources → gaps). Alternatively Rth = Vth / Isc, with Isc the short-circuit current.",
                      formula: "V_{th} = v_{oc}, \\quad R_{th} = \\frac{v_{oc}}{i_{sc}}", text: "Vth = open-circuit voltage; Rth = Vth / short-circuit current"),
                scene("An example",
                      "12 V in series with 4 Ω, then 4 Ω to ground, feeding a 2 Ω load at node b. Open the load: the divider gives Vth = 6 V. Switch off the source: the two 4 Ω resistors are in parallel, Rth = 2 Ω.",
                      .circuit(DemoCircuits.with(DemoCircuits.thevenin, [
                          keyframe("The load RL hangs on node b.", .elements(["RL"])),
                          keyframe("Everything else is the network to replace.", .elements(["V1", "R1", "R2"])),
                          keyframe("Full solution: RL carries 1.5 A.", .flow),
                      ]))),
                scene("The equivalent behaves the same",
                      "Replace the network by Vth = 6 V and Rth = 2 Ω. The load current is 6 / (2 + 2) = 1.5 A, exactly as before. Change the load to anything you like: the equivalent still predicts it in one line.",
                      .circuit(DemoCircuits.with(DemoCircuits.theveninEquivalent, [
                          keyframe("Vth and Rth with the same load: 1.5 A again.", .flow),
                      ], loop: 5))),
            ], quiz: [
                question("Vth is measured…", ["with the terminals shorted", "with the terminals open", "with the load connected", "with all sources off"], answer: 1, "The Thévenin voltage is the open-circuit voltage at the terminals."),
                question("To find Rth by inspection, independent voltage sources are replaced by…", ["open circuits", "short circuits", "their internal resistance only", "current sources"], answer: 1, "Switch every independent source off: voltage sources become wires, current sources become gaps."),
                question("A network has Vth = 9 V and Rth = 3 Ω. A 6 Ω load draws…", ["3 A", "1.5 A", "1 A", "0.5 A"], answer: 2, "i = Vth/(Rth + RL) = 9/(3 + 6) = 1 A."),
                question("The short-circuit current of a network with Vth = 6 V and Rth = 2 Ω is…", ["12 A", "3 A", "6 A", "0.33 A"], answer: 1, "isc = Vth / Rth = 3 A; this is also the Norton current."),
            ]),

            Lesson(id: "m4l4", title: "Norton's theorem", minutes: 5, scenes: [
                scene("The current-source twin",
                      "Norton's theorem is Thévenin's after a source transformation: the same network also behaves like a current source IN in parallel with RN, where RN = Rth and IN = Vth / Rth, the short-circuit current.",
                      .circuit(DemoCircuits.with(DemoCircuits.norton, [
                          keyframe("IN = 3 A in parallel with RN = 2 Ω, the Norton form of the last example.", .elements(["IN", "RN"])),
                          keyframe("The 2 Ω load again draws 1.5 A.", .flow),
                      ]))),
                scene("Which to use",
                      "Use Thévenin when the load is in series with the source resistance, Norton when it is in parallel. Both are found from the same two measurements: open-circuit voltage and short-circuit current.",
                      formula: "I_N = \\frac{V_{th}}{R_{th}}, \\quad R_N = R_{th}", text: "IN = Vth / Rth, RN = Rth"),
            ], quiz: [
                question("A network has Vth = 10 V and Rth = 5 Ω. Its Norton equivalent is…", ["2 A in parallel with 5 Ω", "50 A in parallel with 5 Ω", "2 A in series with 5 Ω", "10 A in parallel with 0.5 Ω"], answer: 0, "IN = Vth/Rth = 2 A; RN = Rth = 5 Ω in parallel."),
                question("The Norton current equals…", ["the open-circuit voltage", "the short-circuit current at the terminals", "the load current", "Vth × Rth"], answer: 1, "Shorting the Norton equivalent's terminals sends all of IN through the short."),
            ]),

            Lesson(id: "m4l5", title: "Maximum power transfer", minutes: 5, scenes: [
                scene("How much can a load take?",
                      "Feed a load RL from a Thévenin source. A tiny RL takes a lot of current but little voltage; a huge RL the reverse. The power in the load peaks when RL equals Rth, at Vth²/(4 Rth).",
                      .concept(.maxPower),
                      formula: "P_{max} = \\frac{V_{th}^2}{4 R_{th}} \\text{ at } R_L = R_{th}", text: "Pmax = Vth² / (4 Rth) when RL = Rth"),
                scene("Matching, not efficiency",
                      "At the matched point half the power is lost in Rth: efficiency is only 50%. Matching matters for signals, antennas and audio; power distribution instead keeps Rth as small as possible.",
                      .concept(.maxPower)),
            ], quiz: [
                question("A source with Vth = 12 V and Rth = 6 Ω delivers the most power to a load of…", ["3 Ω", "6 Ω", "12 Ω", "0 Ω"], answer: 1, "Maximum power transfer occurs at RL = Rth = 6 Ω."),
                question("That maximum power is…", ["24 W", "12 W", "6 W", "3 W"], answer: 2, "Pmax = Vth²/(4Rth) = 144/24 = 6 W."),
                question("At maximum power transfer the efficiency is…", ["100%", "75%", "50%", "25%"], answer: 2, "Equal resistances share the power equally: half is lost inside the source."),
            ]),
        ]
    )
}
