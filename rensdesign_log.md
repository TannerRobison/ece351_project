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


0.40
×
255
=
102
L


## 2026-11-18: Standalone FPGA image brightness demonstration

**Author:** Ren Cadua

Developed with ChatGPT assistance for Python code, SystemVerilog integration, troubleshooting, explanations, and this log.

### Goal

Demonstrate stochastic multiplication with an image by using the Nexys 4 DDR FPGA to scale grayscale pixel brightness. This first demonstration used a separate FPGA design to establish image loading, UART communication, arithmetic, and image reconstruction.

### Files added

| File | Purpose |
|---|---|
| `image_demo.py` | Loads an image, maps pixels to LUT codes, sends requests, and reconstructs the output image |
| `image_top.sv` | Standalone FPGA design containing two SNGs, an AND multiplier, counters, and request control |
| `demo_uart.sv` | UART receiver and transmitter for communication with the computer |
| `image_demo.xdc` | Nexys 4 DDR clock, reset, and UART pin constraints |
| `build.tcl` | Creates the Vivado project and generates the bitstream |
| `requirements.txt` | Lists Python package dependencies |
| `README.md` | Documents setup and operation |

Existing `lut_a.mem` and `lut_b.mem` files supplied the thresholds. Building the design generated `image_top.bit`.

### Image-processing operation

Each grayscale pixel contains an integer brightness from 0 to 255. Python normalizes the pixel to a probability:

P_A = input_pixel / 255

The selected brightness factor supplies the second probability:

P_B = gain

With sufficiently independent input streams, the FPGA's AND output represents approximately:

P_output = P_A * P_B

The FPGA counts output ones over L cycles. Python reconstructs the output pixel using:

output_pixel = round(255 * output_count / L)

The pixel is already one operand of the multiplication. The factor of 255 converts the result back to image units; the pixel is not multiplied into the result again.

### Design decisions

- **Grayscale images.** Use one intensity value per pixel to keep the demonstration simple.
- **Small initial image.** Fit photos within 32 x 32 pixels while preserving aspect ratio to reduce communication time.
- **Selectable brightness factor.** Use a default gain of 0.35, with values from 0 to 1. This supports darkening or approximately preserving the original image.
- **Use the existing LUT data.** Select the A and B LUT entries whose thresholds most closely represent the requested pixel probability and gain.
- **Fixed stream length.** Count 65,535 samples for every pixel in this initial design.
- **UART communication.** Use 115200 baud, eight data bits, no parity, and one stop bit.
- **Separate demonstration hardware.** Use the standalone design's own LFSRs and control logic. This version did not use the main project's controller or shuffled SNG modules.

### Implementation flow

1. Load a photo or generate a grayscale ramp in Python.
2. Convert each pixel into the corresponding A LUT code.
3. Convert the chosen gain into a B LUT code.
4. Send a five-byte request: start byte 0xA5 followed by the two codes, each split into low seven bits and high four bits.
5. Generate the two stochastic streams and multiply them using an AND gate.
6. Count output ones over 65,535 cycles.
7. Return the 16-bit count as two bytes, low byte first.
8. Convert the count into an output pixel and repeat for the image.
9. Save the processed image and a side-by-side comparison.

### Results

The standalone demonstration was reported working on the board. Python processed the image rows and generated the image output.

| Output | Purpose |
|---|---|
| `fpga_output.png` | Processed grayscale image |
| `comparison.png` | Original image and FPGA result shown side by side |

This demonstrated the computer-to-FPGA-to-computer processing path. No numerical PSNR result was recorded for this initial version.

### Limitations

- Supported brightness multiplication only; it did not implement image blending.
- Used a fixed stream length, so it did not demonstrate progressive precision across different L values.
- Did not calculate PSNR against a floating-point reference.
- Used different LFSR logic from the main project, so its exact counts should not be assumed to match the main project's counts.

### Problems encountered

Setup involved locating the generated bitstream and using a local Windows folder for the Vivado build. Network/UNC paths caused difficulties during the setup process. The working demonstration required programming `image_top.bit` and selecting the board's correct serial port.

## Project integration: Image processing using the existing SNG controller

**Author:** Ren Cadua

**Date:** 11/25/2026.

Developed with ChatGPT assistance for the UART wrapper, Python image-processing code, build setup, testing support, explanations, and this log.

### Goal

Integrate image processing with the project's existing controller, three SNGs, and stochastic arithmetic. Extend the standalone demonstration to support variable stream lengths, image blending, and PSNR comparisons against floating-point reference results.

### Files added

| File | Purpose |
|---|---|
| `nexys4ddr_image_top.sv` | Connects the board clock/reset and UART to the existing experiment module |
| `project_images.py` | Sends project-format requests, reconstructs images, and calculates PSNR |
| `image_project.xdc` | Provides constraints for the new image-processing top module |
| `build.tcl` | Builds the integrated image design in Vivado |
| `test_host.py` | Checks Python packet handling and software-model regression results |
| `requirements.txt` | Lists NumPy, Pillow, and pyserial dependencies |
| `README.md` | Documents build, programming, experiments, outputs, and limitations |

### Existing project components reused

