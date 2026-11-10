# Tanner's Design Log

## 2026-11-09: Nexys 4 DDR top level, constraints, and 7-segment readout

Written with Claude Code (Opus 5.5).

### Goal

Put one SNG on the Digilent Nexys 4 DDR (`xc7a100tcsg324-1`) so it can be
demonstrated with only the board's switches, buttons, LEDs, and display. The
design itself (`sng.sv` and its submodules) is unchanged. Everything new is a
wrapper around it.

### Files added

| File | Purpose |
|---|---|
| `sv_code/nexys4ddr_top.sv` | Board top level: input synchronizers, slow tick, one `sng` instance, ones counter, output wiring |
| `sv_code/seven_seg.sv` | 8-digit hex driver for the seven-segment display |
| `constraints/nexys4ddr.xdc` | Pin locations, I/O standards, 100 MHz clock, false paths on async inputs |

### Board mapping

| Board | Signal | Notes |
|---|---|---|
| `SW[10:0]` | `code` | voltage code, indexes the LUT |
| `BTNC` | `load` | latch T and reseed the LFSR |
| `SW[15]` | run | 1 = LFSR steps, 0 = paused |
| `SW[14]` | speed | 0 = 4 Hz tick, 1 = one bit per 100 MHz clock |
| `CPU_RESETN` | `rst` | active-low button, inverted to the core's active-high reset |
| `LED[15:0]` | `threshold` | latched T |
| `LED16_R` | `stoch_bit` | registered before the pin |
| 7-seg, left 4 digits | T in hex | same value as the LEDs |
| 7-seg, right 4 digits | count of 1s in hex | see "Ones counter" below |
| `SW[13:11]` | unused | |

### Design decisions

- **One SNG (A settings).** `LUT_FILE`, `TAPS`, and `SHUFFLE_MAP` are top-level
  parameters, so B or S can be swapped in by changing the defaults.
- **Fixed seed.** `SEED = 16'hACE1` is a parameter. 16 switches aren't enough
  for an 11-bit code and a 16-bit seed.
- **Synchronizers.** Every button and switch goes through a 2-FF synchronizer
  (`ASYNC_REG`), and the XDC sets false paths on those inputs. The switch bus
  is synchronized bit by bit. That's fine because a held `load` relatches
  every cycle, so T settles on the final code.
- **No debounce on BTNC.** Holding `load` high is harmless, since it just
  reloads the same T and seed. As a side effect, the stream is frozen while
  the button is down and starts on release.
- **`en` = run AND (fast OR tick).** The slow tick is a counter that pulses
  every `TICK_DIV = 25_000_000` clocks, giving 4 Hz, so single stream bits are
  visible on `LED16_R`. Fast mode steps every clock, so the LED's brightness
  tracks T / 65535.
- **Ones counter.** Counts stream bits (cycles with `en` high) and how many are
  1. A window is 65,535 bits, which is one full LFSR period. Over a full
  period every nonzero R appears exactly once, so the ones count equals T
  exactly. That makes the display a built-in pass/fail check.
  - Fast mode shows the last complete window. A new one finishes every
    0.65 ms, so the reading is steady.
  - Slow mode shows the running count since the last load. A full window would
    take about 4.5 hours at 4 Hz.
  - `load` and `rst` clear the counters.
- **Seven-segment driver.** Free-running counter, with its top 3 bits
  selecting the digit: 1.3 ms per digit, about 95 Hz refresh. Segments and
  anodes are active low. Outputs are registered. The decimal point on digit 4
  separates T from the count.
- **`.mem` files.** Not copied. The top passes the bare filename
  `"lut_a.mem"`, and `Python_Code/lut_*.mem` are added to the Vivado project
  as design sources so the name resolves (see `lut_to_fpga.md`).

### Verification (Verilator, before hardware)

- Lint is clean except for intentional items: `SW[13:11]` unused, and the
  initial value on `refresh_cnt`.
