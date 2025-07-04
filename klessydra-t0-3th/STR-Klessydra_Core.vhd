---------------------------------------------------------------------------------------------------------------------
--                                                                                                                 --
--  Author(s): Abdallah Cheikh abdallah.cheikh@uniroma1.it (abdallah93.as@gmail.com)                               --
--                                                                                                                 --
--  Date Modified: 07-04-2020                                                                                      --
---------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------
--  Klessydra-M core v.4.0:                                                                                        --
--  RISCY core pinout, RISC-V core, RV32IMA support plus the RISC-V Embedded E-extension and custom                --
--  K-extension. T13 has 4 pipeline stages F/RD/E/W, in order execution. With the execute stage being superscalar  --
--  Supports interleaved multithreading (IMT), with maximum configurable thread pool size = 16 threads.            --
--  Pure RISCV exception and interrupt handling. Only thread 0 can be interrupted extenranlly. inter-thread ints   --
--  are allowed, and used for thread synchronization. Pulpino irq/exception table fully supported by SW            --
--  runtime system.                                                                                                --
--  Contributors : Abdallah Cheikh.                                                                                --
--  last update: 27-08-2021                                                                                        --
---------------------------------------------------------------------------------------------------------------------

-- package riscv_kless is new work.riscv_klessydra
--   generic map (RV32E => 0);

-- ieee packages ------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_misc.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.textio.all;

-- local packages ------------
use work.riscv_klessydra.all;
--  use work.riscv_kless.all;

------------------------------------------------------------------------------------------------
--  ██╗  ██╗██╗     ███████╗███████╗███████╗██╗   ██╗██████╗ ██████╗  █████╗     ███╗   ███╗  --
--  ██║ ██╔╝██║     ██╔════╝██╔════╝██╔════╝╚██╗ ██╔╝██╔══██╗██╔══██╗██╔══██╗    ████╗ ████║  --
--  █████╔╝ ██║     █████╗  ███████╗███████╗ ╚████╔╝ ██║  ██║██████╔╝███████║    ██╔████╔██║  --
--  ██╔═██╗ ██║     ██╔══╝  ╚════██║╚════██║  ╚██╔╝  ██║  ██║██╔══██╗██╔══██║    ██║╚██╔╝██║  --
--  ██║  ██╗███████╗███████╗███████║███████║   ██║   ██████╔╝██║  ██║██║  ██║    ██║ ╚═╝ ██║  --
--  ╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝╚══════╝   ╚═╝   ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝    ╚═╝     ╚═╝  --
------------------------------------------------------------------------------------------------

-- core entity declaration --
entity klessydra_t0_3th_core is
  generic (
    lutram_rf               : natural := 0;   -- Changes the regfile from flip-flop type into LUTRAM type
    latch_rf                : natural := 0;   -- Changes the regfile from flip-flop type into Latch type (only works if lutram_rf is set to 0)
    RV32E                   : natural := 0;   -- Regfile size, Can be set to 32 for RV32E being 0 else 16 for RV32E being set to 1
    RV32M                   : natural := 1;   -- Enables the M-extension of the risc-v instruction set
    superscalar_exec_en     : natural := 1;   -- Enables superscalar execution when set to 1, else the stall of the pipeline will depend on tha latency of the instruction
    MCYCLE_EN               : natural := 0;   -- Can be set to 1 or 0 only. Setting to zero will disable MCYCLE and MCYCLEH
    MINSTRET_EN             : natural := 0;   -- Can be set to 1 or 0 only. Setting to zero will disable MINSTRET and MINSTRETH
    MHPMCOUNTER_EN          : natural := 0;   -- Can be set to 1 or 0 only. Setting to zero will disable all performance counters except "MCYCLE/H" and "MINSTRET/H"
    count_all               : natural := 1;   -- Perfomance counters count for all the harts instead of there own hart
    debug_en                : natural := 1;   -- Generates the debug unit
    tracer_en               : natural := 0;   -- Enables the generation of the instruction tracer disable in extremely long simulations in order to save storage space
    ----------------------------------------------------------------------------------------
    Data_Width              : natural := 32;
     ----------------------------------------------------------------------------------------
    N_EXT_PERF_COUNTERS     : integer := 0;   -- ignored in Klessydra
    INSTR_RDATA_WIDTH       : integer := 32;  -- ignored in Klessydra
    N_HWLP                  : integer := 2;   -- ignored in Klessydra
    N_HWLP_BITS             : integer := 4    -- ignored in Klessydra
    );
  port (
    -- clock, reset active low, test enable
    clk_i                   : in  std_logic;
    clock_en_i              : in  std_logic;
    rst_ni                  : in  std_logic;
    test_en_i               : in  std_logic;
    -- initialization signals 
    boot_addr_i             : in  std_logic_vector(31 downto 0);
    core_id_i               : in  std_logic_vector(3 downto 0);
    -- program memory interface
    instr_req_o             : out std_logic;
    instr_gnt_i             : in  std_logic;
    instr_rvalid_i          : in  std_logic;
    instr_addr_o            : out std_logic_vector(31 downto 0);
    instr_rdata_i           : in  std_logic_vector(31 downto 0);
    instr_we_o              : out std_logic;
    instr_be_o              : out std_logic_vector(3 downto 0);
    instr_wdata_o           : out std_logic_vector(31 downto 0);
    instr_axi_rvalid        : in  std_logic;
    -- data memory interface
    data_req_o              : out std_logic;
    data_gnt_i              : in  std_logic;
    data_rvalid_i           : in  std_logic;
    data_we_o               : out std_logic;
    data_be_o               : out std_logic_vector(3 downto 0);
    data_addr_o             : out std_logic_vector(31 downto 0);
    data_wdata_o            : out std_logic_vector(31 downto 0);
    data_rdata_i            : in  std_logic_vector(31 downto 0);
    data_err_i              : in  std_logic;
    -- interrupt request interface
    irq_i                   : in  std_logic;
    irq_id_i                : in  std_logic_vector(4 downto 0);
    irq_ack_o               : out std_logic;
    irq_id_o                : out std_logic_vector(4 downto 0);
    irq_sec_i               : in  std_logic;  -- unused in Pulpino
    sec_lvl_o               : out std_logic;  -- unused in Pulpino
    -- debug interface
    debug_req_i             : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
    debug_havereset         : out std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
    debug_running           : out std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
    debug_halted            : out std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
    dm_halt_addr_i          : in  std_logic_vector(31 downto 0);
    dm_exception_addr_i     : in  std_logic_vector(31 downto 0);
    -- miscellanous control signals
    fetch_enable_i          : in  std_logic;
    core_busy_o             : out std_logic;
    ext_perf_counters_i     : in  std_logic_vector(N_EXT_PERF_COUNTERS to 1);
    -- klessydra-specific signals
    core_select             : in  natural range 1 downto 0;
    source_hartid_o         : out natural range THREAD_POOL_SIZE_GLOBAL-1 downto 0;
    sw_irq_o                : out std_logic_vector(THREAD_POOL_SIZE_GLOBAL-1 downto 0);
    sw_irq_served_i         : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
    sw_irq_served_o         : out std_logic_vector(THREAD_POOL_SIZE_GLOBAL-1 downto 0)
    );

