| setting | correct [95% CI] | topology | structure | answers | kind acc | mAP@0.5 | coverage@95% prec. | Brier |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| tracer, GT text | 0.887 [0.85, 0.92] | 0.920 | 0.927 | 0.900 | 0.999 | 0.9665 | 0.133 | 0.1629 |
| + three-scale majority (TTA) | 0.883 [0.8433, 0.9167] | 0.923 | 0.930 | 0.903 | 1.000 | 0.9801 | 0.143 | 0.1665 |
| tracer, no text | 0.000 [0.0, 0.0] | 0.000 | 0.927 | 0.000 | 0.999 | 0.9665 |  | 0.047 |
| ablation: unit-based kinds on (gated on detector uncertainty) | 0.850 [0.8067, 0.8867] | 0.887 | 0.893 | 0.867 | 0.992 | 0.9665 | 0.067 | 0.166 |
| ablation: box removal, closing 1, wire 0.5 | 0.883 [0.8467, 0.9167] | 0.917 | 0.923 | 0.897 | 0.999 | 0.9665 | 0.133 | 0.1626 |
| calibrated confidence (fit on val) | 0.887 [0.85, 0.92] | 0.920 | 0.927 | 0.900 | 0.999 | 0.9665 | 0.07 | 0.1002 |
