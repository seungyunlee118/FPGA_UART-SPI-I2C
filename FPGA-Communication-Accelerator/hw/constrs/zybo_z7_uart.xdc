
## [1] UART 
set_property -dict { PACKAGE_PIN W8    IOSTANDARD LVCMOS33 } [get_ports { uart_tx }]; # JB2
set_property -dict { PACKAGE_PIN U7    IOSTANDARD LVCMOS33 } [get_ports { uart_rx }]; # JB3


## [2] SPI 
set_property -dict { PACKAGE_PIN Y7    IOSTANDARD LVCMOS33 } [get_ports { spi_ss }];   # JB7
set_property -dict { PACKAGE_PIN Y6    IOSTANDARD LVCMOS33 } [get_ports { spi_mosi }]; # JB8
set_property -dict { PACKAGE_PIN V6    IOSTANDARD LVCMOS33 } [get_ports { spi_miso }]; # JB9
set_property -dict { PACKAGE_PIN W6    IOSTANDARD LVCMOS33 } [get_ports { spi_sclk }]; # JB10


## [3] I2C JD
set_property -dict { PACKAGE_PIN T14   IOSTANDARD LVCMOS33 } [get_ports { i2c_scl }]; #JD1
set_property -dict { PACKAGE_PIN T15   IOSTANDARD LVCMOS33 } [get_ports { i2c_sda }]; #JD2
set_property PULLUP true [get_ports { i2c_scl }]
set_property PULLUP true [get_ports { i2c_sda }]