end entity klessydra_t0_3th_core;

architecture Klessydra_M of klessydra_t0_3th_core is

  constant THREAD_POOL_SIZE_GEN           : natural := work.riscv_klessydra.THREAD_POOL_SIZE;
  constant THREAD_POOL_SIZE_GLOBAL_GEN    : natural := work.riscv_klessydra.THREAD_POOL_SIZE_GLOBAL;

  signal harc_EXEC               :natural range THREAD_POOL_SIZE-1 downto 0;
  signal pc_IE                   :std_logic_vector(31 downto 0);
  signal RS1_Data_IE             :std_logic_vector(31 downto 0);
  signal RS2_Data_IE             :std_logic_vector(31 downto 0);
  signal RD_Data_IE              :std_logic_vector(31 downto 0); -- unused

  constant RF_SIZE             : natural := 32-16*RV32E;
  constant RF_CEIL             : natural := integer(ceil(log2(real(RF_SIZE))));
  constant TPS_CEIL            : natural := integer(ceil(log2(real(THREAD_POOL_SIZE))));

  subtype harc_range is natural range THREAD_POOL_SIZE-1 downto 0;  -- will be used replicated units in the core

  -- Control Status Register (CSR) signals
  signal MHARTID     : MHARTID_array;
  signal MSTATUS     : MSTATUS_array;
  signal MEPC        : harc_vec_array;
  signal MCAUSE      : harc_vec_array;
  signal MIP         : harc_vec_array;
  signal MTVEC       : harc_vec_array;
  signal PCER        : harc_vec_array;

  signal sw_irq          : std_logic_vector(THREAD_POOL_SIZE_GLOBAL-1 downto 0);
  signal sw_irq_pending  : std_logic_vector(THREAD_POOL_SIZE_GLOBAL-1 downto 0);
  signal irq_pending     : std_logic_vector(harc_range);
  signal except_pc_vec_o : std_logic_vector(31 downto 0);
  signal WFI_Instr       : std_logic;

  -- Memory fault signals
  signal load_err, store_err : std_logic;

  -- Interface signals from EXEC unit to CSR management unit
  signal csr_instr_req       : std_logic;
  signal csr_instr_done      : std_logic;
  signal csr_access_denied_o : std_logic;
  signal csr_wdata_i         : std_logic_vector(31 downto 0);
  signal csr_op_i            : std_logic_vector(2 downto 0);
  signal csr_rdata_o         : std_logic_vector(31 downto 0);
  signal csr_addr_i          : std_logic_vector(11 downto 0);

  -- program counters --
  signal pc_IF     : std_logic_vector(31 downto 0);  -- pc_IF is the actual pc
  signal pc_ID     : std_logic_vector(31 downto 0);  -- pc_ID is the orogram counter of the Decode stage

  -- instruction register and instr. propagation registers --
  signal instr_word_IE    : std_logic_vector(31 downto 0);
  signal instr_rvalid_IE  : std_logic;  -- validity bit at IE input

  -- pc updater signals
  signal served_ie_except_condition      : std_logic_vector(harc_range);
  signal served_ls_except_condition      : std_logic_vector(harc_range);
  signal served_except_condition         : std_logic_vector(harc_range);
  signal served_mret_condition           : std_logic_vector(harc_range);
  signal served_irq                      : std_logic_vector(harc_range);
  signal served_pending_irq              : std_logic_vector(harc_range);
  signal taken_branch_pending            : std_logic_vector(harc_range);
  signal ie_except_data                  : std_logic_vector(31 downto 0);
  signal ls_except_data                  : std_logic_vector(31 downto 0);
  signal taken_branch                    : std_logic;
  signal ie_taken_branch                 : std_logic;
  signal ls_taken_branch                 : std_logic;
  signal set_branch_condition            : std_logic;
  signal ie_except_condition             : std_logic;
  signal ls_except_condition             : std_logic;
  signal set_except_condition            : std_logic;
  signal set_mret_condition              : std_logic;
  signal absolute_address                : std_logic_vector(31 downto 0);
  signal PC_offset                       : std_logic_vector(31 downto 0);
  signal pc_except_value                 : harc_vec_array;
  signal pc_except_value_wire            : harc_vec_array;
  signal incremented_pc                  : harc_vec_array;
  signal relative_to_PC                  : harc_vec_array;
  signal absolute_jump                   : std_logic_vector(harc_range);
  signal data_we_o_lat                   : std_logic;
  signal misaligned_err                  : std_logic;
  signal PC_offset_ID                    : std_logic_vector(31 downto 0);
  signal set_branch_condition_ID         : std_logic;
  signal core_enable_i                   : std_logic;

  -- AAA check if we need these signals
  -- signals for counting intructions
  --signal clock_cycle         : std_logic_vector(63 downto 0);  -- RDCYCLE
  --signal external_counter    : std_logic_vector(63 downto 0);  -- RDTIME
  --signal instruction_counter : std_logic_vector(63 downto 0);  -- RDINSTRET

  --signal used by counters
  signal set_wfi_condition          : std_logic;
  signal harc_to_csr                : natural range THREAD_POOL_SIZE_GLOBAL-1 downto 0;
  signal jump_instr                 : std_logic;
  signal jump_instr_lat             : std_logic;
  signal branch_instr               : std_logic;
  signal branch_instr_lat           : std_logic;

  -- auxiliary data memory interface signals
  signal data_addr_internal     : std_logic_vector(31 downto 0);
  signal data_be_internal       : std_logic_vector(3 downto 0);

  --Debug Unit signal and state
  signal ebreak_instr                : std_logic;
  signal dret_instr                  : std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
  signal halt_req                    : std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
  signal DEBUG_MODE                  : std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
  signal debug_cause                 : debug_cause_array;
  signal DPC                         : harc_vec_array;
  signal halt_served                 : std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
  signal ebreak_dbg                  : std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
  signal reset_state                 : std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
  signal irq_en_single_step          : std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
  signal single_stepping             : std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
  signal state_waiting_for_halt_serv : std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
  signal halt_req_wire               : std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
  signal fetch_busy_dbg              : std_logic;
  signal gnt_waiting                 : std_logic;
  signal taken_branch_addr           : std_logic_vector(31 downto 0);
  signal wfi_exec                    : std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
  signal amo_load_skip               : std_logic;
  signal amo_load                    : std_logic;
  signal amo_store                   : std_logic;
  signal debug_pc_taken_wire         : std_logic_vector(THREAD_POOL_SIZE-1 downto 0);

  -- hardware context id at fetch, and propagated hardware context ids
  --signal harc_count            : harc_min_range;
  signal harc_IF         : harc_range;
  signal harc_ID         : harc_range;

  -- Internal signal (VHDL1993)
  signal data_we_o_int          : std_logic;
  signal data_req_o_int         : std_logic;

  signal debug_havereset_int    : std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
  signal debug_running_int      : std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
  signal debug_halted_int       : std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
  signal instr_we_int         : std_logic;
  signal instr_be_int         : std_logic_vector(3 downto 0);
  signal instr_wdata_int      : std_logic_vector(31 downto 0);

  function and_const(a: natural; b: natural) return natural is
    variable c : natural;
  begin
    if a = b then
      c := 1;
    else
      c := 0;
    end if;
    return c;
  end function and_const;

  signal served_irq_lat          : std_logic_vector(harc_range);

  -- This function increments all the bits in a std_logic_vector
  function add_vect_bits(v: std_logic_vector) return natural is
    variable h: natural;
  begin
    h := 0;
    for i in v'range loop
      if v(i) = '1' then
        h := h + 1;
      end if;
    end loop;
    return h;
  end function add_vect_bits;

  component Program_Counter is
    generic (
      debug_en                          : natural;
      THREAD_POOL_SIZE                  : natural
    );
    port (
      absolute_jump                     : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      data_we_o_lat                     : in  std_logic;
      absolute_address                  : in  std_logic_vector(31 downto 0);
      PC_offset                         : in  std_logic_vector(31 downto 0);
      taken_branch                      : in  std_logic;
      ie_taken_branch                   : in  std_logic;
      ls_taken_branch                   : in  std_logic;
      set_branch_condition              : in  std_logic;
      ie_except_condition               : in  std_logic;
      ls_except_condition               : in  std_logic;
      set_except_condition              : in  std_logic;
      set_mret_condition                : in  std_logic;
      set_wfi_condition                 : in  std_logic;
      ------------------------------------------------------------------------------
      gnt_waiting                       : in  std_logic;
      fetch_busy_dbg                    : in  std_logic;
      DEBUG_MODE                        : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      DPC                               : in  harc_vec_array;
      halt_req                          : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      debug_pc_taken_wire               : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      halt_served                       : out std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      reset_state                       : out std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      dm_halt_addr_i                    : in  std_logic_vector(31 downto 0);
      dm_exception_addr_i               : in  std_logic_vector(31 downto 0);
      taken_branch_addr_out             : out std_logic_vector(31 downto 0);
      dret_instr                        : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0); 
      state_waiting_for_halt_serv       : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0); 
      ------------------------------------------------------------------------------
      harc_ID                           : in  natural range THREAD_POOL_SIZE-1 downto 0;
      harc_EXEC                         : in  natural range THREAD_POOL_SIZE-1 downto 0;
      instr_rvalid_IE                   : in  std_logic;
      pc_ID                             : in  std_logic_vector(31 downto 0);
      pc_IE                             : in  std_logic_vector(31 downto 0);
      MSTATUS                           : in  MSTATUS_array;
      MIP, MEPC, MCAUSE, MTVEC          : in  harc_vec_array;
      instr_word_IE                     : in  std_logic_vector(31 downto 0);
      pc_IF                             : out std_logic_vector(31 downto 0);
      harc_IF                           : out natural range THREAD_POOL_SIZE-1 downto 0;
      served_ie_except_condition        : out std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      served_ls_except_condition        : out std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      served_except_condition           : out std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      served_mret_condition             : out std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      served_irq                        : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      taken_branch_pending              : out std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      incremented_pc                    : out harc_vec_array;
      irq_pending                       : out std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      PC_offset_ID                      : in  std_logic_vector(31 downto 0);
      set_branch_condition_ID           : in  std_logic;
      clk_i                             : in  std_logic;
      rst_ni                            : in  std_logic;
      irq_i                             : in  std_logic;
      fetch_enable_i                    : in  std_logic;
      boot_addr_i                       : in  std_logic_vector(31 downto 0);
      instr_gnt_i                       : in  std_logic
      );
  end component;

  component CSR_Unit is
    generic (
      THREAD_POOL_SIZE_GLOBAL : natural;
      THREAD_POOL_SIZE        : natural;
      MCYCLE_EN               : natural;
      MINSTRET_EN             : natural;
      MHPMCOUNTER_EN          : natural;
      RF_CEIL                 : natural;
      debug_en                : natural;
      count_all               : natural
    );
    port (
      pc_IE                       : in  std_logic_vector(31 downto 0);
      ie_except_data              : in  std_logic_vector(31 downto 0);
      ls_except_data              : in  std_logic_vector(31 downto 0);
      served_ie_except_condition  : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      served_ls_except_condition  : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      harc_EXEC                   : in  natural range THREAD_POOL_SIZE-1 downto 0;
      harc_ID                     : in  natural range THREAD_POOL_SIZE-1 downto 0;
      harc_IF                     : in  natural range THREAD_POOL_SIZE-1 downto 0;
      harc_to_csr                 : in  natural range THREAD_POOL_SIZE_GLOBAL-1 downto 0;
      instr_word_IE               : in  std_logic_vector(31 downto 0);
      served_except_condition     : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      served_mret_condition       : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      served_irq                  : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      served_pending_irq          : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      pc_except_value_wire        : in  harc_vec_array;
      data_addr_internal          : in  std_logic_vector(31 downto 0);
      jump_instr                  : in  std_logic;
      branch_instr                : in  std_logic;
      set_branch_condition        : in  std_logic;
      csr_instr_req               : in  std_logic;
      misaligned_err              : in  std_logic;
      WFI_Instr                   : in  std_logic;
      csr_wdata_i                 : in  std_logic_vector (31 downto 0);
      csr_op_i                    : in  std_logic_vector (2 downto 0);
      csr_addr_i                  : in  std_logic_vector (11 downto 0);
      csr_instr_done              : out std_logic;
      csr_access_denied_o         : out std_logic;
      csr_rdata_o                 : out std_logic_vector (31 downto 0);
      MHARTID                     : out MHARTID_array;  -- AAA adjust the size of mhartID
      MSTATUS                     : out MSTATUS_array;
      MEPC                        : out harc_vec_array;
      MCAUSE                      : out harc_vec_array;
      MIP                         : out harc_vec_array;
      MTVEC                       : out harc_vec_array;
      MSCRATCH                    : out harc_vec_array;
      PCER                        : out harc_vec_array;
      --Debug added signals-----------------------------------------------------------
      pc_ID                       : in  std_logic_vector(31 downto 0);
      pc_IF                       : in  std_logic_vector(31 downto 0);
      DPC                         : out harc_vec_array;
      DEBUG_MODE                  : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      wfi_exec                    : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      taken_branch_addr           : in  std_logic_vector (31 downto 0);
      halt_req                    : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      irq_en_single_step          : out std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      single_stepping             : out std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      debug_cause                 : in  debug_cause_array;
      dret_instr                  : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      ebreak_instr                : in  std_logic;
      halt_served                 : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      ebreak_dbg                  : out std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      taken_branch                : in  std_logic; 
  ----------------------------------------------------------------------------------------
      fetch_enable_i              : in  std_logic;
      clk_i                       : in  std_logic;
      rst_ni                      : in  std_logic;
      core_id_i                   : in  std_logic_vector(3 downto 0);
      instr_rvalid_i              : in  std_logic;
      instr_rvalid_IE             : in  std_logic;
      data_we_o                   : in  std_logic;
      data_req_o                  : in  std_logic;
      data_gnt_i                  : in  std_logic;
      irq_i                       : in  std_logic;
      irq_id_i                    : in  std_logic_vector(4 downto 0);
      irq_id_o                    : out std_logic_vector(4 downto 0);
      irq_ack_o                   : out std_logic;
      sw_irq                      : in  std_logic_vector(THREAD_POOL_SIZE_GLOBAL-1 downto 0);
      sw_irq_pending              : in  std_logic_vector(THREAD_POOL_SIZE_GLOBAL-1 downto 0)
      );
  end component;

  component Pipeline is
    generic(
      ThREAD_POOL_SIZE           : natural;
      THREAD_POOL_SIZE_GLOBAL    : natural;
      lutram_rf                  : natural;
      latch_rf                   : natural;
      RV32E                      : natural;
      RV32M                      : natural;
      superscalar_exec_en        : natural;
      MCYCLE_EN                  : natural;
      MINSTRET_EN                : natural;
      MHPMCOUNTER_EN             : natural;
      count_all                  : natural;
      debug_en                   : natural;
      tracer_en                  : natural;
      --------------------------------
      RF_SIZE                    : natural;
      RF_CEIL                    : natural
    );
    port (
      pc_IF                      : in  std_logic_vector(31 downto 0);
      harc_IF                    : in  natural range THREAD_POOL_SIZE-1 downto 0;
      irq_pending                : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      csr_instr_done             : in  std_logic;
      csr_access_denied_o        : in  std_logic;
      csr_rdata_o                : in  std_logic_vector (31 downto 0);
      MHARTID                    : in  MHARTID_array;
      MSTATUS                    : in  MSTATUS_array;
      PCER                       : in  harc_vec_array;
      --------------------------------------------------------------------------------
      DEBUG_MODE                 : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      halt_req                   : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      halt_req_wire              : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      debug_pc_taken_wire        : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      irq_en_single_step         : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      single_stepping            : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      amo_load                   : out  std_logic;
      amo_load_skip              : out  std_logic;
      amo_store                  : out std_logic;
      dret_instr                 : out std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      gnt_waiting                : out std_logic;
      fetch_busy_dbg             : out std_logic;
      wfi_exec                   : out std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      instr_axi_rvalid           : in  std_logic;
      --------------------------------------------------------------------------------
      served_irq                 : out std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      served_pending_irq         : out std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      WFI_Instr                  : out std_logic;
      misaligned_err             : out std_logic;
      pc_ID                      : out std_logic_vector(31 downto 0);
      pc_IE                      : out std_logic_vector(31 downto 0);
      ie_except_data             : out std_logic_vector(31 downto 0);
      ls_except_data             : out std_logic_vector(31 downto 0);
      taken_branch               : out std_logic;
      ie_taken_branch            : out std_logic;
      ls_taken_branch            : out std_logic;
      set_branch_condition       : out std_logic;
      set_except_condition       : out std_logic;
      ie_except_condition        : out std_logic;
      ls_except_condition        : out std_logic;
      set_mret_condition         : out std_logic;
      set_wfi_condition          : out std_logic;
      csr_instr_req              : out std_logic;
      instr_rvalid_IE            : out std_logic;  -- validity bit at IE input
      csr_addr_i                 : out std_logic_vector (11 downto 0);
      csr_wdata_i                : out std_logic_vector (31 downto 0);
      csr_op_i                   : out std_logic_vector (2 downto 0);
      jump_instr                 : out std_logic;
      jump_instr_lat             : out std_logic;
      branch_instr               : out std_logic;
      branch_instr_lat           : out std_logic;
      harc_ID                    : out natural range THREAD_POOL_SIZE-1 downto 0;
      harc_EXEC                  : out natural range THREAD_POOL_SIZE-1 downto 0;
      harc_to_csr                : out natural range THREAD_POOL_SIZE_GLOBAL-1 downto 0;
      instr_word_IE              : out std_logic_vector(31 downto 0);
      PC_offset                  : out std_logic_vector(31 downto 0);
      absolute_address           : out std_logic_vector(31 downto 0);
      ebreak_instr               : out std_logic;
      data_addr_internal         : out std_logic_vector(31 downto 0);
      absolute_jump              : out std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      PC_offset_ID               : out std_logic_vector(31 downto 0);
      set_branch_condition_ID    : out std_logic;
      --wfi_hart_wire              : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      halt_update                : out std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
  
      -- clock, reset active low, test enable
      clk_i                      : in  std_logic;
      rst_ni                     : in  std_logic;
      -- program memory interface
      instr_req_o                : out std_logic;
      instr_gnt_i                : in  std_logic;
      instr_rvalid_i             : in  std_logic;
      instr_rdata_i              : in  std_logic_vector(31 downto 0);
      -- data memory interface
      data_req_o                 : out std_logic;
      data_gnt_i                 : in  std_logic;
      data_rvalid_i              : in  std_logic;
      data_we_o                  : out std_logic;
      data_be_o                  : out std_logic_vector(3 downto 0);
      data_addr_o                : out std_logic_vector(31 downto 0);
      data_wdata_o               : out std_logic_vector(31 downto 0);
      data_rdata_i               : in  std_logic_vector(31 downto 0);
      data_err_i                 : in  std_logic;
      -- interrupt request interface
      irq_i                      : in  std_logic;
      -- miscellanous control signals
      fetch_enable_i             : in  std_logic;
      core_busy_o                : out std_logic;
      -- klessydra-specific signals
      core_enable_i              : in  std_logic;
      source_hartid_o            : out natural range THREAD_POOL_SIZE_GLOBAL-1 downto 0;
      sw_irq                     : out std_logic_vector(THREAD_POOL_SIZE_GLOBAL-1 downto 0);
      sw_irq_served_i            : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      sw_irq_served_o            : out std_logic_vector(THREAD_POOL_SIZE_GLOBAL-1 downto 0);
      sw_irq_pending             : out std_logic_vector(THREAD_POOL_SIZE_GLOBAL-1 downto 0);
      -- VCU  Signals
      RS1_Data_IE                : out std_logic_vector(31 downto 0);
      RS2_Data_IE                : out std_logic_vector(31 downto 0);
      RD_Data_IE                 : out std_logic_vector(31 downto 0);  -- unused
      state_LS                   : out fsm_LS_states
    );
    end component;
  
  component Debug
    generic(
      debug_en          : natural;
      THREAD_POOL_SIZE  : natural
    );
    port(
      rst_ni               : in  std_logic;
      clk_i                : in  std_logic;
      debug_req_i          : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      ebreak_dbg           : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      single_stepping      : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      DEBUG_MODE           : out std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      harc_EXEC            : in  natural range THREAD_POOL_SIZE-1 downto 0;
      harc_IF              : in  natural range THREAD_POOL_SIZE-1 downto 0;
      ebreak_instr         : in  std_logic;
      halt_req             : out std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      halt_req_wire        : out std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      halt_served          : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      reset_state          : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      debug_havereset      : out std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      debug_running        : out std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      debug_halted         : out std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      state_waiting_for_halt_serv : out std_logic_vector(THREAD_POOL_SIZE-1 downto 0); 
      dret_instr           : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      amo_load             : in  std_logic;
      amo_load_skip        : in  std_logic;
      amo_store            : in  std_logic;
      debug_pc_taken_wire  : out std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
      debug_cause          : out debug_cause_array
    );
  end component;

