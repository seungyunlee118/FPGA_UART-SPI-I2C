# FPGA_UART-SPI-I2C
# 🚀 Hardware-Accelerated UART/SPI/I2C Communication Controller  
**FPGA (Zybo Z7-20) + ARM Processing System (Zynq) Integration**

This project implements a **hardware-accelerated multi-protocol communication controller (UART, SPI, I2C)** on the Programmable Logic (PL) of the Zynq SoC.  
The controller is fully accessible from the ARM Cortex-A9 Processing System (PS) via AXI4-Lite.  
Designed for high-speed embedded communication with low CPU load.


## 📂 Project Structure
📦 fpga-comm-controller
┣ 📁 rtl/
┃ ┣ uart/
┃ ┣ spi/
┃ ┣ i2c/
┃ ┗ axi_wrapper/
┣ 📁 sim/
┃ ┣ tb_uart/
┃ ┣ tb_spi/
┃ ┗ tb_i2c/
┣ 📁 vivado/
┃ ┗ project_files/
┣ 📁 software/
┃ ┣ baremetal/
┃ ┗ linux_app/
┣ 📁 docs/
┗ README.md

# 🎯 Project Goals
- Implement **UART, SPI, I2C protocol engines** in FPGA logic  
- Wrap hardware modules with a **custom AXI4-Lite slave interface**  
- Connect to **ARM PS (Cortex-A9)** for software configuration  
- Provide **high-throughput, low-latency** communication  
- Compare **PL-based controller vs PS-based driver performance**  
- Enable scalability for real embedded systems

# 🧩 System Architecture
ARM Cortex-A9 (PS)
│
AXI4-Lite
│
Programmable Logic (PL)
┌───────────────────────────────┐
│ AXI Register Map │
│ ├─ UART Engine (TX/RX) │
│ ├─ SPI Engine (Master) │
│ ├─ I2C Engine (Master) │
│ └─ Interrupt Logic │
└───────────────────────────────┘

# 🛠️ Hardware Components (RTL)
### UART Engine
- Configurable baud rate generator  
- TX/RX FIFOs (optional)  
- Framing error & parity error detection  
- Interrupt support  

### SPI Engine (Master)
- Modes: CPOL/CPHA  
- Adjustable SCLK divider  
- Full-duplex communication  

### I2C Engine (Master)
- Start/Stop generation  
- 7-bit addressing  
- ACK/NACK handling  
- Clock stretching support  

### AXI4-Lite Wrapper
- Register map  
- Control/status registers  
- Interrupt enable/status  
- Protocol selection  

---

# 📡 Register Map Overview
| Address | Name | Description |
|---------|------|-------------|
| 0x00 | CTRL | Protocol Select / Enable |
| 0x04 | STATUS | Busy / Error Flags |
| 0x08 | UART_TX | UART Transmit |
| 0x0C | UART_RX | UART Receive |
| 0x10 | SPI_TX | SPI MOSI Data |
| 0x14 | SPI_RX | SPI MISO Data |
| 0x18 | I2C_CMD | I2C Control Word |
| 0x1C | I2C_DATA | I2C TX/RX Data |

---

# 🧪 Simulation (ModelSim / Verilator)
Testbenches included:

- `tb_uart.sv`  
- `tb_spi.sv`  
- `tb_i2c.sv`

Simulation verifies:
- Protocol correctness  
- Timing accuracy  
- Error detection  
- AXI transactions  

---

# 🔧 FPGA Build (Vivado)
### Steps
1. Create new Vivado project (`Zybo Z7-20`)  
2. Import RTL modules  
3. Add custom AXI4-Lite IP via Vivado IP Packager  
4. Integrate in Block Design  
5. Connect to ZYNQ PS (AXI GP Master)  
6. Generate Bitstream  
7. Export hardware to **Vitis**

---

# 💻 Software (Vitis)
### Bare-metal application features:
- Initialize AXI communication controller  
- Select protocol (UART/SPI/I2C)  
- Transmit & receive data  
- Performance benchmarking  
- Interrupt handling  

### Linux optional:
- Device driver  
- User-space test app  

---

# 📊 Performance Metrics
This project compares **software-only communication (PS)** vs **hardware-accelerated (PL)**.

Metrics:
- Max throughput  
- Latency  
- CPU usage  
- Interrupt overhead  

Results displayed in `/docs/performance_report.md`.

---

# 🧷 Future Improvements
- Add DMA for high-speed transfers  
- Add I2C slave mode  
- Support SPI slave mode  
- UVM-based verification environment  
- Python automated testing suite  

---

# 📄 License
MIT License

---

# 🙋‍♂️ Author
Lee Seungyun  
Zybo Z7-20 FPGA / Embedded Systems / Digital Design / Verification  
