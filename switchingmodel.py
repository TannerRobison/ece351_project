# Memresitor switching model: Described as in which the device
# resistance can depend on one or more internal state variables
# How often it switches depends on the pulse voltage magnitude
# pulsing a memresistor once per clock cyvle produces a random 
# .. bitstream of whose bitstream whose fractions of 1s is set 
# .. by voltage.

import numpy as np
import matplotlib.pyplot as plt
from pathlib import Path

# global variables, setting voltage range and entries
NUM_ENTRIES = 2048
V_MIN = 1.4                  
V_MAX = 4.0                  

DELTA_T = 0.001             
TAU_0 = 2.69e5              
V_0 = 0.163                  

MAX_THRESHOLD = 65535       


# Each lut has 2048 entries, one per voltage code
voltage_codes = np.arange(NUM_ENTRIES)
voltages = np.linspace(V_MIN, V_MAX, NUM_ENTRIES)


# Memresistor switching equations

def switching_probability(voltage, tau_0, v_0, delta_t):

    # tau(V) = tau_0 * exp(-V / v_0) (tau(V))
    tau = tau_0 * np.exp(-voltage / v_0)

    # P(V) = 1 - exp(-delta_t / tau) (Pswitch(v))
    probability = -np.expm1(-delta_t / tau)

    return probability


# For each lut, we want different device paramters so we
# .. can emulate device to device variation
# NOTE for me: Go over with team which device paramters would work, not
# .. really sure

devices = {
    "a": {"tau_0": TAU_0,        "v_0": V_0},
    "b": {"tau_0": TAU_0 * 1.02, "v_0": V_0 * 0.99},
    "s": {"tau_0": TAU_0 * 0.98, "v_0": V_0 * 1.01},
}


# Folder for the .mem files for when we do verilog
output_folder = Path(__file__).resolve().parent / "generated_luts"
output_folder.mkdir(exist_ok=True)

plt.figure(figsize=(8, 5))


# Look up tables (LUT), 

for name, parameters in devices.items():

    # Calculate probabilities for all 2048 voltages for each device
    probabilities = switching_probability(
        voltages,
        parameters["tau_0"],
        parameters["v_0"],
        DELTA_T
    )

    # Convert probabilities into integer thresholds (16bits)
    # .. scales probabilities to 0-65535
    thresholds = np.rint(
        probabilities * MAX_THRESHOLD
    ).astype(np.int64)

    # Check that the generated data is valid
    assert len(thresholds) == NUM_ENTRIES
    assert np.all(np.isfinite(probabilities))
    assert np.all((probabilities >= 0) & (probabilities <= 1))
    assert np.all((thresholds >= 0) & (thresholds <= MAX_THRESHOLD))
    assert np.all(np.diff(thresholds) >= 0)

    # Save hexadecimal thresholds for .mem
    mem_file = output_folder / f"lut_{name}.mem"

    with mem_file.open("w") as file:
        for threshold in thresholds:
            file.write(f"{int(threshold):04X}\n")

    # Probability represented by the integer threshold
    encoded_probabilities = thresholds / MAX_THRESHOLD

    # Find the LUT entry closest to a probability of 0.5,
    # .. Used for the adder,s
    half_code = int(
        np.argmin(np.abs(encoded_probabilities - 0.5))
    )

    print(f"\nSNG {name.upper()}")
    print(f"tau_0 = {parameters['tau_0']} seconds")
    print(f"v_0 = {parameters['v_0']} volts")
    print(f"Saved {mem_file.name}: {len(thresholds)} entries")
    print(f"Code closest to probability 0.5: {half_code}")
    print(f"Voltage: {voltages[half_code]:.6f} V")
    print(f"Threshold: {thresholds[half_code]}")
    print(f"Encoded probability: {encoded_probabilities[half_code]:.6f}")

    # Plot the device's switching curve
    plt.plot(
        voltages,
        probabilities,
        label=f"SNG {name.upper()}"
    )


# Plot

plt.xlabel("Modeled pulse voltage (V)")
plt.ylabel("Switching probability")
plt.title("Memristor Switching Probability")
plt.grid(True)
plt.legend()
plt.tight_layout()

plt.show()