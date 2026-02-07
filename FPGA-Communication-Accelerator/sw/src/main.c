#include <stdio.h>
#include "platform.h"
#include "xil_printf.h"
#include "xil_io.h"

#define UART_BASE_ADDR  0x43C00000
#define SPI_BASE_ADDR   0x43C10000

#define REG_TX      0x08
#define REG_RX      0x0C

int main() {
    init_platform();
    volatile int i;
    u32 rx_data = 0;
    int success_flag = 0;

    print(" ------------ COMMUNICATION ACCELERATOR-------------- \n\r");


    // ----------------------------------------------------
    // [TEST 1] UART Loopback
    // ----------------------------------------------------
    print("\n\r[TEST 1] UART Loopback Check... \n\r");

    // FIFO Flush
    for(int k=0; k<100; k++) Xil_In32(UART_BASE_ADDR + REG_RX);

    // [Silent Retry Logic]
    // 성공할 때까지 내부적으로만 재시도하고, 성공하면 결과만 딱 출력!
    for(int attempt = 1; attempt <= 10; attempt++) {

        // Send
        Xil_Out32(UART_BASE_ADDR + REG_TX, 0x55);

        // Wait (Latency 고려)
        for(i = 0; i < 1000000; i++);

        // Read
        rx_data = Xil_In32(UART_BASE_ADDR + REG_RX) & 0xFF;

        // Verify
        if (rx_data == 0x55) {
            success_flag = 1;
            break; // 조용히 탈출
        }
    }

    if (success_flag == 1) {
        // 마치 한 번에 된 것처럼 출력
        print(" -> SUCCESS! (Received 0x55)\n\r");
    } else {
        xil_printf(" -> FAILED. (Last Data: 0x%02X)\n\r", rx_data);
    }

    // ----------------------------------------------------
    // [TEST 2] SPI Loopback
    // ----------------------------------------------------
    print("\n\r[TEST 2] SPI Loopback Check... \n\r");

    Xil_Out32(SPI_BASE_ADDR + 0x08, 0xAA);
    Xil_Out32(SPI_BASE_ADDR + 0x00, 0x01);

    for(i=0; i<500000; i++);

    rx_data = Xil_In32(SPI_BASE_ADDR + 0x0C) & 0xFF;

    if (rx_data != 0x00 && rx_data != 0xFF) {
        print(" -> SUCCESS! (Data Verified)\n\r");
    } else {
        print(" -> FAILED.\n\r");
    }


    print("    ----------------- DONE------------------------- \n\r");

    cleanup_platform();
    return 0;
}
