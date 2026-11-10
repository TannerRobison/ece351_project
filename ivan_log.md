# Ivan's Design Log

## 2026-10-28: Stochastic comparator RTL and standalone testing

Developed with ChatGPT assistance for RTL, testbench, and explanations.

### Goal

Implement the comparator inside each stochastic number generator. The
comparator takes the shuffled LFSR value R and the LUT threshold T and
outputs 1 when R <= T. Repeating the comparison produces a bitstream whose
fraction of ones represents the selected switching probability.

### Files added

| File | Purpose |
|---|---|
| `sv_code/sng_comparator.sv` | Unsigned comparator that produces one stochastic bit |
| `sv_code/tb_sng_comparator.sv` | Self-checking standalone testbench |
| `results/Comparator Results.pdf` | Questa simulation results and waveform evidence |

### Design decisions

- **Unsigned 16-bit inputs.** Matches the planned LFSR output and LUT
  thresholds. Signed inputs would interpret values with bit 15 set as
  negative, changing the comparison.
- **Use R <= T.** The intended maximal-length LFSR covers 1 through 65,535.
  Over a full period, exactly T values meet this comparison, giving a
  fraction T / 65,535. This matches the proposal's threshold scaling.
- **Combinational output.** A continuous assignment implements the
  comparison. No clock, reset, or output register is needed inside this
  module. The surrounding LFSR and counters provide the clocked behavior.
- **Keep the threshold fixed during a run.** The comparator generates bits;
  it does not hold the threshold or count ones. Those responsibilities
  belong to the LUT output register and run-control logic.

### Verification (Questa Sim)

Ran the standalone testbench on the PSU VM. The boundary cases included:

| R | T | Expected output |
|---|---|---|
| 99 | 100 | 1 |
| 100 | 100 | 1 |
| 101 | 100 | 0 |
| 1 | 0 | 0 |
| 65,535 | 65,535 | 1 |
| 32,768 | 32,767 | 0 |

The testbench also checks other endpoint cases and sweeps all 65,535
nonzero input values with T = 32,768. The sweep must produce exactly
32,768 ones. This checks the threshold comparison without depending on
an actual LFSR or LUT.

Result: PASS. Questa printed `PASS: All comparator tests passed.` and
reached `$finish` at 65,545 ns. That time consists of 10 directed tests
plus 65,535 sweep inputs, each held for 1 ns. The waveform showed the
expected below/equal/above-threshold behavior.

## 2026-10-29: Parameterized comparator width

Developed with ChatGPT assistance.

### Goal

Make the comparator width configurable after a teammate asked about using
a parameter to simplify integration.

### Files changed

| File | Change |
|---|---|
| `sv_code/sng_comparator.sv` | Added `parameter int WIDTH = 16`; input widths now use `[WIDTH-1:0]` |

### Design decisions

- **Default to 16 bits.** Existing instantiations can keep the original
  behavior, or explicitly use `.WIDTH(16)` as the current SNG does.
- **Parameter controls width, not probability.** The threshold remains a
  runtime input. The comparison itself is unchanged.
- **Other widths require coordinated changes.** The LFSR taps, shuffle,
  LUT thresholds, and testbench values must also match the selected width.
  Parameterizing the comparator alone does not make the whole SNG generic.

### Verification status

The standalone results above were recorded for the original fixed-width
implementation. The parameterized comparator at WIDTH = 16 was subsequently
used in the controller integration simulation described below. Other widths
have not been verified here.

## 2026-11-10: State machine controller and host-controlled experiment path

Written with ChatGPT assistance for RTL, testbench, simulation, and this
log. The controller integration tests were run by ChatGPT in Verilator;
I have not yet repeated those tests in Questa or tested this path on the board.

### Goal

Coordinate the host-driven experiments described in the proposal: receive
voltage codes, seeds, and a stream length; load the three SNGs; count L
samples; and return the five counts. The repo already has SNG modules and
a Nexys 4 DDR switch/button demo with arithmetic. This adds a separate
experiment wrapper around the existing SNGs.

### Files added

| File | Purpose |
|---|---|
| `sv_code/sng_controller.sv` | Five-state FSM, packet registers, timeout, sample countdown, five ones counters, and response-byte output |
| `sv_code/sng_experiment.sv` | Connects the FSM to three existing SNGs and the AND/MUX arithmetic |
| `sv_code/tb_sng_experiment.sv` | Self-checking byte-level integration testbench using the actual LUT files |
| `sng_controller.md` | Interface, packet format, timing, and Questa run instructions |

### State sequence

