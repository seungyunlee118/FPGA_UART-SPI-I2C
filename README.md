# Hardware-Accelerated Multi-Protocol Controller (UART, SPI, I2C) on Zynq SoC

## Project Overview
This project implements a **Hardware-Accelerated Multi-Protocol Communication Controller** supporting **UART, SPI, and I2C** on the **Zybo Z7-20 (Zynq-7000 SoC)**.

Unlike standard software bit-banging, all communication logic is offloaded to the **FPGA Programmable Logic (PL)**, ensuring precise timing and reduced CPU load. The system is managed by the **ARM Cortex-A9 (PS)** via a custom **AXI4-Lite** interface.

### Key Objectives
* **Hardware Acceleration:** Offloading protocol engines to FPGA to reduce CPU overhead.
* **Robustness:** Status-polling software drivers with timeouts, and self-checking testbenches that fail on wrong data.
* **Modular Design:** Verification from Unit Test (RTL) to System Integration.


## System Architecture & Features
The system integrates three independent protocol engines connected via AXI Interconnect, controlled by the ARM Processor.

![System Architecture](https://github.com/user-attachments/assets/126f6e3a-6901-448a-b314-a692c3e30c43)

### Protocol Engines
* **UART Controller:**
    * Full-duplex communication (TX/RX), 8N1, LSB first, 16x oversampling.
    * 16-byte TX and RX FIFOs. The RX FIFO is show-ahead: software must check `RX_Empty` before reading.
    * Baud rate set by a divisor: tick period = `divisor + 1` clocks, so `divisor = f_clk / (16 x baud) - 1` (650 for 9600 bps at 100 MHz).
* **SPI Controller (Master):**
    * **Mode 0 only** (CPOL = 0, CPHA = 0), MSB first, 8-bit frames.
    * SCLK = f_clk / 100 (1 MHz at 100 MHz).
* **I2C Controller (Master):**
    * **7-bit addressing**, open-drain pins through `IOBUF`, 100 kHz SCL at 100 MHz.
    * Single-byte write and single-byte read (the master NACKs the byte it reads).
    * Verified in simulation against an independent slave model. Not tested on hardware (no slave device was available).


## Step 1: Pre-Synthesis Verification (RTL Simulation)
Each engine has a **self-checking testbench**. Every testbench compares against expected values and ends with `*** TEST PASSED ***` or `*** TEST FAILED ***`.

| Testbench | What it checks |
| :--- | :--- |
| `tb_uart_core.sv` | Decodes the TX pin with its own bit timing (independent of the DUT's baud generator) and compares every byte. Also reads every byte back through the RX FIFO and compares it. Then sends a 20-byte burst into the 16-deep TX FIFO and checks that exactly 16 are accepted. |
| `tb_spi_ip.sv` | Drives the IP over AXI4-Lite against an **independent SPI slave model** (not a MOSI-to-MISO loopback). Checks both directions on 16 transfers, including values where bit 0 differs from the slave's bit 7. Also checks one frame per start command, DONE sticky/W1C, and that SCLK never toggles while CS is high. |
| `tb_i2c_ip.sv` | An **independent I2C slave model** detects START and STOP on edges and acknowledges on the 9th clock. The test covers a write, two reads (checking `RDATA` and the master's final NACK), a write to an absent address (expecting `ACK_ERR`), and recovery afterwards. It also checks one START/STOP per command. |

The waveforms below come from the **original, waveform-only testbenches**. They are kept here because they show the bugs described in [Re-verification](#re-verification-what-the-original-tests-missed).

### 1. UART Simulation
<img width="100%" alt="UART Simulation" src="https://github.com/user-attachments/assets/c45f4f66-ee7f-4543-9f07-67b63fb0d5e0" />

### 2. SPI Simulation (Mode 0)
The original master sends `0x54` on MOSI for `0x55`: there are three high pulses per byte instead of four.
<img width="100%" alt="SPI Simulation" src="https://github.com/user-attachments/assets/9da928bc-54a4-44f3-8120-6e5ec25b40a4" />

### 3. I2C Simulation (Master Mode)
In the original testbench, the slave acknowledged one bit early. As a result, every transaction in this waveform ends in a NACK after the address byte.
<img width="100%" alt="I2C Simulation" src="https://github.com/user-attachments/assets/f2f83d0e-7c32-4d52-8a9c-c7cee932cda8" />

### Running the testbenches
Vivado Simulator: add the `hw/src` files to a simulation set and run each `tb_*` as top.

Icarus Verilog (tested with 14.0-dev):
```bash
cd FPGA-Communication-Accelerator/hw/src
iverilog -g2012 -o uart.vvp baud_gen.sv fifo.sv uart_tx.sv uart_rx.sv uart_core.sv tb_uart_core.sv && vvp uart.vvp
iverilog -g2012 -o spi.vvp  spi_master.sv spi_ip.sv tb_spi_ip.sv && vvp spi.vvp
iverilog -g2012 -o i2c.vvp  iobuf_model.v i2c_master.sv i2c_ip.sv tb_i2c_ip.sv && vvp i2c.vvp
```
`IOBUF` is a Xilinx primitive. Outside Vivado, save this behavioral model as `iobuf_model.v` (do not add it to the Vivado project):
```verilog
module IOBUF (output O, inout IO, input I, input T);
  assign IO = T ? 1'bz : I;
  assign O  = IO;
endmodule
```

## Step 2: Component Verification & IP Packaging
Before integrating with AXI, the core logic components were tested independently.

### 1. FIFO & State Machine Verification
* **FIFO Test:** `tb_uart_core` fills the TX FIFO past capacity and checks the `Full` flag and the accepted count. Every byte is compared in order on the way out.
* The waveform below is from the original testbench. That testbench pulsed `rd_en` and then sampled `rd_data`, so it printed the *next* slot (`0x00`) after each pop.
<img width="100%" alt="FIFO Verification" src="https://github.com/user-attachments/assets/f1a8ec9e-5cd8-4980-b7bf-50ec33d40bf6" />

### 2. IP Packaging (Modular Design)
Each protocol engine was wrapped with an **AXI4-Lite interface** and packaged as a standalone **Custom IP** in Vivado. This allows for reusability in future Zynq-based designs.

## Step 3: Software Implementation & Driver Testing
Each IP was first tested individually in **Vitis** to verify register access and driver functionality.

### 1. Driver: poll status, never read blind
* `uart_getc()` waits for `RX_Empty = 0` before reading the RX register. `uart_putc()` waits for `TX_Full = 0`. Both time out.
* `spi_xfer()` writes TX, writes `START` once, polls the sticky `DONE` bit, reads RX, and clears `DONE`.
* The test sends ten **different** values (including `0x55`, `0xAA`, `0x01`, `0x80`) and reports how many came back wrong.

### 2. Individual Unit Testing (Vitis)
These captures are from the original design:
* **UART Test:** Each received character is the *previous* one sent (A → nothing, B → A, …). The driver was reading an empty show-ahead FIFO; see [Ghost Data](#1-the-ghost-data-issue).
    <br><img width="50%" alt="UART Vitis" src="https://github.com/user-attachments/assets/da5e8146-41eb-489c-8e03-eed0a162ef0c" />
* **SPI Test:** `0xAA` → `0xAB`, `0xAC` → `0xAD`. The LSB was overwritten by the first received bit; see [Re-verification](#re-verification-what-the-original-tests-missed).
    <br><img width="60%" alt="SPI Vitis" src="https://github.com/user-attachments/assets/5aad89bc-bd98-4e5f-8b12-f0877e6bc6b5" />

### 3. I2C Implementation Note
* **Status:** Write and single-byte read implemented and verified in simulation.
* **Constraint:** I2C cannot be tested with a wire loopback, because it needs an **ACK** from a real slave device. Hardware testing needs a slave such as an EEPROM or sensor on the JD header.


## Hardware Setup & Pinout
Physical connections on the **Zybo Z7-20 Pmod Headers** are required for the Loopback Test. Pins match `hw/constrs/zybo_z7_uart.xdc`. Pmod pins 5/11 are GND and 6/12 are 3.3 V.

| Protocol | Pmod Header | Pin # | FPGA Pin | Signal | Wiring for Loopback Test |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **UART** | **JB Top** | 2 | `W8` | **TX** | **Connect to Pin 3 (RX)** |
| | | 3 | `U7` | **RX** | **Connect to Pin 2 (TX)** |
| **SPI** | **JB Bottom**| 7 | `Y7` | **SS** | (Chip Select) |
| | | 8 | `Y6` | **MOSI** | **Connect to Pin 9 (MISO)** |
| | | 9 | `V6` | **MISO** | **Connect to Pin 8 (MOSI)** |
| | | 10 | `W6` | **SCLK** | (Clock Output) |
| **I2C** | **JD Top** | 1 | `T14` | **SCL** | Connect to Slave SCL |
| | | 2 | `T15` | **SDA** | Connect to Slave SDA |

> **Note:** **UART RX**, **I2C SCL** and **I2C SDA** use the internal `PULLUP`. For a real I2C slave, add external 2.2–4.7 kΩ pull-ups.


## AXI4-Lite Register Map
The memory-mapped interface is accessible via the **ARM Cortex-A9 (PS)**. W1S = write 1 to start (self-clearing, reads 0). W1C = write 1 to clear.

| Protocol | Base Address | Offset | Register Name | Access | Description |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **UART** | `0x43C00000` | `0x00` | `UART_DIV` | R/W | Baud Rate Divisor |
| | | `0x04` | `UART_STAT` | RO | Status (Bit 0: RX_Empty, Bit 1: TX_Full) |
| | | `0x08` | `UART_TX` | WO | Transmit Data Register |
| | | `0x0C` | `UART_RX` | RO | Receive Data Register (FIFO) |
| **SPI** | `0x43C10000` | `0x00` | `SPI_CTRL` | W1S | Bit 0: START (one frame per write) |
| | | `0x04` | `SPI_STAT` | RO / W1C | Bit 0: BUSY, Bit 1: DONE (sticky, W1C) |
| | | `0x08` | `SPI_TX` | R/W | MOSI Data [7:0] |
| | | `0x0C` | `SPI_RX` | RO | MISO Data [7:0] |
| **I2C** | `0x43C20000` | `0x00` | `I2C_CTRL` | R/W | Bit 0: START (W1S), Bit 1: R/W (0 = write, 1 = read) |
| | | `0x04` | `I2C_STAT` | RO / W1C | Bit 0: BUSY, Bit 1: DONE (sticky, W1C), Bit 2: ACK_ERR |
| | | `0x08` | `I2C_ADDR` | R/W | 7-bit Slave Address [6:0] |
| | | `0x0C` | `I2C_WDATA` | R/W | Write Data [7:0] |
| | | `0x10` | `I2C_RDATA` | RO | Read Data [7:0] |

> The UART AXI wrapper (`uart_ip`) is not in this repository yet, so its register map is documented from the packaged IP.


## Final Test Results
The capture below is from the **original** design and driver. The fixed RTL needs to be re-packaged and re-tested on the board with the new `main.c`.

![Final Result](https://github.com/user-attachments/assets/1ab17375-1576-49f3-b0a3-7f7d30646321)


----

## Re-verification: what the original tests missed
The original testbenches only displayed values and never compared them. The board checks were also weak: UART retried the same byte, and SPI accepted anything except `0x00`/`0xFF`. As a result, every test reported success. Re-running the original testbenches with pin-level monitors found these bugs:

| # | Where | Bug | Why it passed before | Fix |
| :--- | :--- | :--- | :--- | :--- |
| 1 | `spi_master.sv` | MISO was sampled into `shift_reg[0]` on the first rising edge. That bit still held a TX bit that had not been sent, so the last bit on MOSI was always the first received bit: loopback `0x55` → `0x54`, `0xAA` → `0xAB`. | Loopback receives the same wrong byte it sends. The board check only rejected `0x00`/`0xFF`. | Sample into a separate flop; shift it in on the falling edge. |
| 2 | `i2c_master.sv` | R/W was read from `shift_reg[0]` after seven shifts, where it is always 0. A read put `0xA1` on the bus and then drove write data. The receive states were not implemented, and `rdata` was never assigned. | Bug 3 meant the data phase never ran in simulation. | Latch R/W; implement `DATA_RX` and the master NACK; assign `rdata`. |
| 3 | `tb_i2c_ip.sv` | The slave detected START by level and counted the START's own SCL fall, so it acknowledged one bit early. Every transaction was a NACK. | The testbench had no checks. | Edge-based slave; one bit per SCL rising edge. |
| 4 | `tb_uart_core.sv` | Raised `rd_en` on the clock edge and then sampled, so it printed the slot after the popped one: `0x00 (Expected 0xAA)`, three times. It still finished with "Verified". | Nothing compared the values. | Compare the head, then pop; drive on the opposite edge. |
| 5 | `spi_ip.sv`, `i2c_ip.sv` | START was wired from the control register as a level, so the engines retransmitted until software wrote 0. `main.c` never did. DONE was a one-cycle pulse that polling could not see. | — | START is W1S (one-cycle pulse); DONE is sticky with W1C. |

`i2c_master.sv` also moves SDA changes from the SCL falling edge to the middle of the SCL low phase, and STOP now drives SDA low only while SCL is low.

**Do the new testbenches catch the old bugs?** Each original bug was put back on its own and the new testbenches were re-run (Icarus Verilog):

| Change | Result |
| :--- | :--- |
| Fixed RTL | UART **PASSED** (26 bytes), SPI **PASSED** (16 transfers), I2C **PASSED** (5 transactions) |
| Original `spi_master.sv` | SPI **FAILED** — `slave received 0x54, master TX reg = 0x55` |
| Read bug put back in `i2c_master.sv` | I2C **FAILED** — `RDATA = 0x00, slave sent 0x3c` |
| Original `spi_ip.sv` / `i2c_ip.sv` (level START) | **FAILED** — `4 frame(s) for one start`, DONE timeout |
| Baud generator off by one clock | UART **FAILED** on the line decoder (43 errors), with **0** errors on the RX FIFO path — a loopback alone cannot see a baud error |


## Troubleshooting & Technical Challenges

### 1. The "Ghost Data" Issue
* **Symptom:** In UART loopback, each read returned the *previous* byte (A → nothing, B → A, C → B). The first read returned `0x00`.
* **Root cause:** The RX FIFO read port is combinational (show-ahead). Reading it while empty returns the stale contents of the next slot (zero after power-up) and does not pop. The driver read the data register without checking `RX_Empty`, so it stayed one byte behind.
* **Original workaround:** A retry loop that resent `0x55` until it read `0x55`. Because every attempt sent the same byte, a late echo of an earlier attempt looked like success, so the retry hid the lag rather than fixing it.
* **Fix:** Poll `RX_Empty` (with a timeout) before every read, and test with different values each time.

### 2. Baud Rate Stability
* **Problem:** Initial tests showed intermittent framing errors due to potential clock division mismatches in software configuration.
* **Solution:** **Hardcoded the Divisor** (Values for 9600 bps @ 100MHz clock) directly in the Verilog RTL module.
* **To verify:** The block design's reset block is named `rst_ps7_0_50M`, and Vivado names that block after the PL clock. If `FCLK_CLK0` is 50 MHz rather than 100 MHz, every rate is halved: UART 4800 bps, SPI 500 kHz, I2C 50 kHz. A loopback cannot detect this, because TX and RX share one baud generator. Check `PCW_FPGA0_PERIPHERAL_FREQMHZ` on the PS7, or measure the UART bit time on a scope (104 µs at 9600 bps).

### 3. I2C Physical Verification Constraint
* **Problem:** I2C needs an ACK from a slave, so a wire loopback always NACKs.
* **Solution:** Verified in simulation against an independent slave model: write, read, NACK on an absent address, and recovery. Hardware testing still needs a real slave device.


## Known Limitations
* SPI: Mode 0 only; one chip select; CS deasserts after every byte (no multi-byte transactions).
* I2C: single-byte write or read; no repeated START, clock stretching (`scl_i` is unused) or multi-master arbitration.
* AXI4-Lite slaves: `WSTRB` is ignored; unmapped addresses return OKAY.
* The UART AXI wrapper (`uart_ip`) is not committed yet.
* The fixed RTL has not yet been re-tested on the board.


----

### Author
* **Seungyun Lee**
* University of Houston