- Simulation with `TICK_DIV` shortened to 10:
  - Load at code 1500 gives LEDs `E850`, matching `lut_a.mem[1500]`.
  - Slow mode gives 20 `en` pulses in 200 cycles.
  - Fast mode, ones in one full window:

    | Code | T | Window count | Display |
    |---|---|---|---|
    | 0 | 0001 | 0001 | `0001.0001` |
    | 1342 | 803A | 803A | `803A.803A` |
    | 1500 | E850 | E850 | `E850.E850` |
    | 2047 | FFFF | FFFF | `FFFF.FFFF` |

### Vivado bring-up

- **First bitstream attempt failed DRC** (`NSTD-1` and `UCIO-1`, 48 ports
  without a pin or I/O standard). The listed ports (`code`, `seed`,
  `threshold`, ...) were `sng`'s, so Vivado had built `sng` as the top.
  - Fix: add `nexys4ddr_top.sv` and `seven_seg.sv` to the design sources,
    **Set as Top** on `nexys4ddr_top`, and resynthesize.
  - Don't downgrade those DRCs to warnings. That gives random pin assignments.
- **Hit merge conflicts on `git pull`** on another clone. Resolved there.

### Board test procedure

1. All switches down, press CPU_RESET.
2. Set a code on `SW[10:0]` and press BTNC. The LEDs and the left display
   half should show T (table above). The LEDs should change only on BTNC.
3. `SW[15]` up (slow mode). `LED16_R` blinks with probability T / 65535: always
   on at 2047, almost never at 0, about half the time at 1342. The right half
   of the display counts up.
4. `SW[14]` up as well (fast mode). The two halves of the display should match
   exactly, and the brightness of `LED16_R` follows T.

### Open items

- [ ] Check `SW[8]`/`SW[9]` I/O standards against Digilent's master XDC.
  They're set to `LVCMOS18` (pins T8/U8 are in a 1.8 V bank), which differs
  from the original handoff's `LVCMOS33`. If implementation reports a bank
  voltage error, switch them to `LVCMOS33`.
- [ ] Check the seven-segment pins against the master XDC. They were taken
  from memory.
- [ ] Rerun synthesis with `nexys4ddr_top` as top. Check that the log has no
  `Synth 8-4445` (`.mem` not found) and that utilization shows 1 RAMB36 for
  the LUT.
- [ ] Run the board test procedure above.
- [ ] Possibly add a `.gitignore` for Vivado project output (`*.runs/`,
  `*.cache/`, `.Xil/`, ...) to avoid future merge conflicts on generated files.

## 2026-11-09 (later): all three SNGs + AND/MUX on the board

Written with Claude Code (Opus 5.5).

### Goal

Show the full datapath from the report on the board instead of SNG A alone.
- SNG A and SNG B make the operand streams a and b.
- SNG S makes the MUX select s.
- a & b is the stochastic multiply, and s ? b : a is the scaled add.

The UART/FSM host interface from the report is still a separate, later step.

### Cost

Small in hardware: 3 RAMB36 (one LUT each) out of 135, and a few DSP48s for
the expected-value math. Most of the work was the controls, because 16
switches can't hold two 11-bit codes.

### Files changed

| File | Change |
|---|---|
| `sv_code/nexys4ddr_top.sv` | Reworked: three `sng` instances, AND/MUX, five ones counters, expected-value math, display select |
| `constraints/nexys4ddr.xdc` | Added `BTNL` (P17) and `BTNR` (M17); removed `LED16_R`; added the new buttons to the false-path list |
| `sv_code/tb_nexys4ddr_top.sv` | New self-checking testbench for the top level (simulation fileset only) |
| `sv_code/seven_seg.sv` | Unchanged |

### Board mapping (replaces the one above)

| Board | Function |
|---|---|
| `SW[10:0]` | code for A/B loads |
| `BTNL` / `BTNR` / `BTNC` | load A / load B / load both, from `SW[10:0]` |
| `CPU_RESETN` | reset. On release, A and B load `SW[10:0]` and S loads `S_CODE`. Same at power-on. |
| `SW[13:11]` | display select: 0 = a, 1 = b, 2 = s, 3 = a & b, 4 = mux (5–7 show zeros) |
| `SW[14]` | speed: 0 = 4 Hz tick, 1 = every clock |
| `SW[15]` | run |
| `LED[4:0]` | live bits a, b, s, a & b, mux |
| 7-seg left | **expected** 1s per 65,535 bits for the selected stream (hex) |
| 7-seg right | **measured** 1s (last full window in fast mode, running count in slow mode) |