| File | Role |
|---|---|
| `sng_controller.sv` | Receives settings, loads SNGs, counts L samples, and reports results |
| `sng_experiment.sv` | Connects the controller to three SNGs, the AND gate, and the MUX |
| `sng.sv` | Combines each LUT, shuffled LFSR, and comparator |
| `sng_lut.sv` | Reads and holds the selected threshold |
| `lfsr_shuffle.sv` | Generates pseudorandom values and applies the project's bit shuffle |
| `sng_comparator.sv` | Outputs a stochastic bit when R <= T |
| `lut_a.mem`, `lut_b.mem`, `lut_s.mem` | Supply the three devices' thresholds |
| `demo_uart.sv` | Provides the serial receiver and transmitter from the earlier demo |

These modules and LUTs were copied unchanged into the integration package. The original switch/button top remained a separate demonstration.

### Design decisions

- **Reuse the project datapath.** The new top instantiates `sng_experiment` instead of recreating the SNG arithmetic.
- **Match the existing controller protocol.** Replace the standalone demo's packet format with the controller's 15-byte request and 10-byte response.
- **Coordinate UART transmission.** Allow the controller to advance its response byte only when the UART can accept that byte.
- **Variable stream length.** Send L as a 16-bit value. Image runs use 1 through 65,535 samples; L = 0 is reserved here for a communication test.
- **Reproducible seeds.** Reload A = 0xACE1, B = 0x1D2C, and S = 0x5EED for each pixel. Runs at different lengths compare prefixes of the same sequences.
- **Two image operations.** Use the multiplication count for brightness scaling and the scaled-add count for blending.
- **Select probability near 0.5.** Choose the S LUT entry closest to 0.5 for approximately equal blending.
- **Measured image quality.** Compare FPGA-derived pixels with the desired floating-point operation using PSNR.

### Communication format

| Direction | Contents |
|---|---|
| Computer to FPGA | 0xA5 followed by seven 16-bit words: code A, code B, code S, seed A, seed B, seed S, L |
| FPGA to computer | Five 16-bit counts: A, B, S, multiplication, scaled addition |

All 16-bit words are transmitted low byte first. Python waits for all ten response bytes before sending another request.

### Implementation flow

1. Read the three LUT files and load or generate the input image.
2. Map input pixel probabilities to the closest LUT codes.
3. Send the voltage codes, seeds, and stream length to the FPGA.
4. The controller moves through IDLE, RECEIVE, LOAD, RUN, and REPORT.
5. The SNGs produce streams and the controller counts all five outputs over L samples.
6. Python receives the counts and selects the relevant arithmetic result.
7. Reconstruct each pixel using `round(255 * count / L)`.
8. Repeat at selected stream lengths, such as 256, 1024, and 4096.
9. Save comparison images, raw counts, and PSNR measurements.

### Arithmetic and image interpretation

For brightness scaling:

expected_pixel = input_pixel * gain

For approximately equal image blending:

expected_pixel = (pixel_A + pixel_B) / 2

As an illustrative multiplication, an input pixel of 102 represents 102/255 = 0.40. A gain of 0.35 gives an ideal normalized output of 0.14 and an ideal image value of approximately 36. The actual displayed FPGA pixel comes from its measured count, not from this expected calculation.

### Verification and results

The initial Vivado build failed. After moving the package to a local Windows folder, the build/programming sequence proceeded and the board was reset. The UART test was then run, and PASS was reported.

The test checks all five received counts against the software reference at A code 1370, B code 1450, S code 1363, and the fixed seeds listed above:

| L | A count | B count | S count | Multiply count | Scaled-add count |
|---:|---:|---:|---:|---:|---:|
| 0 | 0 | 0 | 0 | 0 | 0 |
| 1 | 0 | 1 | 1 | 0 | 1 |
| 19 | 11 | 16 | 5 | 9 | 13 |
| 65535 | 37924 | 56045 | 32682 | 32465 | 46939 |

These are the expected values checked by the supplied test. The reported PASS indicates agreement for those cases; a hardware transcript was not attached to this log.

The brightness experiment and comparison display were discussed after the communication test. Actual image-run PSNR values were not supplied here, so no numerical image-quality claims are recorded.

| Generated output | Purpose |
|---|---|
| `comparison.png` | Input, expected result, and results at different L values |
| `fpga_L*.png` | Reconstructed FPGA image for each stream length |
| `metrics.csv` | PSNR, elapsed time, operation, and image dimensions |
| `counts_L*.npy` | Raw five-count results for each pixel |
| `reference_float.npy` | Floating-point reference before display rounding |

The package includes blending, but a completed board blending run was not reported in this session. Software-only model images are labeled MODEL and are not hardware measurements.

### Model and implementation limitations

- The LUT discretizes desired probabilities, so input encoding introduces error.
- The S stream probability is approximately 0.498695 rather than exactly 0.5, producing a small blending bias.
- Fixed seeds make experiments reproducible but can cause repeated brightness errors for identical input pixels.
- Longer streams generally improve accuracy, but PSNR is not guaranteed to increase at every tested length.
- UART requests are sent per pixel, so larger images take longer. The default is 32 x 32; `--size 128` supports the proposal's larger case study.
- Passing the communication test does not replace checking Vivado timing reports or evaluating image quality across multiple inputs.

### Problems encountered

The first build reported `wait_on_runs failed due to earlier errors`, with synthesis failing while the project was under a school network/UNC path. No `runme.log` was found. The package was copied into a local folder under `%LOCALAPPDATA%`, the copied build directory was removed, and the script was rerun. The exact original failure cause was not established from a synthesis log.

Hardware programming required opening Hardware Manager, connecting to the Nexys FPGA, selecting the new `nexys4ddr_image_top.bit`, and pressing CPU_RESET. The Python script then used the board's serial port for the communication test.



