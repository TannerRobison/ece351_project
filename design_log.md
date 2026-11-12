| Item | Design log entry |
|---|---|
| **Name** | Ren Cadua |
| **Date** | October 29, 2026 |
| **Objective** | Implement the memristor switching model in Python and generate lookup tables for the FPGA. |
| **Work completed** | Calculated switching probabilities for 2048 voltage values between 1.4 V and 4.0 V. Converted probabilities into 16-bit thresholds and exported lut_a.mem, lut_b.mem, and lut_s.mem. |
| **Design choices** | Used a modeled pulse width of 1 ms. Device A uses nominal parameters. Device B increases tau_0 by 2% and decreases V_0 by 1%. Device S decreases tau_0 by 2% and increases V_0 by 1%. These variations are modeling assumptions representing differences between devices. |
| **Results** | The script produced LUT files and displayed switching curves. For device S, the reported entry closest to probability 0.5 was code 1363, with threshold 32682 and encoded probability approximately 0.498695. |
| **Problems encountered** | Moving the Python file caused VS Code to run its old location, producing a file not found error. The identified fix was to reopen the file from its new location. |









