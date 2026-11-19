# Nexys 4 DDR FPGA image demo

The FPGA multiplies each grayscale pixel by a brightness gain with two
stochastic number generators and an AND gate. Python sends the lookup codes,
receives the FPGA's measured count, and saves a side-by-side PNG. The default
gain is 0.35, so white becomes about 89 on the 0–255 scale.

## 1. Extract and copy the lookup tables

1. Extract this ZIP on the Windows computer that runs Vivado. Use a local
   path if available, such as `C:/Users/yourname/Downloads/sng_image_demo`.
2. From your original project's `Python_Code` folder, copy **lut_a.mem**
   and **lut_b.mem** into the extracted folder beside **build.tcl**.
   Keep their original names and check that neither file is empty.

This is a separate image-demo project for the Nexys 4 DDR (XC7A100T-CSG324-1).
It uses your original A/B thresholds and implements the same stochastic AND
operation with its own LFSRs. The PC sends both A and B codes, so the board's
switches and seven-segment display aren't needed for this demo. To return to
your original switch demo, program the original `nexys4ddr_top.bit` again.

## 2. Build and program

1. Open regular **Vivado** with Artix-7 device support installed. Use a fresh
   Vivado session or close the current project before building.
2. In the **Tcl Console**, type the command below. Replace the example path
   with the actual path to the extracted folder. Use braces and forward slashes.

   ```tcl
   source {C:/Users/yourname/Downloads/sng_image_demo/build.tcl}
   ```

3. Wait for **PROGRAM THIS FILE** in the console. It should point to
   **image_top.bit** in the extracted folder.
4. Power the board and connect the **PROG/UART** Micro-USB data cable.
   In Hardware Manager open **Open Target → Auto Connect → Program Device**.
   Choose the new **image_top.bit** and click **Program**. Press and release
   the red **CPU_RESET** button once before the first serial test.

## 3. Install Python packages and find the serial port

Open PowerShell in the extracted folder. Run these commands. If your Python
installation uses `python` instead of `py`, substitute it in each command.

```powershell
py -m pip install -r requirements.txt
py -m serial.tools.list_ports -v
```

Use the Nexys board's COM number in the next commands. You can also check
**Device Manager → Ports (COM & LPT)**. If several ports appear, compare
the list before and after unplugging the board and reconnecting it. If you
unplug the cable and the board loses power, program it again.

## 4. Test one pixel

```powershell
py image_demo.py --port COM5 --test
```

Use your COM number in place of COM5. The script looks up the B voltage code
closest to gain 0.35 and sends it with A code 1200. If A's lookup value is
3490 as in your board guide, expect an ideal count near 4710 decimal
(1266 hex), with a measured value near it and an output pixel around 18.
The measured count may differ from your old board demo because this
image demo uses its own LFSR pair.

## 5. Show the image

For a built-in grayscale ramp, run:

```powershell
py image_demo.py --port COM5
```

For your own photo, run:

```powershell
py image_demo.py --port COM5 --image "C:/path/to/photo.jpg" --gain 0.35
```

Open **comparison.png** from the current folder. The left panel is the
grayscale input and the right is the FPGA result. **fpga_output.png**
contains just the processed image. The script keeps the aspect ratio and
fits an input photo within 32 × 32 pixels for this demo.

## Data path and troubleshooting

- Python maps an 8-bit pixel to the A code with the closest threshold.
  It maps gain to a B code using B's table.
- UART runs at 115200 baud, 8N1. A request is byte A5 followed by A low 7
  bits, A high 4 bits, B low 7 bits, B high 4 bits. The FPGA returns its
  16-bit AND count as two bytes, low first. The PC waits for those bytes
  before sending the next request.
- The FPGA reads its two ROMs, counts 1s in 65,535 AND samples, and sends
  the count. Python converts that count to an 8-bit pixel.
- On timeout, confirm the correct COM port, close other serial programs,
  check that Hardware Manager programmed **image_top.bit**, and press
  CPU_RESET before retrying.
- If a build reports a missing LUT, check that both .mem files sit next to
  build.tcl. If it reports a missing part, check Vivado's Artix-7 support.
- Digilent board constraints:
  https://github.com/Digilent/digilent-xdc/blob/master/Nexys-4-DDR-Master.xdc