| State | Action | Next state |
|---|---|---|
| IDLE | Wait for the start byte | RECEIVE when the start byte arrives |
| RECEIVE | Collect 14 configuration bytes | LOAD after all bytes; IDLE on receive timeout |
| LOAD | Pulse SNG load; clear counters and initialize sample countdown | RUN for nonzero L; REPORT for L = 0 |
| RUN | Count current stream bits and advance all three LFSRs | REPORT after the Lth sample |
| REPORT | Send ten response bytes, waiting for each acceptance | IDLE after the tenth byte is accepted |

### Design decisions

- **Reuse existing SNG control ports.** Each `sng` receives its own code and
  seed. All three share the controller's `load` and `en` signals. The
  existing comparator, LUT, and LFSR modules are unchanged by this patch.
- **Synchronous LUT timing.** At the edge ending LOAD, each LUT registers
  its threshold and each LFSR loads its seed. The first sample is counted
  on the next rising edge in RUN, using the seeded state. The last RUN
  edge counts its sample before the FSM enters REPORT.
- **Five counters.** Count A, B, select S, `a & b`, and `s ? b : a`.
  The controller receives these as `{scaled_add, multiply, s, b, a}`.
  Sixteen-bit counters support every request length through 65,535.
- **No floating-point conversion in the FSM.** Return integer counts;
  the host can divide by L to calculate the measured values.
- **Receive timeout.** Default is 1,000,000 clocks without a new byte
  during RECEIVE, or 10 ms at 100 MHz. A partial request is abandoned
  without a response. The host must use its own timeout and retry.
- **Transmit handshake.** Hold `tx_valid` and `tx_data` until an edge with
  `tx_ready` high. Advance one byte on that edge. This allows a UART
  transmitter to take time between accepting bytes.
- **L = 0.** Load the SNGs, skip RUN, and return five zero counts. The
  host must avoid dividing by zero when interpreting this response.
- **Separate from the board demo.** `nexys4ddr_top.sv`, its display, and
  its pin constraints are not modified. Physical UART serialization and
  board-level wiring remain separate integration work.

### Proposed host packet format

These are implementation choices to confirm with the team; the proposal
specifies the field sizes but not the start marker or byte order.

| Direction | Format |
|---|---|
| Request | Start byte `0xA5`, followed by seven little-endian 16-bit words: code A, code B, code S, seed A, seed B, seed S, L |
| Response | Five little-endian 16-bit words: count A, count B, count S, multiply count, scaled-add count |

Voltage codes must be 0-2047; the implementation uses each code word's
low 11 bits. The existing LFSR maps a zero seed to 1. The host should
wait for the entire response before starting another experiment. Requests
are not queued while LOAD, RUN, or REPORT is active.

### Verification (Verilator, before hardware)

The integration testbench uses the repo's three SNGs and
`Python_Code/lut_a.mem`, `lut_b.mem`, and `lut_s.mem`. It sends complete
requests at the byte interface, not through physical serial pins.

Test settings: A code = 1370, B code = 1450, S code = 1363;
seeds A = `ACE1`, B = `1D2C`, S = `5EED`. Reference counts were calculated
with a Python model of the LUT comparisons, shuffle maps, and LFSR steps.

| L | A count | B count | S count | Multiply count | Scaled-add count |
|---|---|---|---|---|---|
| 1 | 0 | 1 | 1 | 0 | 1 |
| 19 | 11 | 16 | 5 | 9 | 13 |
| 65,535 | 37,924 | 56,045 | 32,682 | 32,465 | 46,939 |
| 0 | 0 | 0 | 0 | 0 | 0 |

All four runs matched their reference counts. The full-period A/B/S
counts also equal the selected LUT thresholds.

Additional checks passed:

- An unrelated byte in IDLE does not begin a request.
- An incomplete packet times out without loading or running the SNGs;
  a subsequent complete request succeeds.
- Each complete request produces one LOAD pulse and exactly L enabled
  sample cycles.
- Each response byte stays stable through three stalled clock cycles.
- The response has the expected little-endian order, and counting stops
  while results are sent.

Result: `PASS: controller + three SNGs + arithmetic`. This verifies the
tested byte-level datapath behavior, not synthesis timing or UART/board
operation.

### Open items

- [ ] Agree on the start byte, field order, and little-endian encoding.
- [ ] Repeat `tb_sng_experiment` in Questa from the repo root using the
  commands in `sng_controller.md`; save the transcript and waveform.
- [ ] Connect UART RX/TX modules with the documented byte handshake.
- [ ] Add the matching Python host request/response code.
- [ ] Connect the experiment wrapper to the Nexys 4 DDR clock, reset,
  and UART pins; confirm reset polarity and synchronization.
- [ ] Synthesize and implement the combined design in Vivado; check
  timing and LUT memory initialization.
- [ ] Test reset during an active run or response and additional UART
  traffic/error cases.
- [ ] Run board experiments across codes and stream lengths and collect
  encoding/arithmetic error measurements for the final report.