### Design decisions

- **S_CODE = 1363.** It's the `lut_s.mem` entry closest to 0.5 (T = 0x7FAA),
  matching the report ("the entry of its own LUT closest to 0.5").
- **Separate seeds:** A = `ACE1`, B = `1D2C`, S = `5EED`. Each SNG also keeps
  its own taps and shuffle map from the `sng.sv` header.
- **Power-on reset with no extra logic.** The reset synchronizer starts at 0
  when the FPGA is configured, so `rst` is high for two cycles at startup.
  The first cycle after reset ends (`rst_release`) loads all three SNGs, so
  they always start with a threshold and their own seed.
- **Expected values in hardware:**
  - a, b, s: T.
  - a & b: `(T_A * T_B) >> 16`.
  - mux: `((65535 - T_S) * T_A + T_S * T_B) >> 16`.
  - Dividing by 2^16 instead of 65,535 is off by at most a couple of counts.
  - Registered, so the multiplies are off the critical path. Thresholds only
    change on a load.
- **Counters:** the earlier ones counter generalized to five streams with one
  shared bit counter. Any load clears them all.
- **Why a, b, s match exactly but a & b and mux don't:**
  - A 65,535-bit window is one full period of each LFSR, so each SNG's count
    is exactly T.
  - The products and MUX depend on how the three different LFSR sequences
    line up, so they show real stochastic error. That error is what the
    project is measuring.

### Verification (Verilator)

`tb_nexys4ddr_top.sv` drives the buttons and switches and reads the results
back by decoding `SEG`/`AN`. It doesn't use internal signals for the display
checks. It also checks every cycle that `LED[3] = a & b` and
`LED[4] = s ? b : a`.

Power-on: T_A = 0C16, T_B = 0DEE (code 1000), T_S = 7FAA.

| A code / B code | Stream | Expected | Measured | Error |
|---|---|---|---|---|
| 1500 / 1342 (BTNL, BTNR) | a | E850 | E850 | 0 |
| | b | 8FE7 | 8FE7 | 0 |
| | s | 7FAA | 7FAA | 0 |
| | a & b | 8296 | 82C4 | +46 (0.070%) |
| | mux | BC38 | BBEE | −74 (0.113%) |
| 1200 / 1200 (BTNC) | a | 3490 | 3490 | 0 |
| | b | 3C97 | 3C97 | 0 |
| | s | 7FAA | 7FAA | 0 |
| | a & b | 0C70 | 0C87 | +23 (0.035%) |
| | mux | 3890 | 38B1 | +33 (0.050%) |

Result: PASS. Run from the repo root:

```
verilator --binary --timing -Wno-fatal -Wno-lint --top-module tb_nexys4ddr_top \
  sv_code/tb_nexys4ddr_top.sv sv_code/nexys4ddr_top.sv sv_code/seven_seg.sv \
  sv_code/sng.sv sv_code/sng_lut.sv sv_code/lfsr_shuffle.sv sv_code/sng_comparator.sv
./obj_dir/Vtb_nexys4ddr_top
```

### Board test procedure (replaces the one above)

1. Press CPU_RESET.
2. Set a code on `SW[10:0]` and press BTNL. Set another code and press BTNR.
3. Turn `SW[15]` and `SW[14]` up.
4. Step `SW[13:11]` through 0–4:
   - 0/1/2 (a, b, s): the two display halves match exactly.
   - 3/4 (a & b, mux): the halves are close, with an error of a fraction of
     a percent.
5. Turn `SW[14]` down for slow mode. `LED[3]` lights only when `LED[0]` and
   `LED[1]` are both on. `LED[4]` follows `LED[1]` when `LED[2]` is on and
   `LED[0]` when it's off.

### Open items (in addition to the ones above)

- [ ] Add `Python_Code/lut_b.mem` and `lut_s.mem` to the Vivado design sources
  (not only `lut_a.mem`), and `tb_nexys4ddr_top.sv` to the simulation sources.
- [ ] After synthesis, utilization should show 3 RAMB36, with no
  `Synth 8-4445` warnings.
