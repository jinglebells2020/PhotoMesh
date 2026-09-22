import Foundation

// MARK: - Module 1: Water and wires

/// The opening module for someone who has never met a circuit: the water-in-pipes picture first,
/// one idea per lesson, no symbols until the very end. Pressure is voltage, flow rate is current,
/// a narrow pipe is resistance and the pump is the battery.
extension Course {
    static let waterAndWires = CourseModule(
        id: "m0", number: 1, title: "Water and wires", subtitle: "No formulas yet. A pump, some pipes and a narrow section explain everything a circuit does.", isFree: true,
        lessons: [
            Lesson(id: "m0l1", title: "A loop of water", minutes: 4, scenes: [
                scene("Start with water, not wires",
                      "Before any electricity, look at this little water system. A pump pushes water round a loop of pipe. On the way round, the water squeezes through one narrow section. That is all there is: a push, a path, and one place where the path is harder.",
                      .concept(.waterLoop)),
                scene("Round and round",
                      "The pump does not make water. It only keeps pushing the same water round and round. Every drop that leaves the pump comes back to it. Nothing is used up on the way.",
                      .concept(.waterPump),
                      remember: "A pump pushes water round. It never uses any up."),
                scene("Close the valve",
                      "Now close a valve anywhere in the loop. The water does not stop only at the valve. It stops everywhere at the same moment, because it is all one loop. Open the valve again and the whole loop moves again.",
                      .concept(.waterValve)),
                scene("Now the same picture with wires",
                      "Here is a battery, some wire and one small part called a resistor. Watch the dots go round: the battery pushes them, the wire carries them, the resistor makes it harder. It is the water loop again, drawn the electrical way.",
                      .circuit(DemoCircuits.with(DemoCircuits.single, [
                          keyframe("The battery is the pump: it does the pushing.", .elements(["V1"])),
                          keyframe("The resistor is the narrow section.", .elements(["R1"])),
                          keyframe("And the dots go round like the water: nothing is used up.", .flow),
                      ], loop: 12))),
                scene("The map",
                      "Every part of the water loop has an electrical twin. Keep this map in mind; the next lessons take it one row at a time.",
                      analogy: [
                          ("Pump", "Battery (or any power source)"),
                          ("Pipes", "Wires"),
                          ("Narrow section", "Resistor"),
                          ("Water going round", "Electric current"),
                          ("How hard the water is pushed", "Voltage"),
                      ],
                      remember: "A circuit is a closed loop. Break it anywhere and everything stops."),
            ], quiz: [
                question("In the water loop, what does the pump do?", ["It makes new water", "It pushes the same water round the loop", "It uses the water up", "It stores water"], answer: 1, "The pump only pushes. The same water goes round and round; none is made and none is used up."),
                question("You close a valve on the far side of the loop from the pump. What happens to the water next to the pump?", ["It keeps flowing", "It flows faster", "It stops too", "It flows backwards"], answer: 2, "It is all one loop. Block it anywhere and the water stops everywhere at once."),
                question("Which part of a circuit plays the part of the pump?", ["The wire", "The resistor", "The battery", "The switch"], answer: 2, "The battery does the pushing, just as the pump does."),
                question("A wire in a circuit is like…", ["the pump", "a pipe", "the narrow section", "a valve"], answer: 1, "Wires are the pipes: they carry the flow from one part to the next."),
            ]),

            Lesson(id: "m0l2", title: "Pressure, and voltage", minutes: 5, scenes: [
                scene("What makes water move?",
                      "Water only moves when something pushes it. That push is called pressure. Deep water pushes hard: the tall tank shoots its stream a long way. Shallow water pushes gently.",
                      .concept(.waterPressure)),
                scene("The pump makes the difference",
                      "The pump lifts water into an upper tank. Now there is a high side and a low side, and water runs from high to low through the narrow pipe. Switch the pump off and the difference fades away. So does the flow.",
                      .concept(.waterPump),
                      remember: "No difference, no flow."),
                scene("In a circuit, the push is voltage",
                      "A battery is a pump for electric charge. It keeps one of its ends high and the other low. That difference is the voltage, and it is what makes current go round the loop. Like pressure, voltage is always between two points.",
                      .circuit(DemoCircuits.with(DemoCircuits.single, [
                          keyframe("The + end of the battery is the high side, 12 V above the − end.", .elements(["V1"])),
                          keyframe("The resistor sits between high and low, so charge is pushed through it.", .elements(["R1"])),
                          keyframe("Round it goes.", .flow),
                      ], loop: 12))),
                scene("The volt",
                      "Voltage is measured in volts, written V. A small battery gives about 1.5 V, a phone charger 5 V, a car battery 12 V, a wall socket a great deal more. More volts means a harder push. That is all the number means for now.",
                      analogy: [
                          ("Pressure", "Voltage"),
                          ("High-pressure tank", "The + end of a battery"),
                          ("A strong pump", "A high-voltage source"),
                      ],
                      remember: "Voltage is the push. It is measured in volts (V), and always between two points."),
            ], quiz: [
                question("In the water picture, voltage is like…", ["how much water there is", "how hard the water is pushed", "how long the pipe is", "how warm the water is"], answer: 1, "Voltage is the push, just as pressure is the push on the water."),
                question("Two tanks joined by a pipe hold water at exactly the same pressure. The water…", ["flows toward the bigger tank", "flows toward the smaller tank", "does not move", "flows back and forth"], answer: 2, "No pressure difference, no flow. The same is true of voltage: no voltage difference, no current."),
                question("A 12 V battery, compared with a 1.5 V battery…", ["pushes harder", "holds more water", "is always bigger", "has thinner wires"], answer: 0, "More volts is simply a harder push."),
                question("Voltage is always measured between…", ["one point and nothing", "two points", "the whole circuit at once", "the ends of a wire only"], answer: 1, "Like pressure, voltage is a difference between two places."),
            ]),

            Lesson(id: "m0l3", title: "Flow, and current", minutes: 5, scenes: [
                scene("How much goes past?",
                      "Stand at one spot on the pipe and count the water going by. Three buckets every second is a flow rate. It is not about how fast one drop moves; it is about how much passes in each second.",
                      .concept(.waterFlowRate)),
                scene("The same all along one loop",
                      "In a single pipe with no branches, whatever passes one spot also passes every other spot. Water cannot pile up inside the pipe or vanish from it. So the flow rate is the same everywhere round the loop, before and after the narrow section.",
                      .concept(.waterLoop),
                      remember: "In one loop, the flow is the same everywhere."),
                scene("In a circuit, the flow is current",
                      "Current is how much electric charge passes a point each second. Watch the dots in this loop: the same number pass every part of it. The current through the battery is the current through each resistor.",
                      .circuit(DemoCircuits.with(DemoCircuits.series, [
                          keyframe("One current goes round the whole loop.", .flow),
                          keyframe("Through the first resistor…", .elements(["R1"])),
                          keyframe("… and exactly the same through the second.", .elements(["R2"])),
                          keyframe("Count the dots: the same before, the same after.", .flow),
                      ], loop: 12))),
                scene("The ampere",
                      "Current is measured in amperes, written A, or amps for short. A phone charger gives about 1 or 2 A; a car's starter motor takes a few hundred. Small currents are written in milliamps: 1 mA is a thousandth of an amp.",
                      analogy: [
                          ("Flow rate (buckets per second)", "Current (amperes)"),
                          ("Counting water past one spot", "Measuring current at one point"),
                          ("A trickle", "A few milliamps"),
                      ],
                      remember: "Current is the flow. It is measured in amperes (A) and is the same all round a single loop."),
                scene("Which way?",
                      "On diagrams we draw the current with an arrow from the + end of the battery, round the loop, back to the − end. Think of it as the direction the water is pushed. Inside a metal wire the tiny particles actually drift the other way; it does not matter yet, the arrow gives the right answers.",
                      .concept(.chargeFlow)),
            ], quiz: [
                question("Flow rate means…", ["how fast one drop moves", "how much passes a point each second", "how long the pipe is", "how deep the tank is"], answer: 1, "Flow rate counts what passes a point per second. Current does the same for charge."),
                question("A loop of pipe has one narrow section. Compared with the flow before it, the flow after it is…", ["smaller", "larger", "the same", "zero"], answer: 2, "Water cannot pile up or vanish, so the same amount passes every point of a single loop."),
                question("Current is measured in…", ["volts", "amperes", "litres", "ohms"], answer: 1, "Amperes, or amps: coulombs of charge per second."),
                question("In a single loop with a battery and a lamp, the current through the lamp is…", ["less than through the battery", "more than through the battery", "the same as through the battery", "zero"], answer: 2, "One loop, one current, the same everywhere."),
            ]),

            Lesson(id: "m0l4", title: "Narrow pipes, and resistance", minutes: 5, scenes: [
                scene("The narrow pipe",
                      "Two pumps push equally hard. One feeds a wide pipe, the other a narrow one. The wide pipe delivers a lot; the narrow one only a trickle. The narrow pipe resists the flow.",
                      .concept(.waterNarrowPipe)),
                scene("Where the push goes",
                      "Squeezing water through a narrow gap takes effort, and that effort turns into a little heat. The push is not lost; it is spent on the narrow section. With two narrow sections in a row, each takes a share, and by the end of the loop the push is used up.",
                      .concept(.waterSeries),
                      remember: "Narrow sections use up the push."),
                scene("In a circuit: the resistor",
                      "Anything that makes it harder for current to pass has resistance. A resistor is a part made to have a chosen amount of it. Lamp filaments and heater wires are resistors too: the push spent on them comes out as light and heat.",
                      .circuit(DemoCircuits.with(DemoCircuits.series, [
                          keyframe("Two resistors in the loop: two narrow sections.", .elements(["R1", "R2"])),
                          keyframe("R2 is the narrower one, 220 Ω against 100 Ω, so it takes the bigger share of the push.", .elements(["R2"])),
                          keyframe("The same current squeezes through both.", .flow),
                      ], loop: 12))),
                scene("The ohm",
                      "Resistance is measured in ohms, written Ω. A short thick wire has almost none. A lamp has a few hundred; a resistor inside a radio may have thousands, written kΩ. More ohms means a narrower pipe: less flow for the same push.",
                      analogy: [
                          ("Narrow or clogged pipe", "Resistor"),
                          ("How narrow it is", "Resistance (ohms, Ω)"),
                          ("Wide, smooth pipe", "Plain wire (almost no resistance)"),
                      ],
                      remember: "Resistance is how much a part fights the flow. More ohms, less current for the same voltage."),
            ], quiz: [
                question("Two pipes get the same push. The narrow one…", ["carries more water", "carries less water", "carries the same amount", "carries none"], answer: 1, "A narrow pipe resists the flow: less gets through for the same push."),
                question("Resistance is measured in…", ["amperes", "volts", "ohms", "watts"], answer: 2, "Ohms, written Ω."),
                question("A lamp glows because…", ["it stores electricity", "the push spent on its resistance comes out as heat and light", "it makes its own current", "it has no resistance"], answer: 1, "The filament is a resistor; the push spent on it turns into heat and light."),
                question("A wide, smooth pipe is like…", ["a resistor", "a battery", "a plain wire", "a switch"], answer: 2, "A wire has almost no resistance: the flow passes with hardly any push spent."),
            ]),

            Lesson(id: "m0l5", title: "Push, flow and pipe together", minutes: 6, scenes: [
                scene("Turn the pump up",
                      "Keep the same pipe and slowly turn the pump up. The gauge climbs and the flow climbs with it, in step. Double the push, double the flow. That is the whole relationship between pressure and flow for one pipe.",
                      .concept(.waterOhm)),
                scene("Change the pipe instead",
                      "Now keep the push the same and swap in a narrower pipe. The flow drops. A pipe with twice the resistance passes half the flow. So the flow goes up with the push and down with the resistance.",
                      .concept(.waterNarrowPipe),
                      remember: "Flow = push ÷ resistance."),
                scene("Now in electrical words",
                      "Current goes up with voltage and down with resistance. Written with the usual letters, I for current, V for voltage and R for resistance, that is the first formula of the course. It is called Ohm's law, and it says nothing more than the water did.",
                      formula: "I = \\frac{V}{R}", text: "I = V / R",
                      analogy: [
                          ("Push (pressure)", "V, voltage, in volts"),
                          ("Flow (buckets per second)", "I, current, in amperes"),
                          ("Narrowness of the pipe", "R, resistance, in ohms"),
                      ]),
                scene("One example",
                      "A 12 V battery pushes through a 4 Ω resistor. Current = 12 ÷ 4 = 3 A. Turn the battery up to 24 V and you get 6 A. Keep 24 V but swap in an 8 Ω resistor and you are back to 3 A. Try to predict each number before it appears.",
                      .circuit(DemoCircuits.with(DemoCircuits.single, [
                          keyframe("12 V of push…", .elements(["V1"])),
                          keyframe("… through 4 Ω of resistance…", .elements(["R1"])),
                          keyframe("… gives 12 ÷ 4 = 3 A of flow.", .flow),
                      ], loop: 12))),
                scene("The map so far",
                      "This is the whole foundation. Everything later in the course is built from these four ideas and the one relationship between them.",
                      analogy: [
                          ("Pump", "Battery, or any source"),
                          ("Pressure", "Voltage (V)"),
                          ("Flow rate", "Current (A)"),
                          ("Narrow pipe", "Resistance (Ω)"),
                          ("Flow = push ÷ narrowness", "I = V / R"),
                      ],
                      remember: "Voltage pushes, resistance resists, current is what results."),
            ], quiz: [
                question("For the same resistor, doubling the voltage…", ["halves the current", "doubles the current", "leaves the current unchanged", "stops the current"], answer: 1, "Double the push, double the flow: I = V / R."),
                question("For the same voltage, doubling the resistance…", ["halves the current", "doubles the current", "leaves the current unchanged", "stops the current"], answer: 0, "Twice as narrow a pipe passes half the flow."),
                question("A 9 V battery pushes through a 3 Ω resistor. The current is…", ["27 A", "12 A", "3 A", "0.33 A"], answer: 2, "I = V / R = 9 ÷ 3 = 3 A."),
                question("Voltage is the ___, current is the ___, resistance is the ___.", ["flow, push, pipe", "push, flow, narrow pipe", "pipe, push, flow", "flow, pipe, push"], answer: 1, "Voltage pushes, current flows, resistance is the narrow pipe that fights the flow."),
            ]),
        ]
    )
}
