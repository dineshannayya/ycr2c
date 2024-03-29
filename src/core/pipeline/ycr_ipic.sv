/*****************************************************************************************************
 * Copyright (c) 2024 SiPlusPlus Semiconductor
 *
 * FileContributor: Dinesh Annayya <dinesha@opencores.org>                       
 * FileContributor: Dinesh Annayya <dinesh@siplusplus.com>                       
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 ***************************************************************************************************/
/****************************************************************************************************
  yifive Integrated Programmable Interrupt Controller (IPIC)          
                                                                      
                                                                      
  Description:                                                        
     Integrated Programmable Interrupt Controller (IPIC)              
                                                                      
 Functionality:                                                       
 - Synchronizes IRQ lines (optional)                                  
 - Detects level and edge (with optional lines inversion) of IRQ lines
 - Setups interrupts handling (mode, inversion, enable)               
 - Provides information about pending interrupts and interrupts       
   currently in service                                               
 - Generates interrupt request to CSR                                 
                                                                      
 Structure:                                                           
 - IRQ lines handling (synchronization, level and edge detection) logic
 - IPIC registers:                                                    
   - CISV                                                             
   - CICSR                                                            
   - EOI                                                              
   - SOI                                                              
   - IDX                                                              
   - IPR                                                              
   - ISVR                                                             
   - IER                                                              
   - IMR                                                              
   - IINVR                                                            
   - ICSR                                                             
 - Priority interrupt generation logic                                
                                                                      
  To Do:                                                              
    nothing                                                           
                                                                      
  Author(s):                                                  
          - syntacore, https://github.com/syntacore/scr1                   
          - Dinesh Annayya <dinesha@opencores.org>               
          - Dinesh Annayya <dinesh@siplusplus.com>               
                                                                      
  Revision :                                                          
     v0:    Jan 2021- Initial version picked from                     
            https://github.com/syntacore/scr1                         
     v1:    June 7, 2021, Dinesh A                                    
             opentool(iverilog/yosys) related cleanup                 
     v2:    Aug 21, 2022, Dinesh A                                    
            Interrupt support increse from 16 to 32                   
                                                                      
 ***************************************************************************************************/


`include "ycr_arch_description.svh"

`ifdef YCR_IPIC_EN

