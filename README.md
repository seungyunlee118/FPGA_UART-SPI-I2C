# Hardware-Accelerated Multi-Protocol Controller (UART, SPI, I2C) on Zynq SoC
Project Overview
This project implements a Hardware-Accelerated Multi-Protocol Communication Controller supporting UART, SPI, and I2C on the Zybo Z7-20 (Zynq-7000 SoC).

Unlike standard software bit-banging, all communication logic is offloaded to the FPGA Programmable Logic (PL), ensuring precise timing and reduced CPU load. The system is managed by the ARM Cortex-A9 (PS) via a custom AXI4-Lite interface



# System Architecture & Key Features
![Image](https://github.com/user-attachments/assets/126f6e3a-6901-448a-b314-a692c3e30c43)

UART Controller:
- Full-duplex communication (TX/RX).
- Hardware-fixed baud rate (9600 bps) for stability.
- Robust Driver: Software retry logic to handle FIFO latency.

SPI Controller (Master):
- Master mode implementation.
- Configurable Clock Polarity/Phase (CPOL/CPHA).

I2C Controller (Master):
- Standard Master Mode implementation.
- 7-bit Addressing support.
- Note: Implemented in RTL & Driver, verifying logic via synthesis.

# 🔍 Pre-Synthesis Verification (RTL Simulation)
Before synthesis and bitstream generation, all protocol engines (UART, SPI, I2C) were rigorously verified using **Vivado Simulator**.
Testbenches were written to simulate Master-Slave transactions, ensuring timing constraints and logic correctness.

## 1. UART Simulation
Verified TX/RX baud rate timing and data integrity.
<img width="2046" height="574" alt="Image" src="https://github.com/user-attachments/assets/c45f4f66-ee7f-4543-9f07-67b63fb0d5e0" />

## 2. SPI Simulation (Mode 0)
Verified SCLK generation, MOSI/MISO data shifting, and Chip Select (CS) timing.
<img width="2058" height="1060" alt="Image" src="https://github.com/user-attachments/assets/9da928bc-54a4-44f3-8120-6e5ec25b40a4" />

## 3. I2C Simulation (Master Mode)
Although the physical loopback test was skipped due to the lack of a slave device, the **I2C Logic was fully verified in simulation**.
- Verified **Start/Stop conditions**.
- Verified **7-bit Addressing** and **ACK/NACK** signal handling.
<img width="1944" height="296" alt="Image" src="https://github.com/user-attachments/assets/f2f83d0e-7c32-4d52-8a9c-c7cee932cda8" />



# AXI4-Lite Register Map
The memory-mapped interface is accessible via the **ARM Cortex-A9 (PS)**.
Each protocol controller operates as an independent AXI Slave.

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


# Development Workflow: From Unit Test to System Integration
This project followed a strict Bottom-Up Design Methodology, ensuring the reliability of each module before final system integration.

## 1. Component Verification (FIFO & RTL)
Before integrating with AXI, the core logic (especially the Synchronous FIFO) was verified independently.

- FIFO Test: Verified Empty/Full flag logic and Read/Write pointer synchronization.
- RTL Simulation: Verified state machine transitions for UART/SPI/I2C using Vivado Simulator.
- 
<img width="2160" height="568" alt="Image" src="https://github.com/user-attachments/assets/f1a8ec9e-5cd8-4980-b7bf-50ec33d40bf6" />

## 2. IP Packaging (Modular Design)
Each protocol engine was wrapped with an AXI4-Lite interface and packaged as a standalone Custom IP in Vivado. This modular approach allows for reusability in other Zynq-based designs.

myip_uart_1.0
myip_spi_1.0
myip_i2c_1.0

(Vivado Block Design에서 IP들이 연결된 그림을 캡처해서 넣으세요)

## 3. Individual Software Testing (Vitis)
Before the final combined test, each IP was tested individually in Vitis to verify register access and basic functionality.
- UART Test: Verified Baud Rate generation and TX/RX loopback.
  <img width="547" height="640" alt="Image" src="https://github.com/user-attachments/assets/da5e8146-41eb-489c-8e03-eed0a162ef0c" />
- SPI Test: Verified CPOL/CPHA mode switching and Chip Select (CS) timing.
  <img width="718" height="368" alt="Image" src="https://github.com/user-attachments/assets/5aad89bc-bd98-4e5f-8b12-f0877e6bc6b5" />
  
# Hardware Setup & Pinout
Physical connections on the **Zybo Z7-20 Pmod Headers** are required for the Loopback Test.

| Protocol | Pmod Header | Pin # | FPGA Pin | Signal | Wiring for Loopback Test |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **UART** | **JB Top** | 1 | `V8` | **TX** | **Connect to Pin 2 (RX)** |
| | | 2 | `W8` | **RX** | **Connect to Pin 1 (TX)** |
| | | 3 | `U7` | *GND* | - |
| | | 4 | `V7` | *N/C* | - |
| **SPI** | **JB Bottom**| 7 | `Y7` | **SS** | (Chip Select) |
| | | 8 | `Y6` | **MOSI** | **Connect to Pin 9 (MISO)** |
| | | 9 | `V6` | **MISO** | **Connect to Pin 8 (MOSI)** |
| | | 10 | `W6` | **SCLK** | (Clock Output) |
| **I2C** | **JD Top** | 1 | `T14` | **SCL** | Connect to Slave SCL |
| | | 2 | `T15` | **SDA** | Connect to Slave SDA |

> **Note:**
> * **UART RX:** Configured with internal `PULLUP` to prevent floating signal errors.
> * **I2C:** Requires external pull-up resistors (or internal PULLUP enabled) and a valid Slave device for ACK generation.

# Software Implementation: Robust Driver
## 1. The "Retry" Logic (UART/SPI)
To solve hardware latency issues where the CPU reads the FIFO before data arrives, a Reliable Send/Recv Algorithm was implemented. It automatically retries transmission if the initial read returns invalid data (0x00), ensuring 100% success rate without manual intervention.

## 2. I2C Implementation Note
The I2C Controller logic and software driver are fully implemented. However, the Loopback Test for I2C was skipped in the final demo.
- Reason: Unlike UART/SPI, the I2C protocol requires an ACK (Acknowledge) bit from a physical Slave device to complete a transaction.
- Result: Simple wire loopback (SDA-SDA) is electrically insufficient for I2C protocol verification without a responding slave.



# Test Results
![Image](https://github.com/user-attachments/assets/1ab17375-1576-49f3-b0a3-7f7d30646321)


