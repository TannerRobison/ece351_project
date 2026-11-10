# Board Guide: Running the SNG Demo on the Nexys 4 DDR

This guide covers how to get the design onto the board and how to control it
once it's running: what every switch, button, LED, and display digit does,
how to change modes, and some setups to try.

---

## Getting it onto the board

### Option 1: Program the prebuilt bitstream (fastest)

The latest build is committed at `bitstream/nexys4ddr_top.bit`, so you don't
need to build anything.

1. Plug the board in over USB (the `PROG/UART` port) and turn it on.
2. Open Vivado (or the smaller Vivado Lab Edition) and go to
   **Open Hardware Manager → Open Target → Auto Connect**.
3. Click **Program Device**, select `bitstream/nexys4ddr_top.bit`, and
   click **Program**.

The board starts running right away. Programming over JTAG doesn't survive a
power cycle, so you need to reprogram after turning the board off.

### Option 2: Build it yourself in Vivado

Use this if you changed any `.sv`, `.mem`, or `.xdc` file.

1. Open `vivavado/vivavado.xpr` in Vivado. The project points at the repo's
   sources with relative paths, so it works from any clone location.
2. Click **Generate Bitstream**. This runs synthesis and implementation
   first, and takes a few minutes.
   - The first build on a fresh clone may warn that the incremental synthesis
     checkpoint is missing. That's expected, since it's a generated file and
     isn't in git. It just does a full synthesis.
3. Program the result as in Option 1. It's at
   `vivavado/vivavado.runs/impl_1/nexys4ddr_top.bit`.

### Updating the committed bitstream

The build output in `vivavado/vivavado.runs/` is ignored by git. To share a
new build:

1. Copy it into `bitstream/`:
   ```
   cp vivavado/vivavado.runs/impl_1/nexys4ddr_top.bit bitstream/
   ```
2. Commit it **in the same commit** as the code change that produced it, so
   the bitstream always matches the sources next to it.

---

## What's running on the board

Three stochastic number generators (SNGs), each emulating a different
memristor:

| SNG | Stream | Role | Its code comes from |
|---|---|---|---|
| A | **a** | first operand | the switches, loaded with **BTNL** |
| B | **b** | second operand | the switches, loaded with **BTNR** |
| S | **s** | MUX select, always about 0.5 | fixed at code 1363 (T = `7FAA`) |

Two stochastic arithmetic circuits use those streams:

| Circuit | Stream | Computes |
|---|---|---|
| AND gate | **a·b** | multiply: P(a) × P(b) |
| 2:1 MUX | **mux** | scaled add: about (P(a) + P(b)) / 2 |

Each SNG turns an 11-bit **voltage code** (0–2047) into a 16-bit
**threshold T** from its own lookup table. Its output stream is 1 with
probability **T / 65535**. Each table is based on a slightly different
device, so the same code gives a slightly different T on A, B, and S.

---

## Controls at a glance

```
 SW15  SW14  SW13 SW12 SW11  SW10 ............................ SW0
 RUN   FAST  |-- DISPLAY --|  |------- VOLTAGE CODE (11 bits) ------|
             |   SELECT    |   (binary, SW10 = MSB, SW0 = LSB)

             BTNU
 BTNL        BTNC        BTNR          CPU_RESET (red button)
 load A    load A + B    load B        reset, reloads everything
             BTND
```

Switch **up = 1**, down = 0. BTNU and BTND aren't used.

### Switches

| Switch | Name | Down (0) | Up (1) |
|---|---|---|---|
| `SW15` | Run | paused (streams frozen) | running |
| `SW14` | Speed | **slow mode**: about 4 bits per second | **fast mode**: 100 million bits per second |
| `SW13:11` | Display select | see the table below | |
| `SW10:0` | Voltage code | binary code 0–2047, used when you press a load button | |

Display select (`SW13 SW12 SW11`):

