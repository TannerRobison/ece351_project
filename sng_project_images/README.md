# Image processing using your ECE351 project

This package connects your uploaded `sng_controller.sv` and `sng_experiment.sv`
to the physical UART on a Nexys 4 DDR, and supplies an image host script.
No prebuilt bitstream is included. Build in full Vivado (not Lab Edition).

## What is reused

Unchanged copies of your `sng_controller.sv`, `sng_experiment.sv`, `sng.sv`,
`sng_lut.sv`, `sng_comparator.sv`, `lfsr_shuffle.sv`, and all three LUT files.
The earlier standalone demo's `demo_uart.sv` is also reused unchanged.
The new `nexys4ddr_image_top.sv` replaces switches/buttons as the experiment
input and connects serial bytes to your existing experiment module.
Your original switch/button top and its bitstream are not needed in this build.
Keep your original project available; programming a different bitstream changes
which design runs on the board.

## 1. Extract

Extract the entire folder into a local Windows path, for example:
`C:/Users/yourname/Downloads/sng_project_images`.
Keep all included source files and LUT files together.
You may copy this folder into your team repository as a self-contained integration.
These are snapshots of the uploaded files; future team RTL changes should be
carried into this folder deliberately and retested.

## 2. Build

In a fresh full Vivado session, enter this in the Tcl Console (adjust the path):

```tcl
source {C:/Users/yourname/Downloads/sng_project_images/build.tcl}
```

The script targets Nexys 4 DDR, `xc7a100tcsg324-1`, and builds
`nexys4ddr_image_top.bit`. This is NOT a Basys 3 build.
Review `timing_summary.txt` and `drc_report.txt`; resolve timing failures or
critical warnings before relying on hardware results.

The constraints use the same clock/reset/UART pins as the previously supplied
standalone demo: E3 clock, C12 active-low CPU reset, C4 RX, D4 TX.
Do not include the old switch-demo constraints in this separate build.

## 3. Program

Connect the Nexys 4 DDR using its PROG/UART data cable.
Hardware Manager -> Open Target -> Auto Connect -> Program Device.
Select the NEW `nexys4ddr_image_top.bit` in this extracted folder.
Press and release CPU_RESET before starting Python.
The image appears on the computer; this top does not drive the LEDs or display.

## 4. Install packages and identify the port

Open PowerShell in the extracted folder:

```powershell
py -m pip install -r requirements.txt
py -m serial.tools.list_ports -v
```

Use the board's COM number instead of COM5 below. Close other serial terminals.
On Mac, use `python3` instead of `py`, and the board's `/dev/cu...` device path.

## 5. Verify communication BEFORE processing images

```powershell
py project_images.py --port COM5 --test
```

This sends four experiments (L = 0, 1, 19, 65535) and checks all five returned
counts against a software model of your uploaded SNG implementation. Expect PASS.
The full-period counts should be `(37924, 56045, 32682, 32465, 46939)`.
If it times out, verify the new bitstream and port, reset the board, and rerun.
If counts differ, do not treat image results as verified.

## 6. Brightness study

Built-in grayscale ramp, initially at 32 x 32:

```powershell
py project_images.py --port COM5 --mode brightness --gain 0.35 --lengths 256 1024 4096 --out brightness_results
```

Your own image:

```powershell
py project_images.py --port COM5 --image "C:/path/photo.jpg" --gain 0.35 --lengths 256 1024 4096 65535 --out photo_results
```

Open `comparison.png` in the output folder to see the input, expected result,
and FPGA results labeled by stream length. The script saves files; it does not
launch an image viewer automatically.

## 7. Blending study

```powershell
py project_images.py --port COM5 --mode blend --image "C:/path/first.jpg" --image-b "C:/path/second.jpg" --lengths 256 1024 4096 --out blend_results
```

Corresponding pixels are averaged, `(A+B)/2`. The first photo is resized to fit
within 32 x 32 by default, retaining aspect ratio; the second is resized to the
first's dimensions, which may stretch it. Prefer similarly composed photos.
Without image paths, generated ramps demonstrate the operation.

For a mask, use blend code as a starting point but take multiplication count:
this package's supported commands are brightness and blend, not a mask mode.

## 8. Larger images and metrics

Add `--size 128` for the proposal's suggested size once the smaller image works.
`L` is restricted to 1..65535 for images because the existing controller stores
it in 16 bits. It cannot represent 65536. The test command also checks L=0.
At 115200 baud and 8N1, each request/response transfers 25 bytes, requiring at
least 2.17 ms per pixel, plus L/100 MHz and host/USB overhead. A 128 x 128 pass
therefore needs at least about 36 seconds at short L, or 46 seconds at full L;
actual elapsed time may be appreciably longer. Multiple L values take multiple
passes. The earlier ten-second estimate in the proposal is not achievable with
this request-per-pixel packet format at 115200 baud.

Outputs:
- `comparison.png`: all panels, enlarged for viewing.
- `fpga_L*.png`: reconstructed 8-bit images (or `model_L*.png` in software mode).
- `metrics.csv`: operation, L, dimensions, elapsed seconds, and three PSNR values.
- `counts_L*.npy`: raw five-count arrays for each pixel.
- `reference_float.npy`: exact floating-point target before display rounding.

`psnr_float_dB` compares 255*C/L before rounding to the desired floating-point
operation. `psnr_display_dB` evaluates the rounded displayed image.
`psnr_encoded_reference_dB` uses the achievable LUT probabilities and actual
select probability to help separate input quantization from arithmetic error.
Higher PSNR is better; infinite PSNR means zero MSE. Improvement with L need not
be monotonic for every picture because of deterministic streams and correlation.

The script reloads fixed, separate seeds for every pixel and every L. This makes
runs reproducible and compares prefixes of the same streams. Equal input values
produce equal outputs, so finite-stream error may appear as bands rather than
random spatial noise. Different seeds and shuffles reduce some correlations but
do not guarantee independence. The S LUT code closest to 0.5 is selected
programmatically; its actual probability is about 0.498695, causing a small
blend weighting bias relative to the ideal 50/50 reference.

## Optional software-only check

```powershell
py project_images.py --model --mode brightness --lengths 256 1024 4096 --out model_results
py project_images.py --model --mode blend --out model_blend_results
py -m unittest test_host.py
```

MODEL images are software reference results, not FPGA measurements. Do not label
them as hardware output in the report. The model follows the uploaded Fibonacci
LFSR step and shuffle wiring, not the old standalone demo's Galois LFSRs.

## Protocol and connection

Request: 0xA5 + seven little-endian 16-bit words:
A code, B code, S code, A seed, B seed, S seed, L. Total 15 bytes.
Response: five little-endian 16-bit counts: A, B, S, AND, MUX. Total 10 bytes.
This differs from the old `image_demo.py` five-byte request and two-byte response.
Use this script and new top together.

The new top connects controller tx_valid to UART tx_start only while UART is
idle. The controller and UART accept the same byte on the same clock edge.
UART busy then holds off the next byte until transmission finishes.
Receive bytes feed the controller directly. The host waits for the complete
response before sending another request. There is no checksum/response framing;
a timeout aborts the host operation, and the user must reset before retrying.

## Validation status

Verified here: Python syntax; packet bytes and little-endian fields; fragmented
response assembly; invalid-count rejection; model agreement with counts recorded
in the supplied design log; small brightness and blend runs, PNG/CSV generation.
Original SNG/controller/LUT sources are copied unchanged.
No Verilog simulator, Vivado, or physical FPGA was available here. The new top
has been inspected but has NOT been RTL-simulated, synthesized, timing-verified,
or tested on the board. The build and `--test` steps above are still required.
