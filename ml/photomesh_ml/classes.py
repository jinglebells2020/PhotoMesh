"""Label vocabularies shared by the synthetic generator, the dataset converters and the tracer."""

# What the on-device tracer detects. The first nine are the app's component kinds; "ground" marks
# the reference node, "crossover" a wire hop, "text" a label, "other" any symbol the app cannot solve
# (diodes, transistors, AC sources ...) so it can be reported as unsupported.
TRACER_CLASSES = [
    "resistor", "voltage_source", "current_source", "battery", "capacitor", "inductor", "lamp",
    "switch_open", "switch_closed", "ground", "crossover", "text", "other",
]
CLASS_INDEX = {name: i for i, name in enumerate(TRACER_CLASSES)}

# Direction of a symbol's positive terminal (voltage source, battery) or arrow head (current source),
# as seen on screen. Non-polar symbols use "right" when horizontal and "up" when vertical.
POLARITY = ["right", "up", "left", "down"]
POLARITY_INDEX = {name: i for i, name in enumerate(POLARITY)}
POLAR_KINDS = {"voltage_source", "current_source", "battery"}

APP_KINDS = TRACER_CLASSES[:9]
