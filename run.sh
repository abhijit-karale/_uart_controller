#!/bin/bash
set -e
iverilog -g2012 -o sim.out rtl/uart_controller.sv tb/tb_uart_controller.sv
vvp sim.out
python3 vcd_plot.py waveform/uart_controller.vcd waveform/uart_controller_waveform.png \
    clk rst_n tx_start tx_data tx_busy tx_serial rx_data rx_valid --window 0 400
echo "Done. Open waveform/uart_controller.vcd in GTKWave for full interactive waveform."
    