`include "ycr_ipic.svh"

module ycr_ipic
(
    // Common
    input   logic                                   rst_n,                  // IPIC reset
    input   logic                                   clk,                    // IPIC clock

    // External Interrupt lines
    input   logic [YCR_IRQ_LINES_NUM-1:0]          soc2ipic_irq_lines_i,   // External IRQ lines

    // CSR <-> IPIC interface
    input   logic                                   csr2ipic_r_req_i,       // IPIC read request
    input   logic                                   csr2ipic_w_req_i,       // IPIC write request
    input   logic [2:0]                             csr2ipic_addr_i,        // IPIC address
    input   logic [`YCR_XLEN-1:0]                  csr2ipic_wdata_i,       // IPIC write data
    output  logic [`YCR_XLEN-1:0]                  ipic2csr_rdata_o,       // IPIC read data
    output  logic                                   ipic2csr_irq_m_req_o    // IRQ request from IPIC
);

//-------------------------------------------------------------------------------
// Local types declaration
//-------------------------------------------------------------------------------
typedef struct packed { // cp.6
    logic                                   vd;
    logic                                   idx;
} type_ycr_search_one_2_s;

typedef struct packed { // cp.6
    logic                                   vd;
    logic   [YCR_IRQ_VECT_WIDTH-1:0]       idx;
} type_ycr_search_one_16_s;

typedef struct packed {
    logic                                   ip;
    logic                                   ie;
    logic                                   im;
    logic                                   inv;
    logic                                   is;
    logic   [YCR_IRQ_LINES_WIDTH-1:0]      line;
} type_ycr_icsr_m_s;

typedef struct packed {
    logic                                   ip;
    logic                                   ie;
} type_ycr_cicsr_s;

//-------------------------------------------------------------------------------
// Local functions declaration
//-------------------------------------------------------------------------------

function automatic type_ycr_search_one_2_s ycr_search_one_2(
    input   logic   [1:0] din
);
    type_ycr_search_one_2_s tmp;
begin
    tmp.vd  = |din;
    tmp.idx = ~din[0];
    ycr_search_one_2 =  tmp;
end
endfunction

function automatic type_ycr_search_one_16_s ycr_search_one_16(
    input   logic [15:0]    din
);
    logic [7:0]         stage1_vd;
    logic [3:0]         stage2_vd;
    logic [1:0]         stage3_vd;

    logic               stage1_idx [7:0];
    logic [1:0]         stage2_idx [3:0];
    logic [2:0]         stage3_idx [1:0];
    type_ycr_search_one_16_s result;
    type_ycr_search_one_2_s tmp;
    integer i; // cp.17
begin
    // Stage 1
    for (i=0; i<8; i=i+1) begin
        tmp = ycr_search_one_2(din[(i+1)*2-1-:2]);
        stage1_vd[i]  = tmp.vd;
        stage1_idx[i] = tmp.idx;
    end

    // Stage 2
    for (i=0; i<4; i=i+1) begin
        tmp = ycr_search_one_2(stage1_vd[(i+1)*2-1-:2]);
        stage2_vd[i]  = tmp.vd;
        stage2_idx[i] = (~tmp.idx) ? {tmp.idx, stage1_idx[2*i]} : {tmp.idx, stage1_idx[2*i+1]};
    end

    // Stage 3
    for (i=0; i<2; i=i+1) begin
        tmp = ycr_search_one_2(stage2_vd[(i+1)*2-1-:2]);
        stage3_vd[i]  = tmp.vd;
        stage3_idx[i] = (~tmp.idx) ? {tmp.idx, stage2_idx[2*i]} : {tmp.idx, stage2_idx[2*i+1]};
    end

    // Stage 4
    result.vd = |stage3_vd;
    result.idx = (stage3_vd[0]) ? {1'b0, stage3_idx[0]} : {1'b1, stage3_idx[1]};

    ycr_search_one_16 = result;
end
endfunction

//------------------------------------------------------------------------------
// Local signals declaration
//------------------------------------------------------------------------------

// IRQ lines handling signals
//------------------------------------------------------------------------------

logic [YCR_IRQ_VECT_NUM-1:0]           irq_lines;              // Internal IRQ lines
`ifdef YCR_IPIC_SYNC_EN
logic [YCR_IRQ_VECT_NUM-1:0]           irq_lines_sync;
`endif // YCR_IPIC_SYNC_EN
logic [YCR_IRQ_VECT_NUM-1:0]           irq_lines_dly;          // Internal IRQ lines delayed for 1 cycle
logic [YCR_IRQ_VECT_NUM-1:0]           irq_edge_detected;      // IRQ lines edge detected flags
logic [YCR_IRQ_VECT_NUM-1:0]           irq_lvl;                // IRQ lines level

// IPIC registers
//------------------------------------------------------------------------------

// CISV register
logic                                   ipic_cisv_upd;          // Current Interrupt Vecotr in Service register update
logic [YCR_IRQ_VECT_WIDTH-1:0]         ipic_cisv_ff;           // Current Interrupt Vector in Service register
logic [YCR_IRQ_VECT_WIDTH-1:0]         ipic_cisv_next;         // Current Interrupt Vector in Service register next value

// CICS register (CICSR)
logic                                   cicsr_wr_req;           // Write request to Current Interrupt Control Status register
type_ycr_cicsr_s                       ipic_cicsr;             // Current Interrupt Control Status register

// EOI register
logic                                   eoi_wr_req;             // Write request to End of Interrupt register
logic                                   ipic_eoi_req;           // Request to end the interrupt that is currently in service

// SOI register
logic                                   soi_wr_req;             // Write request to Start of Interrupt register
logic                                   ipic_soi_req;           // Request to start the interrupt

// IDX register (IDXR)
logic                                   idxr_wr_req;            // Write request to Index register
logic [YCR_IRQ_IDX_WIDTH-1:0]          ipic_idxr_ff;           // Index register

// IP register (IPR)
logic                                   ipic_ipr_upd;           // Interrupt pending register update
logic [YCR_IRQ_VECT_NUM-1:0]           ipic_ipr_ff;            // Interrupt pending register
logic [YCR_IRQ_VECT_NUM-1:0]           ipic_ipr_next;          // Interrupt pending register next value
logic [YCR_IRQ_VECT_NUM-1:0]           ipic_ipr_clr_cond;      // Interrupt pending clear condition
logic [YCR_IRQ_VECT_NUM-1:0]           ipic_ipr_clr_req;       // Interrupt pending clear request
logic [YCR_IRQ_VECT_NUM-1:0]           ipic_ipr_clr;           // Interrupt pending clear operation

// ISV register (ISVR)
logic                                   ipic_isvr_upd;          // Interrupt Serviced register update
logic [YCR_IRQ_VECT_NUM-1:0]           ipic_isvr_ff;           // Interrupt Serviced register
logic [YCR_IRQ_VECT_NUM-1:0]           ipic_isvr_next;         // Interrupt Serviced register next value

// IE register (IER)
logic                                   ipic_ier_upd;           // Interrupt enable register update
logic [YCR_IRQ_VECT_NUM-1:0]           ipic_ier_ff;            // Interrupt enable register
logic [YCR_IRQ_VECT_NUM-1:0]           ipic_ier_next;          // Interrupt enable register next value

// IM register (IMR)
logic [YCR_IRQ_VECT_NUM-1:0]           ipic_imr_ff;            // Interrupt mode register
logic [YCR_IRQ_VECT_NUM-1:0]           ipic_imr_next;          // Interrupt mode register next value

// IINV register (IINVR)
logic [YCR_IRQ_VECT_NUM-1:0]           ipic_iinvr_ff;          // Interrupt Inversion register
logic [YCR_IRQ_VECT_NUM-1:0]           ipic_iinvr_next;        // Interrupt Inversion register next value

// ICS register (ICSR)
logic                                   icsr_wr_req;            // Write request to Interrupt Control Status register
type_ycr_icsr_m_s                      ipic_icsr;              // Interrupt Control Status register

// Priority interrupt generation signals
//------------------------------------------------------------------------------

// Serviced interrupt signals
logic                                   irq_serv_vd;            // There is an interrupt in service
logic [YCR_IRQ_VECT_WIDTH-1:0]         irq_serv_idx;           // Index of an interrupt that is currently in service

// Requested interrupt signals
logic                                   irq_req_vd;             // There is a requested interrupt
logic [YCR_IRQ_VECT_WIDTH-1:0]         irq_req_idx;            // Index of a requested interrupt

// Interrupt requested on "end of the previous interrupt" signals
logic                                   irq_eoi_req_vd;         // There is a requested interrupt when the previous one has ended
logic [YCR_IRQ_VECT_WIDTH-1:0]         irq_eoi_req_idx;        // Index of an interrupt requested when the previous one has ended

logic [YCR_IRQ_VECT_NUM-1:0]           irq_req_v;              // Vector of interrupts that are pending and enabled

logic                                   irq_start_vd;           // Request to start an interrupt is valid
logic                                   irq_hi_prior_pnd;       // There is a pending IRQ with a priority higher than of the interrupt that is currently in service

type_ycr_search_one_16_s               irr_priority;           // Structure for vd and idx of the requested interrupt
type_ycr_search_one_16_s               isvr_priority_eoi;      // Structure for vd and idx of the interrupt requested when the previous interrupt has ended
logic [YCR_IRQ_VECT_NUM-1:0]           ipic_isvr_eoi;          // Interrupt Serviced register when the previous interrupt has ended

//------------------------------------------------------------------------------
// IRQ lines handling
//------------------------------------------------------------------------------

`ifdef YCR_IPIC_SYNC_EN
// IRQ lines synchronization
//------------------------------------------------------------------------------

always_ff @(posedge clk, negedge rst_n) begin
    if (~rst_n) begin
        irq_lines_sync <= '0;
        irq_lines      <= '0;
    end else begin
        irq_lines_sync <= soc2ipic_irq_lines_i;
        irq_lines      <= irq_lines_sync;
    end
end
`else // YCR_IPIC_SYNC_EN
assign irq_lines = soc2ipic_irq_lines_i;
`endif // YCR_IPIC_SYNC_EN

// IRQ lines level detection
//------------------------------------------------------------------------------

assign irq_lvl = irq_lines ^ ipic_iinvr_next;

// IRQ lines edge detection
//------------------------------------------------------------------------------

always_ff @(negedge rst_n, posedge clk) begin
    if (~rst_n) begin
        irq_lines_dly <= '0;
    end else begin
        irq_lines_dly <= irq_lines;
    end
end

assign irq_edge_detected = (irq_lines_dly ^ irq_lines) & irq_lvl;

//------------------------------------------------------------------------------
// IPIC registers read/write interface
//------------------------------------------------------------------------------

// Read Logic
//------------------------------------------------------------------------------

// Read data multiplexer
always_comb begin
    ipic2csr_rdata_o  = '0;

    if (csr2ipic_r_req_i) begin
        case (csr2ipic_addr_i)
            YCR_IPIC_CISV : begin
                ipic2csr_rdata_o[YCR_IRQ_VECT_WIDTH-1:0] = irq_serv_vd
                                                          ? ipic_cisv_ff
                                                          : YCR_IRQ_VOID_VECT_NUM;
            end
            YCR_IPIC_CICSR : begin
                ipic2csr_rdata_o[YCR_IPIC_ICSR_IP]  = ipic_cicsr.ip;
                ipic2csr_rdata_o[YCR_IPIC_ICSR_IE]  = ipic_cicsr.ie;
            end
            YCR_IPIC_IPR : begin
                ipic2csr_rdata_o = `YCR_XLEN'(ipic_ipr_ff);
            end
            YCR_IPIC_ISVR : begin
                ipic2csr_rdata_o = `YCR_XLEN'(ipic_isvr_ff);
            end
            YCR_IPIC_EOI,
            YCR_IPIC_SOI : begin
                ipic2csr_rdata_o = '0;
            end
            YCR_IPIC_IDX : begin
                ipic2csr_rdata_o = `YCR_XLEN'(ipic_idxr_ff);
            end
            YCR_IPIC_ICSR : begin
                ipic2csr_rdata_o[YCR_IPIC_ICSR_IP]      = ipic_icsr.ip;
                ipic2csr_rdata_o[YCR_IPIC_ICSR_IE]      = ipic_icsr.ie;
                ipic2csr_rdata_o[YCR_IPIC_ICSR_IM]      = ipic_icsr.im;
                ipic2csr_rdata_o[YCR_IPIC_ICSR_INV]     = ipic_icsr.inv;
                ipic2csr_rdata_o[YCR_IPIC_ICSR_PRV_MSB:
                                 YCR_IPIC_ICSR_PRV_LSB] = YCR_IPIC_PRV_M;
                ipic2csr_rdata_o[YCR_IPIC_ICSR_IS]      = ipic_icsr.is;
                ipic2csr_rdata_o[YCR_IPIC_ICSR_LN_MSB-1:
                                 YCR_IPIC_ICSR_LN_LSB]  = ipic_icsr.line;
            end
            default : begin
                ipic2csr_rdata_o = 'x;
            end
        endcase
    end
end

// Write logic
//------------------------------------------------------------------------------

// Register selection
always_comb begin
    cicsr_wr_req = 1'b0;
    eoi_wr_req   = 1'b0;
    soi_wr_req   = 1'b0;
    idxr_wr_req  = 1'b0;
    icsr_wr_req  = 1'b0;
    if (csr2ipic_w_req_i) begin
        case (csr2ipic_addr_i)
            YCR_IPIC_CISV : begin end // Quiet Read-Only
            YCR_IPIC_CICSR: cicsr_wr_req = 1'b1;
            YCR_IPIC_IPR  : begin end
            YCR_IPIC_ISVR : begin end // Quiet Read-Only
            YCR_IPIC_EOI  : eoi_wr_req   = 1'b1;
            YCR_IPIC_SOI  : soi_wr_req   = 1'b1;
            YCR_IPIC_IDX  : idxr_wr_req  = 1'b1;
            YCR_IPIC_ICSR : icsr_wr_req  = 1'b1;
            default : begin // Illegal IPIC register address
                cicsr_wr_req = 'x;
                eoi_wr_req   = 'x;
                soi_wr_req   = 'x;
                idxr_wr_req  = 'x;
                icsr_wr_req  = 'x;
            end
        endcase
    end
end

//------------------------------------------------------------------------------
// IPIC registers
//------------------------------------------------------------------------------
//
 // Registers:
 // - Current Interrupt Vector in Service (CISV) register
 // - Current Interrupt Control Status (CICSR) register
 // - End of Interrupt (EOI) register
 // - Start of Interrupt (SOI) register
 // - Index (IDX) register
 // - Interrupt Pending Register (IPR)
 // - Interrupt Serviced Register (ISVR)
 // - Interrupt Enable Register (IER)
 // - Interrupt Mode Register (IMR)
 // - Interrupt Inversion Register (IINVR)
 // - Interrupt Control Status Register (ICSR)
//

// CISV register
//------------------------------------------------------------------------------
// Contains number of the interrupt vector currently in service. When no
// interrupts are in service, contains number of the void interrupt vector (0x10).
// The register cannot contain all 0's

assign ipic_cisv_upd = irq_start_vd | ipic_eoi_req;

always_ff @(negedge rst_n, posedge clk) begin
    if (~rst_n) begin
        ipic_cisv_ff <= YCR_IRQ_VOID_VECT_NUM;
    end else if (ipic_cisv_upd) begin
        ipic_cisv_ff <= ipic_cisv_next;
    end
end

assign ipic_cisv_next = irq_start_vd ? irq_req_idx
                      : ipic_eoi_req ? irq_eoi_req_vd ? irq_eoi_req_idx
                                                      : YCR_IRQ_VOID_VECT_NUM
                                     : 1'b0;

assign irq_serv_idx = ipic_cisv_ff[YCR_IRQ_VECT_WIDTH-2:0];
assign irq_serv_vd  = ~ipic_cisv_ff[YCR_IRQ_VECT_WIDTH-1];

// CICSR register
//------------------------------------------------------------------------------
// Shows whether the interrupt currently in service is pending and enabled

assign ipic_cicsr.ip = ipic_ipr_ff[irq_serv_idx] & irq_serv_vd;
assign ipic_cicsr.ie = ipic_ier_ff[irq_serv_idx] & irq_serv_vd;

// EOI register
//------------------------------------------------------------------------------
// Writing any value to EOI register ends the interrupt which is currently in service

assign ipic_eoi_req = eoi_wr_req & irq_serv_vd;

// SOI register
//------------------------------------------------------------------------------
// Writing any value to SOI activates start of interrupt if one of the following
// conditions is true:
// - There is at least one pending interrupt with IE and ISR is zero
// - There is at least one pending interrupt with IE and higher priority than the
// interrupts currently in service

assign ipic_soi_req = soi_wr_req & irq_req_vd;

// IDX register
//------------------------------------------------------------------------------
// Defines the number of interrupt vector which is accessed through the IPIC_ICSR
// register

always_ff @(negedge rst_n, posedge clk) begin
    if (~rst_n) begin
        ipic_idxr_ff <= '0;
    end else if (idxr_wr_req) begin
        ipic_idxr_ff <= csr2ipic_wdata_i[YCR_IRQ_IDX_WIDTH-1:0];
    end
end

// IPR
//------------------------------------------------------------------------------
// For every IRQ line shows whether there is a pending interrupt

assign ipic_ipr_upd = (ipic_ipr_next != ipic_ipr_ff);

always_ff @(negedge rst_n, posedge clk) begin
    if (~rst_n) begin
        ipic_ipr_ff <= '0;
    end else if (ipic_ipr_upd) begin
        ipic_ipr_ff <= ipic_ipr_next;
    end
end

always_comb begin
    ipic_ipr_clr_req = '0;
    if (csr2ipic_w_req_i) begin
        case (csr2ipic_addr_i)
            YCR_IPIC_CICSR: ipic_ipr_clr_req[irq_serv_idx] = csr2ipic_wdata_i[YCR_IPIC_ICSR_IP]
                                                            & irq_serv_vd;
            YCR_IPIC_IPR  : ipic_ipr_clr_req               = csr2ipic_wdata_i[YCR_IRQ_VECT_NUM-1:0];
            YCR_IPIC_SOI  : ipic_ipr_clr_req[irq_req_idx]  = irq_req_vd;
            YCR_IPIC_ICSR : ipic_ipr_clr_req[ipic_idxr_ff] = csr2ipic_wdata_i[YCR_IPIC_ICSR_IP];
            default        : begin end
        endcase
    end
end

assign ipic_ipr_clr_cond = ~irq_lvl | ipic_imr_next;
assign ipic_ipr_clr      = ipic_ipr_clr_req & ipic_ipr_clr_cond;
integer i;
always_comb begin
    ipic_ipr_next = '0;
    for (i=0; i<YCR_IRQ_VECT_NUM; i=i+1) begin
        ipic_ipr_next[i] = ipic_ipr_clr[i] ? 1'b0
                         : ~ipic_imr_ff[i] ? irq_lvl[i]
                                           : ipic_ipr_ff[i] | irq_edge_detected[i];
    end
end

// ISVR
//------------------------------------------------------------------------------
// For every IRQ line shows whether the interrupt is in service or not

assign ipic_isvr_upd = irq_start_vd | ipic_eoi_req;

always_ff @(negedge rst_n, posedge clk) begin
    if (~rst_n) begin
        ipic_isvr_ff <= '0;
    end else if (ipic_isvr_upd) begin
        ipic_isvr_ff <= ipic_isvr_next;
    end
end

always_comb begin
    ipic_isvr_eoi = ipic_isvr_ff;
    if (irq_serv_vd) begin
        ipic_isvr_eoi[irq_serv_idx] = 1'b0;
    end
end

always_comb begin
    ipic_isvr_next = ipic_isvr_ff;
    if (irq_start_vd) begin
        ipic_isvr_next[irq_req_idx] = 1'b1;
    end else if (ipic_eoi_req) begin
        ipic_isvr_next = ipic_isvr_eoi;
    end
end

// IER
//------------------------------------------------------------------------------
// Enables/disables interrupt for every IRQ line

assign ipic_ier_upd = cicsr_wr_req | icsr_wr_req;

always_ff @(negedge rst_n, posedge clk) begin
    if (~rst_n) begin
        ipic_ier_ff <= '0;
    end else if (ipic_ier_upd) begin
        ipic_ier_ff <= ipic_ier_next;
    end
end

always_comb begin
    ipic_ier_next = ipic_ier_ff;
    if (cicsr_wr_req) begin
        ipic_ier_next[irq_serv_idx] = irq_serv_vd
                                    ? csr2ipic_wdata_i[YCR_IPIC_ICSR_IE]
                                    : ipic_ier_ff[irq_serv_idx];
    end else if (icsr_wr_req) begin
        ipic_ier_next[ipic_idxr_ff] = csr2ipic_wdata_i[YCR_IPIC_ICSR_IE];
    end
end

// IMR
//------------------------------------------------------------------------------
// For every IRQ line sets either Level (0) or Edge (1) detection

always_ff @(negedge rst_n, posedge clk) begin
    if (~rst_n) begin
        ipic_imr_ff <= '0;
    end else if (icsr_wr_req) begin
        ipic_imr_ff <= ipic_imr_next;
    end
end

always_comb begin
    ipic_imr_next = ipic_imr_ff;
    if (icsr_wr_req) begin
        ipic_imr_next[ipic_idxr_ff] = csr2ipic_wdata_i[YCR_IPIC_ICSR_IM];
    end
end

// IINVR
//------------------------------------------------------------------------------
// For every IRQ line defines whether it should be inverted or not

always_ff @(negedge rst_n, posedge clk) begin
    if (~rst_n) begin
        ipic_iinvr_ff <= '0;
    end else if (icsr_wr_req) begin
        ipic_iinvr_ff <= ipic_iinvr_next;
    end
end

always_comb begin
    ipic_iinvr_next = ipic_iinvr_ff;
    if (icsr_wr_req) begin
        ipic_iinvr_next[ipic_idxr_ff] = csr2ipic_wdata_i[YCR_IPIC_ICSR_INV];
    end
end

// ICSR
//------------------------------------------------------------------------------
// Holds control and status information about the interrupt defined by Index Register

assign ipic_icsr.ip    = ipic_ipr_ff  [ipic_idxr_ff];
assign ipic_icsr.ie    = ipic_ier_ff  [ipic_idxr_ff];
assign ipic_icsr.im    = ipic_imr_ff  [ipic_idxr_ff];
assign ipic_icsr.inv   = ipic_iinvr_ff[ipic_idxr_ff];
assign ipic_icsr.is    = ipic_isvr_ff [ipic_idxr_ff];
assign ipic_icsr.line  = YCR_IRQ_LINES_WIDTH'(ipic_idxr_ff);

//------------------------------------------------------------------------------
// Priority IRQ generation logic
//------------------------------------------------------------------------------

assign irq_req_v = ipic_ipr_ff & ipic_ier_ff;

/*** Modified for Yosys handing typedef in function - dinesha
assign irr_priority        = ycr_search_one_16(irq_req_v);
assign irq_req_vd          = irr_priority.vd;
assign irq_req_idx         = irr_priority.idx;
****/

always_comb 
begin
    casex(irq_req_v)
	    32'bxxxx_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx_xxx1 : irq_req_idx = 0;
	    32'bxxxx_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx_xx10 : irq_req_idx = 1;
	    32'bxxxx_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx_x100 : irq_req_idx = 2;
	    32'bxxxx_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx_1000 : irq_req_idx = 3;
	    32'bxxxx_xxxx_xxxx_xxxx_xxxx_xxxx_xxx1_0000 : irq_req_idx = 4;
	    32'bxxxx_xxxx_xxxx_xxxx_xxxx_xxxx_xx10_0000 : irq_req_idx = 5;
	    32'bxxxx_xxxx_xxxx_xxxx_xxxx_xxxx_x100_0000 : irq_req_idx = 6;
	    32'bxxxx_xxxx_xxxx_xxxx_xxxx_xxxx_1000_0000 : irq_req_idx = 7;
	    32'bxxxx_xxxx_xxxx_xxxx_xxxx_xxx1_0000_0000 : irq_req_idx = 8;
	    32'bxxxx_xxxx_xxxx_xxxx_xxxx_xx10_0000_0000 : irq_req_idx = 9;
	    32'bxxxx_xxxx_xxxx_xxxx_xxxx_x100_0000_0000 : irq_req_idx = 10;
	    32'bxxxx_xxxx_xxxx_xxxx_xxxx_1000_0000_0000 : irq_req_idx = 11;
	    32'bxxxx_xxxx_xxxx_xxxx_xxx1_0000_0000_0000 : irq_req_idx = 12;
	    32'bxxxx_xxxx_xxxx_xxxx_xx10_0000_0000_0000 : irq_req_idx = 13;
	    32'bxxxx_xxxx_xxxx_xxxx_x100_0000_0000_0000 : irq_req_idx = 14;
	    32'bxxxx_xxxx_xxxx_xxxx_1000_0000_0000_0000 : irq_req_idx = 15;
        32'bxxxx_xxxx_xxxx_xxx1_0000_0000_0000_0000 : irq_req_idx = 16;
        32'bxxxx_xxxx_xxxx_xx10_0000_0000_0000_0000 : irq_req_idx = 17;
        32'bxxxx_xxxx_xxxx_x100_0000_0000_0000_0000 : irq_req_idx = 18;
        32'bxxxx_xxxx_xxxx_1000_0000_0000_0000_0000 : irq_req_idx = 19;
        32'bxxxx_xxxx_xxx1_0000_0000_0000_0000_0000 : irq_req_idx = 20;
        32'bxxxx_xxxx_xx10_0000_0000_0000_0000_0000 : irq_req_idx = 21;
        32'bxxxx_xxxx_x100_0000_0000_0000_0000_0000 : irq_req_idx = 22;
        32'bxxxx_xxxx_1000_0000_0000_0000_0000_0000 : irq_req_idx = 23;
        32'bxxxx_xxx1_0000_0000_0000_0000_0000_0000 : irq_req_idx = 24;
        32'bxxxx_xx10_0000_0000_0000_0000_0000_0000 : irq_req_idx = 25;
        32'bxxxx_x100_0000_0000_0000_0000_0000_0000 : irq_req_idx = 26;
        32'bxxxx_1000_0000_0000_0000_0000_0000_0000 : irq_req_idx = 27;
        32'bxxx1_0000_0000_0000_0000_0000_0000_0000 : irq_req_idx = 28;
        32'bxx10_0000_0000_0000_0000_0000_0000_0000 : irq_req_idx = 29;
        32'bx100_0000_0000_0000_0000_0000_0000_0000 : irq_req_idx = 30;
        32'b1000_0000_0000_0000_0000_0000_0000_0000 : irq_req_idx = 31;
	    32'b0000_0000_0000_0000_0000_0000_0000_0000 : irq_req_idx = 32;
	    default : irq_req_idx = 32;
    endcase
    irq_req_vd = |irq_req_v;
end

/*** Modified for Yosys handing typedef in function - dinesha
assign isvr_priority_eoi   = ycr_search_one_16(ipic_isvr_eoi);
assign irq_eoi_req_vd      = isvr_priority_eoi.vd;
assign irq_eoi_req_idx     = isvr_priority_eoi.idx;
*************************************************/

always_comb 
begin
    casex(ipic_isvr_eoi)
	    32'bxxxx_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx_xxx1 : irq_eoi_req_idx = 0;
	    32'bxxxx_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx_xx10 : irq_eoi_req_idx = 1;
	    32'bxxxx_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx_x100 : irq_eoi_req_idx = 2;
	    32'bxxxx_xxxx_xxxx_xxxx_xxxx_xxxx_xxxx_1000 : irq_eoi_req_idx = 3;
	    32'bxxxx_xxxx_xxxx_xxxx_xxxx_xxxx_xxx1_0000 : irq_eoi_req_idx = 4;
	    32'bxxxx_xxxx_xxxx_xxxx_xxxx_xxxx_xx10_0000 : irq_eoi_req_idx = 5;
	    32'bxxxx_xxxx_xxxx_xxxx_xxxx_xxxx_x100_0000 : irq_eoi_req_idx = 6;
	    32'bxxxx_xxxx_xxxx_xxxx_xxxx_xxxx_1000_0000 : irq_eoi_req_idx = 7;
	    32'bxxxx_xxxx_xxxx_xxxx_xxxx_xxx1_0000_0000 : irq_eoi_req_idx = 8;
	    32'bxxxx_xxxx_xxxx_xxxx_xxxx_xx10_0000_0000 : irq_eoi_req_idx = 9;
	    32'bxxxx_xxxx_xxxx_xxxx_xxxx_x100_0000_0000 : irq_eoi_req_idx = 10;
	    32'bxxxx_xxxx_xxxx_xxxx_xxxx_1000_0000_0000 : irq_eoi_req_idx = 11;
	    32'bxxxx_xxxx_xxxx_xxxx_xxx1_0000_0000_0000 : irq_eoi_req_idx = 12;
	    32'bxxxx_xxxx_xxxx_xxxx_xx10_0000_0000_0000 : irq_eoi_req_idx = 13;
	    32'bxxxx_xxxx_xxxx_xxxx_x100_0000_0000_0000 : irq_eoi_req_idx = 14;
	    32'bxxxx_xxxx_xxxx_xxxx_1000_0000_0000_0000 : irq_eoi_req_idx = 15;
        32'bxxxx_xxxx_xxxx_xxx1_0000_0000_0000_0000 : irq_eoi_req_idx = 16;
        32'bxxxx_xxxx_xxxx_xx10_0000_0000_0000_0000 : irq_eoi_req_idx = 17;
        32'bxxxx_xxxx_xxxx_x100_0000_0000_0000_0000 : irq_eoi_req_idx = 18;
        32'bxxxx_xxxx_xxxx_1000_0000_0000_0000_0000 : irq_eoi_req_idx = 19;
        32'bxxxx_xxxx_xxx1_0000_0000_0000_0000_0000 : irq_eoi_req_idx = 20;
        32'bxxxx_xxxx_xx10_0000_0000_0000_0000_0000 : irq_eoi_req_idx = 21;
        32'bxxxx_xxxx_x100_0000_0000_0000_0000_0000 : irq_eoi_req_idx = 22;
        32'bxxxx_xxxx_1000_0000_0000_0000_0000_0000 : irq_eoi_req_idx = 23;
        32'bxxxx_xxx1_0000_0000_0000_0000_0000_0000 : irq_eoi_req_idx = 24;
        32'bxxxx_xx10_0000_0000_0000_0000_0000_0000 : irq_eoi_req_idx = 25;
        32'bxxxx_x100_0000_0000_0000_0000_0000_0000 : irq_eoi_req_idx = 26;
        32'bxxxx_1000_0000_0000_0000_0000_0000_0000 : irq_eoi_req_idx = 27;
        32'bxxx1_0000_0000_0000_0000_0000_0000_0000 : irq_eoi_req_idx = 28;
        32'bxx10_0000_0000_0000_0000_0000_0000_0000 : irq_eoi_req_idx = 29;
        32'bx100_0000_0000_0000_0000_0000_0000_0000 : irq_eoi_req_idx = 30;
        32'b1000_0000_0000_0000_0000_0000_0000_0000 : irq_eoi_req_idx = 31;
	    32'b0000_0000_0000_0000_0000_0000_0000_0000 : irq_eoi_req_idx = 32;
	    default : irq_eoi_req_idx = 32;
    endcase
    irq_eoi_req_vd = |ipic_isvr_eoi;
end

assign irq_hi_prior_pnd     = irq_req_idx < irq_serv_idx;

assign ipic2csr_irq_m_req_o = irq_req_vd & (~irq_serv_vd | irq_hi_prior_pnd);

assign irq_start_vd         = ipic2csr_irq_m_req_o & ipic_soi_req;

endmodule : ycr_ipic

`endif // YCR_IPIC_EN
