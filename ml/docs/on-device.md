# On-device integration: Core ML contract and the Swift assembler

## Model contract (`tracer/export_coreml.py`)

- Input `image`: RGB, `input_size` × `input_size` (metadata key), the image letterboxed on a
  paper-coloured background (median border colour), scaled 1/255 (Core ML `ImageType`); ImageNet
  normalisation happens inside the model.
- Outputs, all `[1, C, S/4, S/4]` float:
  `symbol_heat` (13, sigmoid; order in metadata `classes`), `symbol_size` (2: box w, h in stride
  units), `symbol_off` (2: sub-cell offset), `polarity` (4, softmax; `right, up, left, down`),
  `wire`, `junction`, `terminal` (1 each, sigmoid).
- Latency budget: MobileNetV3-Large at 640 px is ~15–40 ms on the Neural Engine (estimate; measure
  with Xcode's Core ML performance report).

## Assembler steps (`tracer/assemble.py` is the reference; port 1:1)

1. **Decode symbols**: 3×3 local maxima of `symbol_heat` above 0.3 → centre `(x + off_x, y + off_y) * 4`,
   box from `symbol_size * 4`, class = channel, polarity = argmax of `polarity` at that cell.
   Drop a peak whose box overlaps an already-kept box with IoU > 0.55.
2. **Axis and terminals**: the current axis is horizontal iff polarity ∈ {right, left}. The two
   terminals are the box-edge midpoints on that axis, each snapped along the edge to the nearest
   `terminal` peak (> 0.3) within ~10 px (at 640). If the polarity softmax is unsure (< 0.6), take
   the axis whose edge midpoints carry more `terminal` heat.
3. **Wire components**: `wire` upsampled to `S × S`, threshold 0.5, morphological closing radius 1,
   every symbol box (plus 1.5 px) set to 0, 8-connected components, components under 12 px dropped.
4. **Attach**: each terminal takes the majority component label in growing windows (3, 6, 10, 16,
   24 px at 640) just outside its box edge. Terminals that find nothing get a fresh node; two such
   terminals within 24 px share it (symbols touching directly).
5. **Crossovers**: the four arm labels around a `crossover` box are unioned left↔right and
   top↔bottom. **Grounds**: the label found above a `ground` box becomes node `0`; several grounds
   are unioned.
6. **Nodes**: union-find roots, named `0` for ground and `a, b, c, …` by mean x of their pixels.
   A one-letter OCR string next to a wire renames that node (unique letters only; the others are
   renumbered to stay unique).
7. **Text** (Vision `VNRecognizeTextRequest`): parse each string (`textparse.py` rules: value with
   unit and family, name like `R1`, question sentence, node letter). Values and names are assigned
   globally, closest pairs first, one value and one name per symbol; a unit that does not fit the
   symbol's family costs 3× distance. Unassigned "other" strings join the question.
8. **JSON**: components with node ids (positive/negative or from/to for sources; the arrow head is
   `to`), normalised boxes, orientation, `node_points` (junction peak inside the node else the
   pixel nearest its centroid), `unknowns` from `parse_question`, `unsupported` for `other`
   symbols, and `confidence` = min symbol score × share of attached terminals × 0.6 if values are
   missing × 0.5 if validation fails.
9. **Escalation**: on the phone, `confidence` (optionally × agreement between two scales, see
   `tracer/infer.py`) decides whether to accept locally or send the photo to the server.

## Validation before shipping the port

Run `tracer/evaluate.py` on synthetic held-out data with the Python assembler, then feed the same
Core ML outputs (dump `maps` from `Tracer.maps`) through the Swift port and require identical
netlists on at least 100 images before wiring it into `CircuitSolverService`.