--------------------------------------------------------------------------------------------------
----------------------- ARCHITECTURE BEGIN -------------------------------------------------------              
begin

  --new signals for demux on instruction bus
  instr_we_int      <= '0';
  instr_be_int      <= "1111";
  instr_wdata_int   <= (others => '0');

  instr_we_o     <= instr_we_int;
  instr_be_o     <= instr_be_int;
  instr_wdata_o  <= instr_wdata_int;

  data_we_o <= data_we_o_int;
  data_req_o <= data_req_o_int;

  -- Connecting signals to ports
  data_we_o <= data_we_o_int;
  data_req_o <= data_req_o_int;

  sw_irq_o <= sw_irq;

  assert (lutram_rf /= debug_en and lutram_rf /= 1) report "Debug-Unit cannot read from a LUTRAM regfile." severity WARNING;

  instr_addr_o <= pc_IF;

  process(pc_except_value, set_except_condition, pc_IE, pc_except_value_wire, harc_EXEC) --VHDL1993
  begin
    pc_except_value_wire <= pc_except_value;
    if set_except_condition  = '1' then
      pc_except_value_wire(harc_EXEC) <=  pc_IE;    
    end if;
  end process;

  process(clk_i, rst_ni)
  begin
    if rst_ni = '0' then
    elsif rising_edge(clk_i) then
      pc_except_value <= pc_except_value_wire;
    end if;
  end process;

  Prg_Ctr : Program_Counter
    generic map (
      debug_en                    => debug_en,
      THREAD_POOL_SIZE            => THREAD_POOL_SIZE_GEN
      )
    port map(
      absolute_jump               => absolute_jump,
      data_we_o_lat               => data_we_o_lat,
      absolute_address            => absolute_address,       
      PC_offset                   => PC_offset,
      taken_branch                => taken_branch,
      ie_taken_branch             => ie_taken_branch,
      ls_taken_branch             => ls_taken_branch,
      set_branch_condition        => set_branch_condition,
      ie_except_condition         => ie_except_condition,
      ls_except_condition         => ls_except_condition,
      set_except_condition        => set_except_condition,
      set_mret_condition          => set_mret_condition,
      set_wfi_condition           => set_wfi_condition,
      gnt_waiting                 => gnt_waiting,
      fetch_busy_dbg              => fetch_busy_dbg,
      DEBUG_MODE                  => DEBUG_MODE,
      DPC                         => DPC,
      halt_req                    => halt_req,
      debug_pc_taken_wire         => debug_pc_taken_wire,
      halt_served                 => halt_served,
      reset_state                 => reset_state,
      dm_halt_addr_i              => dm_halt_addr_i,
      dm_exception_addr_i         => dm_exception_addr_i,
      taken_branch_addr_out       => taken_branch_addr,
      dret_instr                  => dret_instr,
      state_waiting_for_halt_serv => state_waiting_for_halt_serv,
      harc_ID                     => harc_ID,
      harc_EXEC                   => harc_EXEC,
      instr_rvalid_IE             => instr_rvalid_IE,
      pc_ID                       => pc_ID,
      pc_IE                       => pc_IE,
      MIP                         => MIP,
      MEPC                        => MEPC,
      MSTATUS                     => MSTATUS,
      MCAUSE                      => MCAUSE,
      MTVEC                       => MTVEC,
      instr_word_IE               => instr_word_IE,
      pc_IF                       => pc_IF,
      harc_IF                     => harc_IF,
      served_ie_except_condition  => served_ie_except_condition,
      served_ls_except_condition  => served_ls_except_condition,
      served_except_condition     => served_except_condition,
      served_mret_condition       => served_mret_condition,
      served_irq                  => served_irq,
      taken_branch_pending        => taken_branch_pending,
      incremented_pc              => incremented_pc,
      irq_pending                 => irq_pending,
      PC_offset_ID                => PC_offset_ID,
      set_branch_condition_ID     => set_branch_condition_ID,
      clk_i                       => clk_i,
      rst_ni                      => rst_ni,
      irq_i                       => irq_i,
      fetch_enable_i              => fetch_enable_i,
      boot_addr_i                 => boot_addr_i,
      instr_gnt_i                 => instr_gnt_i
      );

  CSR : CSR_Unit
    generic map (
      THREAD_POOL_SIZE_GLOBAL     => THREAD_POOL_SIZE_GLOBAL_GEN,
      THREAD_POOL_SIZE            => THREAD_POOL_SIZE_GEN,
      MCYCLE_EN                   => MCYCLE_EN,
      MINSTRET_EN                 => MINSTRET_EN,
      MHPMCOUNTER_EN              => MHPMCOUNTER_EN,
      RF_CEIL                     => RF_CEIL,
      debug_en                    => debug_en,
      count_all                   => count_all
    )
    port map(
      pc_IE                       => pc_IE,
      ie_except_data              => ie_except_data,
      ls_except_data              => ls_except_data,
      served_ie_except_condition  => served_ie_except_condition,
      served_ls_except_condition  => served_ls_except_condition,
      harc_EXEC                   => harc_EXEC,
      harc_ID                     => harc_ID,
      harc_IF                     => harc_IF,
      harc_to_csr                 => harc_to_csr,
      instr_word_IE               => instr_word_IE,
      served_except_condition     => served_except_condition,
      served_mret_condition       => served_mret_condition,
      served_irq                  => served_irq,
      served_pending_irq          => served_pending_irq,
      pc_except_value_wire        => pc_except_value_wire,
      data_addr_internal          => data_addr_internal,
      jump_instr                  => jump_instr,
      branch_instr                => branch_instr,
      set_branch_condition        => set_branch_condition,
      csr_instr_req               => csr_instr_req,
      misaligned_err              => misaligned_err,
      WFI_Instr                   => WFI_Instr,
      csr_wdata_i                 => csr_wdata_i,
      csr_op_i                    => csr_op_i,
      csr_addr_i                  => csr_addr_i,
      csr_instr_done              => csr_instr_done,
      csr_access_denied_o         => csr_access_denied_o,
      csr_rdata_o                 => csr_rdata_o,
      MHARTID                     => MHARTID,
      MSTATUS                     => MSTATUS,
      MEPC                        => MEPC,
      MCAUSE                      => MCAUSE,
      MIP                         => MIP,
      MTVEC                       => MTVEC,
      PCER                        => PCER,
      pc_ID                       => pc_ID,
      pc_IF                       => pc_IF,
      DPC                         => DPC,
      DEBUG_MODE                  => DEBUG_MODE,
      wfi_exec                    => wfi_exec,
      taken_branch_addr           => taken_branch_addr,
      halt_req                    => halt_req,
      irq_en_single_step          => irq_en_single_step,
      single_stepping             => single_stepping,
      debug_cause                 => debug_cause,
      dret_instr                  => dret_instr,
      ebreak_instr                => ebreak_instr,
      halt_served                 => halt_served,
      ebreak_dbg                  => ebreak_dbg,
      taken_branch                => taken_branch,
      fetch_enable_i              => fetch_enable_i,
      clk_i                       => clk_i,
      rst_ni                      => rst_ni,
      core_id_i                   => core_id_i,
      instr_rvalid_i              => instr_rvalid_i,
      instr_rvalid_IE             => instr_rvalid_IE,
      data_we_o                   => data_we_o_int,
      data_req_o                  => data_req_o_int,
      data_gnt_i                  => data_gnt_i,
      irq_i                       => irq_i,
      irq_id_i                    => irq_id_i,
      irq_id_o                    => irq_id_o,
      irq_ack_o                   => irq_ack_o,
      sw_irq                      => sw_irq,
      sw_irq_pending              => sw_irq_pending
      );

  Pipe : Pipeline
    generic map(
      THREAD_POOL_SIZE_GLOBAL => THREAD_POOL_SIZE_GLOBAL_GEN,
      THREAD_POOL_SIZE        => THREAD_POOL_SIZE_GEN,
      lutram_rf               => lutram_rf,
      latch_rf                => latch_rf,
      RV32E                   => RV32E,
      RV32M                   => RV32M,
      superscalar_exec_en     => superscalar_exec_en,
      MCYCLE_EN               => MCYCLE_EN,
      MINSTRET_EN             => MINSTRET_EN,
      MHPMCOUNTER_EN          => MHPMCOUNTER_EN,
      count_all               => count_all,
      debug_en                => debug_en,
      tracer_en               => tracer_en,
      -----------------------------------
      RF_SIZE                 => RF_SIZE,
      RF_CEIL                 => RF_CEIL
      )
    port map(
      pc_IF                      => pc_IF,
      harc_IF                    => harc_IF,
      irq_pending                => irq_pending,
      csr_instr_done             => csr_instr_done,
      csr_access_denied_o        => csr_access_denied_o,
      csr_rdata_o                => csr_rdata_o,
      pc_ID                      => pc_ID,
      pc_IE                      => pc_IE,
      ie_except_data             => ie_except_data,
      ls_except_data             => ls_except_data,
      MHARTID                    => MHARTID,
      MSTATUS                    => MSTATUS,
      PCER                       => PCER,
      DEBUG_MODE                 => DEBUG_MODE,
      halt_req                   => halt_req,
      halt_req_wire              => halt_req_wire,
      debug_pc_taken_wire        => debug_pc_taken_wire,
      irq_en_single_step         => irq_en_single_step,
      single_stepping            => single_stepping,
      amo_load                   => amo_load,
      amo_load_skip              => amo_load_skip,
      amo_store                  => amo_store,
      dret_instr                 => dret_instr,
      gnt_waiting                => gnt_waiting,
      fetch_busy_dbg             => fetch_busy_dbg,
      wfi_exec                   => wfi_exec,
      instr_axi_rvalid           => instr_axi_rvalid,
      served_irq                 => served_irq,
      served_pending_irq         => served_pending_irq,
      misaligned_err             => misaligned_err,
      WFI_Instr                  => WFI_Instr,
      taken_branch               => taken_branch,
      ie_taken_branch            => ie_taken_branch,
      ls_taken_branch            => ls_taken_branch,
      set_branch_condition       => set_branch_condition,
      set_except_condition       => set_except_condition,
      ie_except_condition        => ie_except_condition,
      ls_except_condition        => ls_except_condition,
      set_mret_condition         => set_mret_condition,
      set_wfi_condition          => set_wfi_condition,
      csr_instr_req              => csr_instr_req,
      instr_rvalid_IE            => instr_rvalid_IE,
      csr_addr_i                 => csr_addr_i,
      csr_wdata_i                => csr_wdata_i,
      csr_op_i                   => csr_op_i,
      jump_instr                 => jump_instr,
      jump_instr_lat             => jump_instr_lat,
      branch_instr               => branch_instr,
      branch_instr_lat           => branch_instr_lat,
      harc_ID                    => harc_ID,
      harc_EXEC                  => harc_EXEC,
      harc_to_csr                => harc_to_csr,
      instr_word_IE              => instr_word_IE,
      PC_offset                  => PC_offset,
      absolute_address           => absolute_address,
      ebreak_instr               => ebreak_instr,
      data_addr_internal         => data_addr_internal,
      absolute_jump              => absolute_jump,
      PC_offset_ID               => PC_offset_ID,
      set_branch_condition_ID    => set_branch_condition_ID,
      clk_i                      => clk_i,
      rst_ni                     => rst_ni,
      instr_req_o                => instr_req_o,
      instr_gnt_i                => instr_gnt_i,
      instr_rvalid_i             => instr_rvalid_i,
      instr_rdata_i              => instr_rdata_i,
      data_req_o                 => data_req_o_int,
      data_gnt_i                 => data_gnt_i,
      data_rvalid_i              => data_rvalid_i,
      data_we_o                  => data_we_o_int,
      data_be_o                  => data_be_o,
      data_addr_o                => data_addr_o,
      data_wdata_o               => data_wdata_o,
      data_rdata_i               => data_rdata_i,
      data_err_i                 => data_err_i,
      irq_i                      => irq_i,
      fetch_enable_i             => fetch_enable_i,
      core_busy_o                => core_busy_o,
      core_enable_i              => core_enable_i,
      source_hartid_o            => source_hartid_o,
      sw_irq                     => sw_irq,
      sw_irq_served_i            => sw_irq_served_i, 
      sw_irq_served_o            => sw_irq_served_o,
      sw_irq_pending             => sw_irq_pending,
      RS1_Data_IE                => RS1_Data_IE,
      RS2_Data_IE                => RS2_Data_IE,
      RD_Data_IE                 => RD_Data_IE,
      state_LS                   => open
      );

  debug_unit_gen: if debug_en = 1 generate
    Debug_u : Debug
      generic map(
        debug_en                     => debug_en,
        THREAD_POOL_SIZE             => THREAD_POOL_SIZE
      )
      port map(
        rst_ni                       => rst_ni,
        clk_i                        => clk_i,
        debug_req_i                  => debug_req_i,
        ebreak_dbg                   => ebreak_dbg,
        single_stepping              => single_stepping,
        DEBUG_MODE                   => DEBUG_MODE,
        harc_EXEC                    => harc_EXEC,
        harc_IF                      => harc_IF,
        ebreak_instr                 => ebreak_instr,
        halt_req                     => halt_req,
        halt_req_wire                => halt_req_wire,
        halt_served                  => halt_served,
        reset_state                  => reset_state,
        debug_havereset              => debug_havereset_int,
        debug_running                => debug_running_int,
        debug_halted                 => debug_halted_int,
        state_waiting_for_halt_serv  => state_waiting_for_halt_serv,
        dret_instr                   => dret_instr,
        amo_load                     => amo_load,
        amo_load_skip                => amo_load_skip,
        amo_store                    => amo_store,
        debug_pc_taken_wire          => debug_pc_taken_wire,
        debug_cause                  => debug_cause
      );
  end generate debug_unit_gen;

end Klessydra_M;
--------------------------------------------------------------------------------------------------
-- END of Klessydra M core architecture ----------------------------------------------------------
--------------------------------------------------------------------------------------------------
