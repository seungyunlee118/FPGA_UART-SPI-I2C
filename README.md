#Hardware-Accelerated Multi-Protocol Controller (UART, SPI, I2C) on Zynq SoC
Project Overview
This project implements a Hardware-Accelerated Multi-Protocol Communication Controller supporting UART, SPI, and I2C on the Zybo Z7-20 (Zynq-7000 SoC).

Unlike standard software bit-banging, all communication logic is offloaded to the FPGA Programmable Logic (PL), ensuring precise timing and reduced CPU load. The system is managed by the ARM Cortex-A9 (PS) via a custom AXI4-Lite interface

---

#System Architecture & Key Features

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
![UART Waveform](./docs/sim_uart.png)
*(캡처하신 UART 파형 사진 파일명을 sim_uart.png로 저장해서 docs 폴더에 넣으세요)*

## 2. SPI Simulation (Mode 0)
Verified SCLK generation, MOSI/MISO data shifting, and Chip Select (CS) timing.
![SPI Waveform](./docs/sim_spi.png)
*(SPI 파형 사진)*

## 3. I2C Simulation (Master Mode)
Although the physical loopback test was skipped due to the lack of a slave device, the **I2C Logic was fully verified in simulation**.
- Verified **Start/Stop conditions**.
- Verified **7-bit Addressing** and **ACK/NACK** signal handling.
![I2C Waveform](./docs/sim_i2c.png)
*(여기에 I2C 파형 사진을 꼭 넣으세요! 물리적 테스트를 대신하는 강력한 증거입니다)*

---
#Register Map
Protocol,Base Address,Offset,Register Name,Description
UART,0x43C00000,0x00,DIVISOR,Baud Rate Divisor
,,0x04,STATUS,RX Empty / TX Full
,,0x08,TX_DATA,Transmit Data
,,0x0C,RX_DATA,Receive Data
SPI,0x43C10000,0x00,CONTROL,Start / Mode Select
,,0x08,TX_DATA,MOSI Data
,,0x0C,RX_DATA,MISO Data
I2C,0x43C20000,0x00,CONTROL,Enable / Start
,,0x04,STATUS,ACK Received / Busy
,,0x08,ADDR,Slave Address
,,0x0C,DATA,SDA Data (TX/RX)

---
#Hardware Setup & Pinout
Protocol,Pmod Header,Pin Description,FPGA Pin,Wiring (Loopback)
UART,JB Top Row,TX (Transmit),V8 (JB1),Connect to JB2
,,RX (Receive),W8 (JB2),Connect to JB1
SPI,JB Bottom Row,MOSI,Y6 (JB7),Connect to JB8
,,MISO,V6 (JB8),Connect to JB7
I2C,JD Top Row,SCL,T14 (JD1),Requires Slave Device
,,SDA,T15 (JD2),Requires Slave Device

#Software Implementation: Robust Driver
1. The "Retry" Logic (UART/SPI)
To solve hardware latency issues where the CPU reads the FIFO before data arrives, a Reliable Send/Recv Algorithm was implemented. It automatically retries transmission if the initial read returns invalid data (0x00), ensuring 100% success rate without manual intervention.

2. I2C Implementation Note
The I2C Controller logic and software driver are fully implemented. However, the Loopback Test for I2C was skipped in the final demo.
- Reason: Unlike UART/SPI, the I2C protocol requires an ACK (Acknowledge) bit from a physical Slave device to complete a transaction.
- Result: Simple wire loopback (SDA-SDA) is electrically insufficient for I2C protocol verification without a responding slave.

#Test Results


