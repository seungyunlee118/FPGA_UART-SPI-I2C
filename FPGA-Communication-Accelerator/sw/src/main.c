#include <stdio.h>
#include "platform.h"
#include "xil_printf.h"
#include "xil_io.h"
#include "sleep.h"

// ----------------------------------------------------
// Register map (base address: Vivado Address Editor)
// ----------------------------------------------------
#define UART_BASE_ADDR  0x43C00000
#define SPI_BASE_ADDR   0x43C10000

// UART (uart_ip): AXI wrapper는 이 repo에 없음 — README의 레지스터 정의를 따름
#define UART_STAT       0x04
#define UART_TX         0x08
#define UART_RX         0x0C
#define UART_RX_EMPTY   (1u << 0)
#define UART_TX_FULL    (1u << 1)

// SPI (spi_ip.sv)
#define SPI_CTRL        0x00    // bit0 START (W1S: 1을 쓴 순간 한 번만 전송)
#define SPI_STAT        0x04    // bit0 BUSY, bit1 DONE (sticky, 1을 써서 clear)
#define SPI_TX          0x08
#define SPI_RX          0x0C
#define SPI_START       (1u << 0)
#define SPI_DONE        (1u << 1)

#define UART_TIMEOUT_US 5000    // 9600 bps 8N1 한 프레임 = 1.04 ms
#define SPI_TIMEOUT_US  100     // 1 MHz SCLK 한 프레임 = 8 us

// ----------------------------------------------------
// Drivers
// ----------------------------------------------------
static int uart_putc(u8 c)
{
    u32 t = UART_TIMEOUT_US;
    while (Xil_In32(UART_BASE_ADDR + UART_STAT) & UART_TX_FULL) {
        if (t-- == 0) return -1;
        usleep(1);
    }
    Xil_Out32(UART_BASE_ADDR + UART_TX, c);
    return 0;
}

// RX FIFO는 show-ahead: 비어 있을 때 읽으면 pop 없이 옛 값(처음엔 0x00)이 나온다.
// 예전 "ghost data"(한 바이트씩 밀려서 수신)의 원인이므로 반드시 RX_EMPTY를 먼저 본다.
static int uart_getc(u8 *c)
{
    u32 t = UART_TIMEOUT_US;
    while (Xil_In32(UART_BASE_ADDR + UART_STAT) & UART_RX_EMPTY) {
        if (t-- == 0) return -1;
        usleep(1);
    }
    *c = Xil_In32(UART_BASE_ADDR + UART_RX) & 0xFF;
    return 0;
}

static int spi_xfer(u8 tx, u8 *rx)
{
    u32 t = SPI_TIMEOUT_US;
    Xil_Out32(SPI_BASE_ADDR + SPI_TX, tx);
    Xil_Out32(SPI_BASE_ADDR + SPI_CTRL, SPI_START);
    while (!(Xil_In32(SPI_BASE_ADDR + SPI_STAT) & SPI_DONE)) {
        if (t-- == 0) return -1;
        usleep(1);
    }
    *rx = Xil_In32(SPI_BASE_ADDR + SPI_RX) & 0xFF;
    Xil_Out32(SPI_BASE_ADDR + SPI_STAT, SPI_DONE);           // DONE clear (W1C)
    return 0;
}

// 매번 다른 값 + bit0 != bit7 인 값 포함
// (같은 값을 반복하면 이전 바이트가 늦게 도착해도 구분이 안 되고, SPI LSB 버그는 bit0 != bit7 에서만 보였음)
static const u8 patterns[] = { 0x55, 0xAA, 0x00, 0xFF, 0x01, 0x80, 0xFE, 0x7F, 0xA5, 0x3C };
#define N_PATTERNS ((int)(sizeof(patterns) / sizeof(patterns[0])))

int main()
{
    u8  got;
    int i, errors;

    init_platform();
    print(" ------------ COMMUNICATION ACCELERATOR-------------- \n\r");

    // ----------------------------------------------------
    // [TEST 1] UART Loopback (JB pin 2 TX <-> pin 3 RX)
    // ----------------------------------------------------
    print("\n\r[TEST 1] UART Loopback Check... \n\r");

    // RX FIFO에 남은 데이터 비우기 (empty가 될 때까지만)
    for (i = 0; i < 64 && !(Xil_In32(UART_BASE_ADDR + UART_STAT) & UART_RX_EMPTY); i++)
        (void)Xil_In32(UART_BASE_ADDR + UART_RX);

    errors = 0;
    for (i = 0; i < N_PATTERNS; i++) {
        if (uart_putc(patterns[i]) != 0 || uart_getc(&got) != 0) {
            xil_printf("    0x%02X: timeout\n\r", patterns[i]);
            errors++;
        } else if (got != patterns[i]) {
            xil_printf("    sent 0x%02X, received 0x%02X\n\r", patterns[i], got);
            errors++;
        }
    }
    xil_printf(" -> %s (%d/%d bytes wrong)\n\r", errors ? "FAILED" : "SUCCESS", errors, N_PATTERNS);

    // ----------------------------------------------------
    // [TEST 2] SPI Loopback (JB pin 8 MOSI <-> pin 9 MISO)
    // loopback은 master가 자기 자신과 비교하는 것이므로 MOSI/MISO 각각의 정확성은
    // 시뮬레이션(tb_spi_ip, 독립 slave 모델)이 기준이다.
    // ----------------------------------------------------
    print("\n\r[TEST 2] SPI Loopback Check... \n\r");

    errors = 0;
    for (i = 0; i < N_PATTERNS; i++) {
        if (spi_xfer(patterns[i], &got) != 0) {
            xil_printf("    0x%02X: timeout\n\r", patterns[i]);
            errors++;
        } else if (got != patterns[i]) {
            xil_printf("    sent 0x%02X, received 0x%02X\n\r", patterns[i], got);
            errors++;
        }
    }
    xil_printf(" -> %s (%d/%d bytes wrong)\n\r", errors ? "FAILED" : "SUCCESS", errors, N_PATTERNS);

    print("    ----------------- DONE------------------------- \n\r");

    cleanup_platform();
    return 0;
}
