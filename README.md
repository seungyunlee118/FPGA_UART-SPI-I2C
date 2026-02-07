# Hardware-Accelerated Multi-Protocol Controller (UART, SPI, I2C) on Zynq SoC

## Project Overview
This project implements a **Hardware-Accelerated Multi-Protocol Communication Controller** supporting **UART, SPI, and I2C** on the **Zybo Z7-20 (Zynq-7000 SoC)**.

Unlike standard software bit-banging, all communication logic is offloaded to the **FPGA Programmable Logic (PL)**, ensuring precise timing and reduced CPU load. The system is managed by the **ARM Cortex-A9 (PS)** via a custom **AXI4-Lite** interface.

### Key Objectives
* **Hardware Acceleration:** Offloading protocol engines to FPGA to reduce CPU overhead.
* **Robustness:** Implementing software drivers that handle hardware latency (FIFO delays).
* **Modular Design:** Verification from Unit Test (RTL) to System Integration.


## System Architecture & Features
The system integrates three independent protocol engines connected via AXI Interconnect, controlled by the ARM Processor.

![System Architecture](https://github.com/user-attachments/assets/126f6e3a-6901-448a-b314-a692c3e30c43)

### Protocol Engines
* **UART Controller:**
    * Full-duplex communication (TX/RX).
    * Hardware-fixed baud rate (**9600 bps**) for stability.
    * **Robust Driver:** Software retry logic to handle FIFO latency.
* **SPI Controller (Master):**
    * Standard Master mode implementation.
    * Configurable Clock Polarity/Phase (**CPOL/CPHA**).
* **I2C Controller (Master):**
    * Standard Master Mode implementation.
    * **7-bit Addressing** support.
    * *Note: Logic fully verified via synthesis & simulation.*


## Step 1: Pre-Synthesis Verification (RTL Simulation)
This project followed a strict **Bottom-Up Design Methodology**. Before bitstream generation, all protocol engines were rigorously verified using **Vivado Simulator**.

### 1. UART Simulation
Verified TX/RX baud rate timing consistency and data integrity check.
<img width="100%" alt="UART Simulation" src="https://github.com/user-attachments/assets/c45f4f66-ee7f-4543-9f07-67b63fb0d5e0" />

### 2. SPI Simulation (Mode 0)
Verified SCLK generation, MOSI/MISO data shifting, and Chip Select (CS) active-low timing.
<img width="100%" alt="SPI Simulation" src="https://github.com/user-attachments/assets/9da928bc-54a4-44f3-8120-6e5ec25b40a4" />

### 3. I2C Simulation (Master Mode)
Since physical loopback is not possible for I2C (requires ACK from slave), the logic was **fully verified in simulation**.
* Verified **Start/Stop conditions**.
* Verified **7-bit Addressing** and **ACK/NACK** handshake logic.
<img width="100%" alt="I2C Simulation" src="https://github.com/user-attachments/assets/f2f83d0e-7c32-4d52-8a9c-c7cee932cda8" />

## Step 2: Component Verification & IP Packaging
Before integrating with AXI, the core logic components were tested independently to ensure reliability.

### 1. FIFO & State Machine Verification
* **FIFO Test:** Verified `Empty`/`Full` flag logic and Read/Write pointer synchronization to prevent data loss.
* **FSM Verification:** validated state transitions for all protocols.
<img width="100%" alt="FIFO Verification" src="https://github.com/user-attachments/assets/f1a8ec9e-5cd8-4980-b7bf-50ec33d40bf6" />

### 2. IP Packaging (Modular Design)
Each protocol engine was wrapped with an **AXI4-Lite interface** and packaged as a standalone **Custom IP** in Vivado. This allows for reusability in future Zynq-based designs.

## 💻 Step 3: Software Implementation & Driver Testing
Before the final combined test, each IP was tested individually in **Vitis** to verify register access and driver functionality.

### 1. Robust Driver Implementation ("Retry" Logic)
To solve hardware latency issues where the CPU reads the FIFO before data physically arrives, a **Reliable Send/Recv Algorithm** was implemented.
* **Mechanism:** If the initial read returns `0x00` (invalid), the driver automatically retries the transmission.
* **Result:** Ensures **100% success rate** without manual intervention.

### 2. Individual Unit Testing (Vitis)
* **UART Test:** Verified Baud Rate generation and TX/RX loopback.
    <br><img width="50%" alt="UART Vitis" src="https://github.com/user-attachments/assets/da5e8146-41eb-489c-8e03-eed0a162ef0c" />
* **SPI Test:** Verified CPOL/CPHA mode switching and Chip Select (CS) timing.
    <br><img width="60%" alt="SPI Vitis" src="https://github.com/user-attachments/assets/5aad89bc-bd98-4e5f-8b12-f0877e6bc6b5" />

### 3. I2C Implementation Note
* **Status:** Logic & Driver fully implemented.
* **Constraint:** The physical loopback test for I2C was skipped in the final demo because I2C requires an **ACK bit** from a real physical slave device. Simple wire loopback is electrically insufficient for I2C verification.


## Hardware Setup & Pinout
Physical connections on the **Zybo Z7-20 Pmod Headers** are required for the Loopback Test.

| Protocol | Pmod Header | Pin # | FPGA Pin | Signal | Wiring for Loopback Test |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **UART** | **JB Top** | 1 | `V8` | **TX** | **Connect to Pin 2 (RX)** |
| | | 2 | `W8` | **RX** | **Connect to Pin 1 (TX)** |
| | | 3 | `U7` | *GND* | - |
| **SPI** | **JB Bottom**| 7 | `Y7` | **SS** | (Chip Select) |
| | | 8 | `Y6` | **MOSI** | **Connect to Pin 9 (MISO)** |
| | | 9 | `V6` | **MISO** | **Connect to Pin 8 (MOSI)** |
| | | 10 | `W6` | **SCLK** | (Clock Output) |
| **I2C** | **JD Top** | 1 | `T14` | **SCL** | Connect to Slave SCL |
| | | 2 | `T15` | **SDA** | Connect to Slave SDA |

> **Note:** **UART RX** is configured with internal `PULLUP` to prevent floating signal errors.


## AXI4-Lite Register Map
The memory-mapped interface is accessible via the **ARM Cortex-A9 (PS)**.

| Protocol | Base Address | Offset | Register Name | Access | Description |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **UART** | `0x43C00000` | `0x00` | `UART_DIV` | R/W | Baud Rate Divisor (Default: 9600) |
| | | `0x04` | `UART_STAT` | RO | Status (Bit 0: RX_Empty, Bit 1: TX_Full) |
| | | `0x08` | `UART_TX` | WO | Transmit Data Register |
| | | `0x0C` | `UART_RX` | RO | Receive Data Register (FIFO) |
| **SPI** | `0x43C10000` | `0x00` | `SPI_CTRL` | R/W | Control (Start, Enable, Mode) |
| | | `0x04` | `SPI_STAT` | RO | Status (Busy, Done) |
| | | `0x08` | `SPI_TX` | WO | MOSI Data Register |
| | | `0x0C` | `SPI_RX` | RO | MISO Data Register |
| **I2C** | `0x43C20000` | `0x00` | `I2C_CTRL` | R/W | Control (Enable, Start, Stop) |
| | | `0x04` | `I2C_STAT` | RO | Status (ACK/NACK, Busy) |
| | | `0x08` | `I2C_ADDR` | R/W | Slave Address Register |
| | | `0x0C` | `I2C_DATA` | R/W | Data Register (TX/RX) |


## Final Test Results
The final integration test verified that the hardware (PL) and software (PS) communicate correctly using the robust driver.

* **UART:** Successful Loopback (0x55) via Auto-Retry logic.
* **SPI:** Successful Data Verification.

![Final Result](https://github.com/user-attachments/assets/1ab17375-1576-49f3-b0a3-7f7d30646321)


----

## Troubleshooting & Technical Challenges
During the hardware-software integration phase, several critical issues were encountered. Below are the engineering solutions applied to resolve them.

### 1. The "Ghost Data" Issue (Hardware-Software Timing Mismatch)
* **Problem:** During the UART loopback test, the CPU (PS) read the RX FIFO immediately after sending data, resulting in a `0x00` read error because the data hadn't physically arrived yet (Latency).
* **Analysis:** The CPU running at 650MHz is significantly faster than the UART baud rate (9600 bps). The software was polling the FIFO before the hardware could update the status.
* **Solution:** Implemented a **"Robust Retry Algorithm"** in the C driver.
    * Instead of a single read, the driver checks for valid data up to 10 times with micro-delays.
    * This approach successfully synchronized the high-speed CPU with the low-speed peripheral without using blocking interrupts.

### 2. Baud Rate Stability
* **Problem:** Initial tests showed intermittent framing errors due to potential clock division mismatches in software configuration.
* **Solution:** **Hardcoded the Divisor** (Values for 9600 bps @ 100MHz clock) directly in the Verilog RTL module.
    * This ensures that the hardware always wakes up in a known, stable state, eliminating software configuration errors.

### 3. I2C Physical Verification Constraint
* **Problem:** The I2C protocol requires an acknowledgment (**ACK**) bit from a slave device to complete a transaction. Since a physical slave device was not available for the demo, a simple wire loopback failed (NACK error).
* **Solution:**
    * **RTL Simulation:** Verified the I2C Master logic (Start/Stop/ACK) using a testbench simulating a slave response.
    * **Driver Verification:** Confirmed that the software correctly triggers the I2C engine and handles the NACK status flag as expected.


----

### Author
* **Seungyun Lee**
* University of Houston
