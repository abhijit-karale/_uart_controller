// -----------------------------------------------------------------------------
// Module      : uart_controller
// Description : Simple UART controller (8 data bits, no parity, 1 stop bit).
//               Contains independent transmitter (uart_tx) and receiver
//               (uart_rx) sharing a common baud-rate generator.
// Author      : Abhijit Karale
// -----------------------------------------------------------------------------
module uart_controller #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 115_200
) (
    input  logic       clk,
    input  logic       rst_n,

    // TX side
    input  logic       tx_start,
    input  logic [7:0] tx_data,
    output logic       tx_busy,
    output logic       tx_serial,

    // RX side
    input  logic       rx_serial,
    output logic [7:0] rx_data,
    output logic       rx_valid,
    output logic       rx_frame_error
);

    localparam integer BAUD_DIV = CLK_FREQ / BAUD_RATE;

    // -------------------- Baud tick generator --------------------
    logic [$clog2(BAUD_DIV)-1:0] baud_cnt;
    logic baud_tick;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            baud_cnt <= '0;
        end else if (baud_cnt == BAUD_DIV-1) begin
            baud_cnt <= '0;
        end else begin
            baud_cnt <= baud_cnt + 1'b1;
        end
    end
    assign baud_tick = (baud_cnt == BAUD_DIV-1);

    // -------------------- Transmitter FSM --------------------
    typedef enum logic [1:0] {TX_IDLE, TX_START, TX_DATA, TX_STOP} tx_state_t;
    tx_state_t tx_state;
    logic [2:0] tx_bit_idx;
    logic [7:0] tx_shift;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state   <= TX_IDLE;
            tx_serial  <= 1'b1;
            tx_busy    <= 1'b0;
            tx_bit_idx <= 3'd0;
            tx_shift   <= 8'd0;
        end else begin
            case (tx_state)
                TX_IDLE: begin
                    tx_serial <= 1'b1;
                    if (tx_start) begin
                        tx_shift  <= tx_data;
                        tx_busy   <= 1'b1;
                        tx_state  <= TX_START;
                    end
                end
                TX_START: begin
                    if (baud_tick) begin
                        tx_serial  <= 1'b0; // start bit
                        tx_state   <= TX_DATA;
                        tx_bit_idx <= 3'd0;
                    end
                end
                TX_DATA: begin
                    if (baud_tick) begin
                        tx_serial <= tx_shift[tx_bit_idx];
                        if (tx_bit_idx == 3'd7)
                            tx_state <= TX_STOP;
                        else
                            tx_bit_idx <= tx_bit_idx + 1'b1;
                    end
                end
                TX_STOP: begin
                    if (baud_tick) begin
                        tx_serial <= 1'b1; // stop bit
                        tx_busy   <= 1'b0;
                        tx_state  <= TX_IDLE;
                    end
                end
                default: tx_state <= TX_IDLE;
            endcase
        end
    end

    // -------------------- Receiver FSM --------------------
    typedef enum logic [1:0] {RX_IDLE, RX_START, RX_DATA, RX_STOP} rx_state_t;
    rx_state_t rx_state;
    logic [2:0] rx_bit_idx;
    logic [7:0] rx_shift;
    logic [$clog2(BAUD_DIV)-1:0] rx_baud_cnt;

    // Independent (mid-bit-sampling) counter for RX to avoid needing a
    // synchronized shared baud tick edge - typical real UART RX design.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_state       <= RX_IDLE;
            rx_bit_idx     <= 3'd0;
            rx_shift       <= 8'd0;
            rx_valid       <= 1'b0;
            rx_frame_error <= 1'b0;
            rx_baud_cnt    <= '0;
            rx_data        <= 8'd0;
        end else begin
            rx_valid <= 1'b0;
            case (rx_state)
                RX_IDLE: begin
                    rx_baud_cnt <= '0;
                    if (!rx_serial) begin // falling edge = start bit detected
                        rx_state <= RX_START;
                    end
                end
                RX_START: begin
                    if (rx_baud_cnt == (BAUD_DIV/2)) begin
                        // sample mid-bit to confirm valid start bit
                        if (!rx_serial) begin
                            rx_baud_cnt <= '0;
                            rx_state    <= RX_DATA;
                            rx_bit_idx  <= 3'd0;
                        end else begin
                            rx_state <= RX_IDLE; // glitch, not a real start bit
                        end
                    end else begin
                        rx_baud_cnt <= rx_baud_cnt + 1'b1;
                    end
                end
                RX_DATA: begin
                    if (rx_baud_cnt == BAUD_DIV-1) begin
                        rx_baud_cnt        <= '0;
                        rx_shift[rx_bit_idx] <= rx_serial;
                        if (rx_bit_idx == 3'd7)
                            rx_state <= RX_STOP;
                        else
                            rx_bit_idx <= rx_bit_idx + 1'b1;
                    end else begin
                        rx_baud_cnt <= rx_baud_cnt + 1'b1;
                    end
                end
                RX_STOP: begin
                    if (rx_baud_cnt == BAUD_DIV-1) begin
                        rx_data        <= rx_shift;
                        rx_valid       <= 1'b1;
                        rx_frame_error <= ~rx_serial; // stop bit should be 1
                        rx_state       <= RX_IDLE;
                    end else begin
                        rx_baud_cnt <= rx_baud_cnt + 1'b1;
                    end
                end
                default: rx_state <= RX_IDLE;
            endcase
        end
    end

endmodule