| SW13 | SW12 | SW11 | Value | Display shows |
|---|---|---|---|---|
| 0 | 0 | 0 | 0 | **a** (SNG A) |
| 0 | 0 | 1 | 1 | **b** (SNG B) |
| 0 | 1 | 0 | 2 | **s** (SNG S) |
| 0 | 1 | 1 | 3 | **a·b** (AND multiply) |
| 1 | 0 | 0 | 4 | **mux** (scaled add) |
| 1 | 0 or 1 | 0 or 1 | 5–7 (anything above 4) | blank (`0000.0000`) |

### Buttons

| Button | Action |
|---|---|
| **BTNL** (left) | Load the code on `SW10:0` into **A** and restart A's random sequence |
| **BTNR** (right) | Load the code on `SW10:0` into **B** |
| **BTNC** (center) | Load the code into **A and B** at the same time |
| **CPU_RESET** | Reset. On release, A and B both load the current switch code and S loads its fixed code. The same thing happens automatically at power-up. |

- **The voltage code only takes effect when you press a button.** Moving
  `SW10:0` alone changes nothing, so you can set up the next code before
  loading it.
- **Any load clears the counters.** The display's measured count starts over.
- **Holding a button freezes that SNG's stream**, because it keeps reseeding
  every clock. The stream starts again when you let go. A quick press is all
  you need.

---

## Reading the outputs

### LEDs

| LED | Shows |
|---|---|
| `LD0` | a |
| `LD1` | b |
| `LD2` | s |
| `LD3` | a·b |
| `LD4` | mux |
| `LD5`–`LD15` | unused (off) |

- **Slow mode:** the LEDs blink once per bit, so you can watch individual
  bits.
  - `LD3` only lights when `LD0` **and** `LD1` are both on.
  - `LD4` copies `LD1` when `LD2` is on, and copies `LD0` when `LD2` is off.
- **Fast mode:** the bits change too fast to see, so each LED's
  **brightness** shows its probability. Dim means close to 0 and bright
  means close to 1.

### Seven-segment display

```
   E 8 5 0 . E 8 5 0
   \_____/   \_____/
   expected  measured
```

Both halves are **hex counts out of 65535 (`FFFF`)**, for the stream picked
by `SW13:11`.

- **Left half, expected:** what the count should be.
  - For a, b, and s, this is the SNG's threshold T.
  - For a·b and mux, it's computed from the three thresholds.
- **Right half, measured:** how many 1s actually came out.
  - **Fast mode:** the count over the last 65,535 bits. This refreshes about
    1,500 times a second, so the reading looks steady.
  - **Slow mode:** a running count since the last load. It goes up by one
    each time that stream's LED blinks on.

To turn a hex count into a probability, divide by `FFFF` (65535):

| Hex | Probability |
|---|---|
| `0000` | 0.00 |
| `1000` | 0.06 |
| `4000` | 0.25 |
| `8000` | 0.50 |
| `C000` | 0.75 |
| `FFFF` | 1.00 |

What to expect in fast mode:
- **a, b, s:** the two halves match **exactly**. 65,535 bits is one full LFSR
  period, so every random value appears exactly once.
- **a·b and mux:** the two halves are **close but not equal**. The gap is
  the stochastic computation error the project measures, usually a fraction
  of a percent.

---

## Modes

### Paused (`SW15` down)
Nothing moves. The LEDs and the display hold their values. Use this to set
up codes and loads before starting.

### Slow mode (`SW15` up, `SW14` down)
About 4 bits per second. Use this to watch the stochastic behavior bit by
bit and to see the AND and MUX logic work on the LEDs. The measured count
climbs slowly, so it isn't useful for accuracy.

### Fast mode (`SW15` up, `SW14` up)
One bit per clock (100 MHz). Use this to check accuracy on the display.
You can switch between slow and fast at any time without reloading.

---

## How to enter a voltage code

The code is 11-bit binary on `SW10:0`, with `SW10` as the most significant
bit. Some useful codes:

