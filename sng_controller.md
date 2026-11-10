# Host-controlled SNG experiment

`sv_code/sng_controller.sv` controls one experiment at a time.
`sv_code/sng_experiment.sv` connects it to the existing three SNGs, AND
multiplier, and MUX scaled adder. This is separate from the Nexys 4 DDR
switch/button demo in `nexys4ddr_top.sv`.

## States

| State | What happens |
| --- | --- |
| IDLE | Wait for the start byte (default `A5` hex). |
| RECEIVE | Capture the next 14 bytes. Return to IDLE after a gap of `RX_TIMEOUT_CYCLES` clocks without a byte. |
| LOAD | Assert `load` for one cycle. At its closing edge, the three LUTs register their thresholds, the LFSRs load their seeds, and the five counters clear. |
| RUN | Assert `en`. At each rising edge, count the current five bits and advance the LFSRs. The first sample uses the loaded seed; the last sample is counted on the edge entering REPORT. |
| REPORT | Hold each response byte and `tx_valid` until an edge with `tx_ready`. After the tenth byte is accepted, return to IDLE. |

`L=0` returns five zero counts and bypasses RUN. Each count is 16 bits
and can represent every result up to the largest request, 65,535 samples.
Reset is synchronous and active high. The RX and TX signals use the same
clock as the controller.

## Proposed byte protocol

The proposal defines the packet sizes and fields but does not fix the
start byte or byte order. Confirm these choices with the host and UART
implementers before testing on the board:

- Request: start byte `0xA5`, then seven little-endian unsigned 16-bit
  words: **code A, code B, code S, seed A, seed B, seed S, L**. Send voltage
  codes 0–2047; hardware uses the low 11 bits of each code word.
  A zero seed is mapped to 1 by the existing LFSR.
- Response: five little-endian unsigned 16-bit words:
  **count A, count B, count S, multiply count, scaled add count**.
  For example, a count of 256 is sent as bytes `00 01`.
- The host should wait for the entire response before sending another
  request. RX bytes outside IDLE and RECEIVE are ignored. An incomplete request is dropped without a response; the host should
  time out and retry if needed.
- The UART RX block pulses `rx_valid` for one cycle per decoded byte.
  The UART TX block asserts `tx_ready` when it can latch a byte. The UART
  serializers, host script, and physical board wiring are separate from
  this controller. In a board wrapper, add the three LUT .mem files as
  design sources and use their existing bare filenames.

## Integration simulation

Run from the repository root so the testbench can open
`Python_Code/lut_{a,b,s}.mem`. In the Questa Transcript:

```tcl
vlib work
vlog -sv sv_code/sng_controller.sv sv_code/sng_experiment.sv sv_code/sng.sv sv_code/sng_lut.sv sv_code/lfsr_shuffle.sv sv_code/sng_comparator.sv sv_code/tb_sng_experiment.sv
vsim -onfinish stop work.tb_sng_experiment
run -all
```

The testbench sends requests into the byte ports and checks timeout
recovery, one LOAD pulse, exact RUN cycle counts, response byte order
and stability during transmitter stalls, and all five counts for
L=1, 19, 65,535, and 0. At L=65,535 the individual SNG counts
should equal their LUT thresholds because each LFSR covers a full period.
