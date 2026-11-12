## 2026-10-29: Python memristor switching model and LUT generation

**Author:** Ren Cadua

Developed with ChatGPT assistance for Python code, explanations, and this log.

### Goal

Model the voltage-dependent switching probability of a memristor and generate three lookup tables for the FPGA stochastic number generators. Each table stores integer thresholds that the FPGA compares with LFSR values to generate stochastic bitstreams.

### Files added

| File | Purpose |
|---|---|
| `switchingmodel.py` | Calculates switching probabilities and exports LUT thresholds |
| `lut_a.mem` | Thresholds for operand A's SNG |
| `lut_b.mem` | Thresholds for operand B's SNG |
| `lut_s.mem` | Thresholds for the scaled adder's select SNG |

### Switching model

The Python script evaluates:

tau(V) = tau_0 * exp(-V / V_0)

P_switch(V) = 1 - exp(-delta_t / tau(V))

The nominal model parameters are:

| Parameter | Value | Meaning |
|---|---|---|
| tau_0 | 269000 seconds | Switching-time scale |
| V_0 | 0.163 V | Voltage-dependence parameter |
| delta_t | 0.001 seconds | Modeled pulse duration |

NumPy evaluates the model for all voltage settings. The code uses `-np.expm1(-delta_t / tau)` to calculate the switching probability accurately, including small probabilities.

### Design decisions

- **2048 voltage settings.** Use evenly spaced voltages from 1.4 V through 4.0 V. Each setting corresponds to one LUT address, from 0 through 2047, requiring an 11-bit address.

- **16-bit thresholds.** Convert each probability using `T = round(P_switch * 65535)`. The thresholds range from 0 through 65535.

- **Three modeled devices.** Use slightly different parameters for A, B, and S to represent device-to-device variation. These differences are selected modeling assumptions, not measured device variations.

| Device | tau_0 (seconds) | V_0 (volts) | Purpose |
|---|---:|---:|---|
| A | 269000 | 0.16300 | Operand A |
| B | 274380 | 0.16137 | Operand B |
| S | 263620 | 0.16463 | Adder select |

- **Hexadecimal file format.** Write each threshold as four hexadecimal digits on its own line. Each file contains 2048 entries, with no header. The first line corresponds to address 0.

- **Match the FPGA comparator.** The threshold scaling assumes a maximal-length 16-bit LFSR covering nonzero values 1 through 65535 and a comparator that outputs 1 when R <= T. Over a full period, the fraction of ones is T / 65535.

- **Identify the select setting.** Find the LUT address whose encoded probability is closest to 0.5. Device S uses this setting to select approximately equally between A and B in the MUX-based scaled adder.

- **Keep the output simple.** Retain the three required `.mem` exports and display the switching curves. Optional CSV exports and automatic plot saving are not required for FPGA operation.

### Generation flow

1. Create the array of 2048 voltage values.
2. Calculate switching probabilities using each device's parameters.
3. Multiply the probabilities by 65535 and round to integer thresholds.
4. Export the thresholds to the corresponding `.mem` file.
5. Identify the entry closest to probability 0.5.
6. Display the switching curves for model inspection.

The LUTs store thresholds, not bitstreams. The FPGA generates the bitstreams using its LFSRs and comparators.

### Results

The script produced the LUT files and displayed the switching curves.

The reported device S setting closest to probability 0.5 was:

| Quantity | Value |
|---|---:|
| Voltage code | 1363 |
| Modeled voltage | Approximately 3.131216 V |
| Threshold | 32682 |
| Encoded probability | Approximately 0.498695 |

The encoded probability is close to, but not exactly, 0.5 because the voltage settings and integer thresholds are discrete.

These results describe the Python-generated model outputs. They do not establish successful FPGA loading or hardware operation.

### Model limitations

- The modeled pulse duration of 1 ms is not the FPGA clock period.
- The model's reported fitting range is approximately 2.6–3.6 V. Values outside that range are extrapolations.
- This implementation models memristor behavior without using a physical memristor.
- Different device parameters do not by themselves make the generated bitstreams independent.

### Problems encountered

After `switchingmodel.py` was moved, VS Code attempted to run the file from its old location and returned a “No such file or directory” error.

The identified fix was to open the repository folder in VS Code and reopen the Python file from its new location. The issue concerned the file path rather than the switching equations.