| Code | Switches (`SW10 → SW0`) | T on A | T on B | T on S |
|---|---|---|---|---|
| 0 | `000 0000 0000` | `0001` (~0) | `0001` | `0001` |
| 1000 | `011 1110 1000` | `0C16` (0.05) | `0DEE` | `0A85` |
| 1200 | `100 1011 0000` | `3490` (0.21) | `3C97` | `2DA3` |
| 1342 | `101 0011 1110` | `803A` (0.50) | `8FE7` | `71B3` |
| 1500 | `101 1101 1100` | `E850` (0.91) | `F165` | `DCE7` |
| 2047 | `111 1111 1111` | `FFFF` (1.0) | `FFFF` | `FFFF` |

Codes that put each device at a round probability:

| Target | A code | A switches | B code | B switches |
|---|---|---|---|---|
| 0.25 | 1229 | `100 1100 1101` | 1208 | `100 1011 1000` |
| 0.50 | 1342 | `101 0011 1110` | 1320 | `101 0010 1000` |
| 0.75 | 1431 | `101 1001 0111` | 1408 | `101 1000 0000` |

The same code gives a different T on each device: code 1342 is 0.50 on A,
0.56 on B, and 0.44 on S. That's the device-to-device variation the lookup
tables model.

---

## Things to try

### 1. Check that it works
1. Press **CPU_RESET**.
2. Turn `SW15` and `SW14` up (fast mode).
3. Step `SW13:11` through 0, 1, and 2. For each one, the two display halves
   should match exactly.

### 2. Multiply 0.5 × 0.5
1. Set `SW10:0` to **1342** (`101 0011 1110`) and press **BTNL** (A = 0.50).
2. Set `SW10:0` to **1320** (`101 0010 1000`) and press **BTNR** (B = 0.50).
3. Fast mode, display select **3** (a·b). Expected `4033` (0.25). Measured
   should be close.
4. Display select **4** (mux). Expected `8033` (0.50), the average of 0.5 and
   0.5.

### 3. Multiply 0.75 × 0.25
1. A code **1431** → **BTNL**. B code **1208** → **BTNR**.
2. a·b: expected `300E` (0.19 = 0.75 × 0.25).
3. mux: expected `8049` (0.50 = (0.75 + 0.25) / 2).

### 4. Watch the logic gates
1. Do one of the setups above, then turn `SW14` **down** (slow mode).
2. Watch `LD0`–`LD4`.
   - `LD3` (a·b) only lights when `LD0` and `LD1` are both on.
   - `LD4` (mux) follows `LD1` when `LD2` is lit and `LD0` when it isn't.

### 5. See device variation
1. Set a code and press **BTNC** to load it into both A and B.
2. Compare display select 0 and 1. The same code gives a different T on each
   device.

### 6. See brightness track probability
1. Fast mode. Load code **0** into A, and watch `LD0`: it's off.
2. Step through codes 1000 → 1200 → 1342 → 1500 → 2047, pressing BTNL each
   time. `LD0` gets brighter at each step.

---

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| The display shows `0000.0000` | `SW13:11` is set to 5–7. Set it to 0–4. |
| The display doesn't change when I move `SW10:0` | Expected: codes only load on a button press. Press BTNL, BTNR, or BTNC. |
| The measured count is stuck at 0 or not changing | `SW15` (run) is down, or a load button is being held. |
| The measured count doesn't match for a, b, s in fast mode | A load happened less than a millisecond ago (wait a moment), or the board isn't running the latest bitstream. |
| Every T reads `0000` no matter the code | The `.mem` files didn't make it into the bitstream. In Vivado, check the synthesis log for `Synth 8-4445` and check that `Python_Code/lut_a.mem`, `lut_b.mem`, and `lut_s.mem` are in the design sources. |
| Hardware Manager can't find the board | Check the USB cable is in the `PROG/UART` port and the power switch is on. On Linux, Digilent's cable drivers must be installed. |
| Nothing works at all | Press CPU_RESET, then reprogram from `bitstream/nexys4ddr_top.bit`. |
