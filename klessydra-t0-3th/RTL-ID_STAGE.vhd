----------------------------------------------------------------------------------------------------------------
--  Stage ID - (Instruction decode and registerfile read)                                                     --
--  Author(s): Abdallah Cheikh abdallah.cheikh@uniroma1.it (abdallah93.as@gmail.com)                          --
--                                                                                                            --
--  Date Modified: 07-04-2020                                                                                 --
----------------------------------------------------------------------------------------------------------------
--  Does operation decoding, and issues the result in a one-hot decoding form to the next stage               --
--  In this stage we detect based on the incoming instruction whether superscalar execution can be enabled.   --
--  This pipeline stage always takes one cycle latency                                                        --
----------------------------------------------------------------------------------------------------------------

-- package riscv_kless is new work.riscv_klessydra;

-- ieee packages ------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_misc.all;
use ieee.numeric_std.all;
use std.textio.all;

-- local packages ------------
use work.riscv_klessydra.all;
--use work.riscv_kless.all;
--use work.klessydra_parameters.all;

-- pipeline  pinout --------------------
entity ID_STAGE is
  generic(
    THREAD_POOL_SIZE           : natural;
    RV32M                      : natural;
    superscalar_exec_en        : natural;
    RF_SIZE                    : natural;
    RF_CEIL                    : natural
    );
  port (
  -- Branch Control Signals
    comparator_en              : out std_logic;
    ls_instr_req               : out std_logic;
    ie_instr_req               : out std_logic;
    decoded_instruction_IE     : out std_logic_vector(EXEC_UNIT_INSTR_SET_SIZE-1 downto 0);
    decoded_instruction_LS     : out std_logic_vector(LS_UNIT_INSTR_SET_SIZE-1 downto 0);
    data_be_ID                 : out std_logic_vector(3 downto 0);
    data_width_ID              : out std_logic_vector(1 downto 0);
    amo_store                  : in  std_logic;
    amo_load                   : out std_logic;
    amo_load_skip              : out std_logic;
    load_op                    : out std_logic;
    store_op                   : out std_logic;
    instr_word_IE              : out std_logic_vector(31 downto 0);
    MSTATUS                    : in  MSTATUS_array;
    harc_ID                    : in  natural range THREAD_POOL_SIZE-1 downto 0;
    pc_ID                      : in  std_logic_vector(31 downto 0);  -- pc_ID is PC entering ID stage
    rs1_valid_ID               : in  std_logic;
    rs2_valid_ID               : in  std_logic;
    rd_valid_ID                : in  std_logic;
    rd_read_valid_ID           : in  std_logic;
    core_busy_IE               : in  std_logic;
    core_busy_LS               : in  std_logic;
    busy_LS                    : in  std_logic;
    busy_ID                    : out std_logic;
    ls_parallel_exec           : out std_logic;
    pc_IE                      : out std_logic_vector(31 downto 0);  -- pc_IE is pc entering stage IE ***
    WB_EN_next_ID              : out std_logic;
    instr_rvalid_ID            : in  std_logic; 
    instr_rvalid_IE            : out std_logic;  -- validity bit at IE input
    instr_rvalid_ID_int        : out std_logic;
    halt_IE                    : out std_logic;
    halt_LSU                   : out std_logic;
    instr_word_ID              : in  std_logic_vector(31 downto 0);
    set_except_condition       : in  std_logic;
    served_irq                 : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
    signed_op                  : out std_logic;
    harc_EXEC                  : out natural range THREAD_POOL_SIZE-1 downto 0;
    harc_WB                    : in  natural range THREAD_POOL_SIZE-1 downto 0;
    absolute_jump              : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
    harc_LS_WB                 : in  natural range THREAD_POOL_SIZE-1 downto 0;
    harc_IE_WB                 : in  natural range THREAD_POOL_SIZE-1 downto 0;
    LS_WB_EN                   : in  std_logic;
    IE_WB_EN                   : in  std_logic;
    MUL_WB_EN                  : in  std_logic;
    LS_WB_EN_wire              : in  std_logic;
    IE_WB_EN_wire              : in  std_logic;
    MUL_WB_EN_wire             : in  std_logic;
    instr_word_LS_WB           : in  std_logic_vector(31 downto 0);
    instr_word_IE_WB           : in  std_logic_vector(31 downto 0);
    PC_offset_ID               : out std_logic_vector(31 downto 0);
    set_branch_condition_ID    : out std_logic;
    zero_rd                    : out std_logic;
    -- clock, reset active low
    clk_i                      : in  std_logic;
    rst_ni                     : in  std_logic
    );

end entity;  ------------------------------------------


-- Klessydra T03x (4 stages) pipeline implementation -----------------------
architecture DECODE of ID_STAGE is

  subtype harc_range is natural range THREAD_POOL_SIZE-1 downto 0;

  -- instruction operands
  signal S_Imm_IE                  : std_logic_vector(11 downto 0);  -- debugging signals
  signal I_Imm_IE                  : std_logic_vector(11 downto 0);  -- debugging signals
  signal B_Imm_IE                  : std_logic_vector(11 downto 0);  -- debugging signals
  signal CSR_ADDR_IE               : std_logic_vector(11 downto 0);  -- debugging signals

  -- data dependency checker
  signal valid_buf_lat             : harc_vec_array;  -- valid buffer for data dependency checker
  signal valid_buf                 : harc_vec_array;  -- valid buffer for data dependency checker
  signal valid_buf_wire            : harc_vec_array;  -- valid buffer for data dependency checker
  signal rf_rs1_valid              : std_logic_vector(harc_range);
  signal rf_rs2_valid              : std_logic_vector(harc_range);
  signal rf_rd_read_valid          : std_logic_vector(harc_range);
  signal rs1_valid_int             : std_logic;
  signal rs2_valid_int             : std_logic;
  signal rd_valid_int              : std_logic;
  signal rd_read_valid_int         : std_logic;
  signal rs1_valid                 : std_logic;
  signal rs2_valid                 : std_logic;
  signal rd_valid                  : std_logic;
  signal rd_read_valid             : std_logic;

  signal Immediate                 : std_logic_vector(31 downto 0);

  signal instr_rvalid_ID_int_lat   : std_logic;

  signal block_valid_wb            : std_logic;
  signal zero_rd_wire              : std_logic;

  -- internal signals (VHDL1993)
  signal ls_parallel_exec_int      : std_logic;
  signal instr_rvalid_ID_intt      : std_logic;
  signal instr_rvalid_IE_int       : std_logic;

  function rs1 (signal instr : in std_logic_vector(31 downto 0)) return integer is
  begin
    return to_integer(unsigned(instr(15+(RF_CEIL-1) downto 15)));
  end;

  function rs2 (signal instr : in std_logic_vector(31 downto 0)) return integer is
  begin
    return to_integer(unsigned(instr(20+(RF_CEIL-1) downto 20)));
  end;

  function rd (signal instr : in std_logic_vector(31 downto 0)) return integer is
  begin
    return to_integer(unsigned(instr(7+(RF_CEIL-1) downto 7)));
  end;

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

  function or_vect_bits(input_vector : std_logic_vector) return std_logic is
    variable result : std_logic := '0';
  begin
    for i in input_vector'range loop
      result := result or input_vector(i);
    end loop;
    return result;
  end function or_vect_bits;


begin

  -- connecting internal signals
  ls_parallel_exec <= ls_parallel_exec_int;
  instr_rvalid_id_int <= instr_rvalid_id_intt;
  instr_rvalid_IE <= instr_rvalid_IE_int;

  zero_rd_wire  <= '1' when rd(instr_word_ID) = 0 else '0';

  rs1_valid     <= rs1_valid_int;  
  rs2_valid     <= rs2_valid_int;  
  rd_valid      <= rd_valid_int;  
  rd_read_valid <= rd_read_valid_int;  


  fsm_ID_sync : process(clk_i, rst_ni, instr_word_ID)  -- synch single state process
    variable OPCODE_wires  : std_logic_vector(6 downto 0);
    variable FUNCT3_wires  : std_logic_vector(2 downto 0);
    variable FUNCT7_wires  : std_logic_vector(6 downto 0);
    variable FUNCT12_wires : std_logic_vector(11 downto 0);
  begin
    OPCODE_wires  := OPCODE(instr_word_ID);
    FUNCT3_wires  := FUNCT3(instr_word_ID);
    FUNCT7_wires  := FUNCT7(instr_word_ID);
    FUNCT12_wires := FUNCT12(instr_word_ID);
    if rst_ni = '0' then
      pc_IE               <= (others => '0');
      harc_EXEC           <=  0;
      instr_rvalid_IE_int     <= '0';
      ie_instr_req        <= '0';
      ls_instr_req        <= '0';
      comparator_en       <= '0';
      WB_EN_next_ID       <= '0';
    elsif rising_edge(clk_i) then
      ls_instr_req     <= '0';
      ie_instr_req     <= '0';
      WB_EN_next_ID    <= '0'; 
      instr_rvalid_IE_int  <= '0';

      if served_irq(harc_ID)   = '1'  or
         core_busy_IE                    = '1'  or 
         core_busy_LS                    = '1'  or 
         ls_parallel_exec_int                = '0'  then -- the instruction pipeline is halted
        halt_IE  <= '1';
        halt_LSU <= '1';
      elsif instr_rvalid_ID_intt = '0' then -- wait for a valid instruction
        halt_IE  <= '0';
        halt_LSU <= '0';
      else  -- process the incoming instruction 
        zero_rd  <= zero_rd_wire;
        halt_IE  <= '0';
        halt_LSU <= '0';
        instr_rvalid_IE_int  <= '1';
        instr_word_IE  <= instr_word_ID;
        -- pc propagation
        pc_IE               <= pc_ID;
        -- harc propagation
        harc_EXEC           <= harc_ID;
        --S_Imm_IE           <= std_logic_vector(to_unsigned(S_immediate(instr_word_ID), 12));
        --I_Imm_IE           <= std_logic_vector(to_unsigned(to_integer(unsigned(I_immediate(instr_word_ID))), 12));
        --B_Imm_IE           <= std_logic_vector(to_unsigned(to_integer(unsigned(B_immediate(instr_word_ID))), 12));
        --CSR_ADDR_IE        <= std_logic_vector(to_unsigned(to_integer(unsigned(CSR_ADDR(instr_word_ID))), 12));
        
        comparator_en        <= '0';
        ie_instr_req         <= '0';
        amo_load_skip        <= '0';
        amo_load             <= '0';
        load_op              <= '0';
        store_op             <= '0';
        signed_op            <= '0';

        -----------------------------------------------------------------------------------------------------------
        --  ██╗███╗   ██╗███████╗████████╗██████╗     ██████╗ ███████╗ ██████╗ ██████╗ ██████╗ ███████╗██████╗   --
        --  ██║████╗  ██║██╔════╝╚══██╔══╝██╔══██╗    ██╔══██╗██╔════╝██╔════╝██╔═══██╗██╔══██╗██╔════╝██╔══██╗  --
        --  ██║██╔██╗ ██║███████╗   ██║   ██████╔╝    ██║  ██║█████╗  ██║     ██║   ██║██║  ██║█████╗  ██████╔╝  --
        --  ██║██║╚██╗██║╚════██║   ██║   ██╔══██╗    ██║  ██║██╔══╝  ██║     ██║   ██║██║  ██║██╔══╝  ██╔══██╗  --
        --  ██║██║ ╚████║███████║   ██║   ██║  ██║    ██████╔╝███████╗╚██████╗╚██████╔╝██████╔╝███████╗██║  ██║  --
        --  ╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝   ╚═╝  ╚═╝    ╚═════╝ ╚══════╝ ╚═════╝ ╚═════╝ ╚═════╝ ╚══════╝╚═╝  ╚═╝  --
        -----------------------------------------------------------------------------------------------------------

        -- process the instruction
        -- read data from the operand registers
        -- Decode Starts here

        case OPCODE_wires is
      
          when OP_IMM =>
            ie_instr_req <= '1';
            if zero_rd_wire = '0' then
              WB_EN_next_ID <= '1';
              case FUNCT3_wires is
                when ADDI =>            -- ADDI instruction
                  decoded_instruction_IE <= ADDI_pattern;
                when SLTI =>            -- SLTI instruction
                  decoded_instruction_IE <= SLTI_pattern;
                when SLTIU =>           -- SLTIU instruction
                  decoded_instruction_IE <= SLTIU_pattern;
                when ANDI =>            -- ANDI instruction
                  decoded_instruction_IE <= ANDI_pattern;
                when ORI =>             -- ORI instruction
                  decoded_instruction_IE <= ORI_pattern;
                when XORI =>            -- XORI instruction
                  decoded_instruction_IE <= XORI_pattern;
                when SLLI =>            -- SLLI instruction
                  decoded_instruction_IE <= SLLI_pattern;
                when SRLI_SRAI =>
                  case FUNCT7_wires is
                    when SRLI7 =>       -- SRLI instruction
                      decoded_instruction_IE <= SRLI7_pattern;
                    when SRAI7 =>       -- SRAI instruction
                      decoded_instruction_IE <= SRAI7_pattern;
                    when others =>  -- ILLEGAL_INSTRUCTION                                      
                      decoded_instruction_IE <= ILL_pattern;
                  end case;  -- FUNCT7_wires cases
                when others =>  -- ILLEGAL_INSTRUCTION                                  
                  decoded_instruction_IE <= ILL_pattern;
              end case;  -- FUNCT3_wires cases   
            else                -- R0_INSTRUCTION
              decoded_instruction_IE <= NOP_pattern;
            end if;  -- if rd(instr_word_ID) /=0
        
          when LUI =>                   -- LUI instruction
            ie_instr_req <= '1';
            if zero_rd_wire = '0' then
              WB_EN_next_ID <= '1';
              decoded_instruction_IE <= LUI_pattern;
            else                        -- R0_INSTRUCTION
              decoded_instruction_IE <= NOP_pattern;
            end if;
        
          when AUIPC =>                 -- AUIPC instruction
            ie_instr_req <= '1';
            if zero_rd_wire = '0' then
              WB_EN_next_ID <= '1';
              decoded_instruction_IE <= AUIPC_pattern;
            else                        -- R0_INSTRUCTION
              decoded_instruction_IE <= NOP_pattern;
            end if;

          when OP =>
            ie_instr_req <= '1';
            if zero_rd_wire = '0' then
              case FUNCT7_wires is
                when OP_I1 =>
                  WB_EN_next_ID <= '1';
                  case FUNCT3_wires is
                    when ADD => --ADD instruction
                      decoded_instruction_IE <= ADD7_pattern;
                    when SLT =>             -- SLT instruction 
                      comparator_en <= '1';
                      decoded_instruction_IE <= SLT_pattern;
                    when SLTU =>            -- SLTU instruction
                      comparator_en <= '1';
                      decoded_instruction_IE <= SLTU_pattern;
                    when ANDD =>            -- AND instruction
                      decoded_instruction_IE <= ANDD_pattern;
                    when ORR =>             -- OR instruction
                      decoded_instruction_IE <= ORR_pattern;
                    when XORR =>            -- XOR instruction        
                      decoded_instruction_IE <= XORR_pattern;
                    when SLLL =>            -- SLL instruction        
                      decoded_instruction_IE <= SLLL_pattern;
                    when SRLL =>       -- SRL instruction   
                      decoded_instruction_IE <= SRLL7_pattern;
                    when others =>  -- ILLEGAL_INSTRUCTION                                      
                      decoded_instruction_IE <= ILL_pattern;
                  end case;
                when OP_I2 =>
                  WB_EN_next_ID <= '1';
                  case FUNCT3_wires is
                    when SUB7 =>
                      decoded_instruction_IE <= SUB7_pattern;
                    when SRAA =>
                      decoded_instruction_IE <= SRAA7_pattern;
                    when others =>  -- ILLEGAL_INSTRUCTION                                      
                      decoded_instruction_IE <= ILL_pattern;
                  end case;
                when OP_M  =>                 -- MUL/DIV instructions
                  if RV32M = 1 then
                    case FUNCT3_wires is
                      when MUL =>
                        WB_EN_next_ID <= '1';
                        comparator_en <= '1';
                        decoded_instruction_IE <= MUL_pattern;
                      when MULH =>
                        comparator_en <= '1';
                        signed_op <= '1';
                        decoded_instruction_IE <= MULH_pattern;
                      when MULHSU =>
                        comparator_en <= '1';
                        signed_op <= '1';
                        decoded_instruction_IE <= MULHSU_pattern;
                      when MULHU =>
                        comparator_en <= '1';
                        decoded_instruction_IE <= MULHU_pattern;
                      when DIV =>
                        comparator_en <= '1';
                        signed_op <= '1';
                        decoded_instruction_IE <= DIV_pattern;
                      when DIVU =>
                        comparator_en <= '1';
                        decoded_instruction_IE <= DIVU_pattern;
                      when REMD =>
                        comparator_en <= '1';
                        signed_op <= '1';
                        decoded_instruction_IE <= REM_pattern;
                      when REMDU =>
                        comparator_en <= '1';
                        decoded_instruction_IE <= REMU_pattern;
                      when others =>
                        decoded_instruction_IE <= ILL_pattern;
                    end case;
                  else
                    decoded_instruction_IE <= ILL_pattern;                  
                  end if;
                when others =>  -- ILLEGAL_INSTRUCTION                                      
                  decoded_instruction_IE <= ILL_pattern;
              end case;
            else                        -- R0_INSTRUCTION
              decoded_instruction_IE <= NOP_pattern;
            end if;

          when JAL =>                   -- JAL instruction
            if zero_rd_wire = '0' then
              WB_EN_next_ID <= '1';
            end if;
            ie_instr_req <= '1';
            decoded_instruction_IE <= JAL_pattern;

          when JALR =>                  -- JALR instruction
            if zero_rd_wire = '0' then
              WB_EN_next_ID <= '1';
            end if;
            ie_instr_req <= '1';
            decoded_instruction_IE <= JALR_pattern;

          when BRANCH =>      -- BRANCH instruction         
            ie_instr_req <= '1';
            case FUNCT3_wires is
              when BEQ =>               -- BEQ instruction   
                comparator_en <= '1';
                decoded_instruction_IE <= BEQ_pattern;
              when BNE =>               -- BNE instruction
                comparator_en <= '1';
                decoded_instruction_IE <= BNE_pattern;
              when BLT =>               -- BLT instruction   
                comparator_en <= '1';
                decoded_instruction_IE <= BLT_pattern;
              when BLTU =>              -- BLTU instruction
                comparator_en <= '1';
                decoded_instruction_IE <= BLTU_pattern;
              when BGE =>               -- BGE instruction
                comparator_en <= '1';
                decoded_instruction_IE <= BGE_pattern;
              when BGEU =>              -- BGEU instruction
                comparator_en <= '1';
                decoded_instruction_IE <= BGEU_pattern;
              when others =>  -- ILLEGAL_INSTRUCTION                      
                decoded_instruction_IE <= ILL_pattern;
            end case;  -- FUNCT3_wires cases

          when LOAD =>                  -- LOAD instruction
            load_op <= '1';
            if zero_rd_wire = '0' then  -- is all in the next_state process
              case FUNCT3_wires is
                when LW =>
                  ls_instr_req <= '1';
                  data_width_ID <= "10";
                  data_be_ID   <= "1111";
                  decoded_instruction_LS <= LW_pattern;
                when LH =>
                  ls_instr_req <= '1';
                  data_width_ID <= "01";
                  data_be_ID <= "0011";
                  decoded_instruction_LS <= LH_pattern;
                when LHU =>
                  ls_instr_req <= '1';
                  data_width_ID <= "01";
                  data_be_ID <= "0011";
                  decoded_instruction_LS <= LHU_pattern;
                when LB =>
                  ls_instr_req <= '1';
                  data_width_ID <= "00";
                  data_be_ID <= "0001";
                  decoded_instruction_LS <= LB_pattern;
                when LBU =>
                  ls_instr_req <= '1';
                  data_width_ID <= "00";
                  data_be_ID <= "0001";
                  decoded_instruction_LS <= LBU_pattern;
                when others =>          -- ILLEGAL_INSTRUCTION
                  ie_instr_req <= '1';
                  decoded_instruction_IE <= ILL_pattern;
              end case;
            else                        -- R0_INSTRUCTION
              ie_instr_req <= '1';
              decoded_instruction_IE <= NOP_pattern;
            end if;

          when STORE =>                 -- STORE instruction
            store_op <= '1';
            case FUNCT3_wires is
              when SW =>                -- is all in the next_state process
                ls_instr_req <= '1';
                ie_instr_req <= '1';
                data_width_ID <= "10";
                data_be_ID <= "1111";
                decoded_instruction_LS <= SW_pattern;
                decoded_instruction_IE <= SW_MIP_pattern;
              when SH =>
                ls_instr_req <= '1';
                data_width_ID <= "01";
                data_be_ID <= "0011";
                decoded_instruction_LS <= SH_pattern;
              when SB =>
                ls_instr_req <= '1';
                data_width_ID <= "00";
                data_be_ID <= "0001";
                decoded_instruction_LS <= SB_pattern;
              when others =>  -- ILLEGAL_INSTRUCTION
                ie_instr_req <= '1';
                decoded_instruction_IE <= ILL_pattern;
            end case;

          when MISC_MEM =>
            ie_instr_req <= '1';
            case FUNCT3_wires is
              when FENCE =>             -- FENCE instruction
                decoded_instruction_IE <= FENCE_pattern;
              when FENCEI =>            -- FENCEI instruction
                decoded_instruction_IE <= FENCEI_pattern;
              when others =>            -- ILLEGAL_INSTRUCTION
                decoded_instruction_IE <= ILL_pattern;
            end case;  -- FUNCT3_wires cases

          when SYSTEM =>
            ie_instr_req <= '1';
            case FUNCT3_wires is
              when PRIV =>
                if (rs1(instr_word_ID) = 0 and zero_rd_wire = '1') then
                  case FUNCT12_wires is
                    when ECALL =>       -- ECALL instruction
                      decoded_instruction_IE <= ECALL_pattern;
                    when EBREAK =>      -- EBREAK instruction       
                      decoded_instruction_IE <= EBREAK_pattern;
                    when mret =>        -- mret instruction
                      decoded_instruction_IE <= MRET_pattern;
                    when WFI =>         -- WFI instruction
                      decoded_instruction_IE <= WFI_pattern;
                    when others =>  -- ILLEGAL_INSTRUCTION                                              
                      decoded_instruction_IE <= ILL_pattern;
                  end case;  -- FUNCT12_wires cases
                else  -- ILLEGAL_INSTRUCTION
                  decoded_instruction_IE <= ILL_pattern;
                end if;
              when CSRRW =>
                decoded_instruction_IE <= CSRRW_pattern;
              when CSRRS =>
                decoded_instruction_IE <= CSRRS_pattern;
              when CSRRC =>
                decoded_instruction_IE <= CSRRC_pattern;
              when CSRRWI =>
                decoded_instruction_IE <= CSRRWI_pattern;
              when CSRRSI =>
                decoded_instruction_IE <= CSRRSI_pattern;
              when CSRRCI =>
                decoded_instruction_IE <= CSRRCI_pattern;
              when others =>  -- ILLEGAL_INSTRUCTION
                decoded_instruction_IE <= ILL_pattern;
            end case;  -- FUNCT3_wires cases

          when AMO =>
            data_width_ID <= "10";
            case FUNCT3_wires is
              when SINGLE =>
                ls_instr_req <= '1';
                decoded_instruction_LS <= AMOSWAP_pattern;
                if zero_rd_wire = '0' then
                  amo_load_skip          <= '0';
                  if amo_store = '1' then
                    amo_load <= '0';
                  elsif amo_store = '0' then
                    amo_load <= '1';
                  end if;
                else
                  amo_load_skip <= '1';
                end if;
              when others =>            -- ILLEGAL_INSTRUCTION
                ie_instr_req <= '1';
                decoded_instruction_IE <= ILL_pattern;
            end case;

          when others =>                -- ILLEGAL_INSTRUCTION
            ie_instr_req <= '1';
            decoded_instruction_IE <= ILL_pattern;

        end case;  -- OPCODE_wires cases                           
        -- Decode OF INSTRUCTION (END) --------------------------

      end if;  -- instr. conditions
    end if;  -- clk
  end process;

  instr_rvalid_ID_intt <= instr_rvalid_ID or instr_rvalid_ID_int_lat when instr_rvalid_IE_int = '0' else instr_rvalid_ID;

  process(clk_i, rst_ni)
  begin
    if rst_ni = '0' then
      instr_rvalid_ID_int_lat <= '0';
    elsif rising_edge(clk_i) then
      if core_busy_LS      = '0' and 
         core_busy_IE      = '0' and 
         ls_parallel_exec_int  = '1' then
        instr_rvalid_ID_int_lat <= '0';
      elsif instr_rvalid_ID = '1' then -- else latch the internal instruction to maintain its state
        instr_rvalid_ID_int_lat <= '1';
      end if;
    end if;
  end process;


---------------------------------------------------------------------------------------------------------------------------------------------------------------
--  ███████╗██╗   ██╗██████╗ ███████╗██████╗ ███████╗ ██████╗ █████╗ ██╗      █████╗ ██████╗     ███████╗███╗   ██╗ █████╗ ██████╗ ██╗     ███████╗██████╗   --
--  ██╔════╝██║   ██║██╔══██╗██╔════╝██╔══██╗██╔════╝██╔════╝██╔══██╗██║     ██╔══██╗██╔══██╗    ██╔════╝████╗  ██║██╔══██╗██╔══██╗██║     ██╔════╝██╔══██╗  --
--  ███████╗██║   ██║██████╔╝█████╗  ██████╔╝███████╗██║     ███████║██║     ███████║██████╔╝    █████╗  ██╔██╗ ██║███████║██████╔╝██║     █████╗  ██████╔╝  --
--  ╚════██║██║   ██║██╔═══╝ ██╔══╝  ██╔══██╗╚════██║██║     ██╔══██║██║     ██╔══██║██╔══██╗    ██╔══╝  ██║╚██╗██║██╔══██║██╔══██╗██║     ██╔══╝  ██╔══██╗  --
--  ███████║╚██████╔╝██║     ███████╗██║  ██║███████║╚██████╗██║  ██║███████╗██║  ██║██║  ██║    ███████╗██║ ╚████║██║  ██║██████╔╝███████╗███████╗██║  ██║  --
--  ╚══════╝ ╚═════╝ ╚═╝     ╚══════╝╚═╝  ╚═╝╚══════╝ ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝    ╚══════╝╚═╝  ╚═══╝╚═╝  ╚═╝╚═════╝ ╚══════╝╚══════╝╚═╝  ╚═╝  --
---------------------------------------------------------------------------------------------------------------------------------------------------------------

  Superscalar_Enable : if superscalar_exec_en = 1 generate
  fsm_ID_comb : process(
                          instr_word_ID, busy_LS, instr_rvalid_ID_intt,
                          core_busy_IE, core_busy_LS, ls_parallel_exec_int
                       ) --VHDL1993
  variable OPCODE_wires  : std_logic_vector (6 downto 0);
  variable parallel_execution_cond : boolean;
  begin
    OPCODE_wires  := OPCODE(instr_word_ID);
    -- parallelism enablers, halts the pipeline when it is zero. -------------------
    parallel_execution_cond := (OPCODE_wires = LOAD or OPCODE_wires = STORE or OPCODE_wires = AMO or OPCODE_wires = KMEM) and busy_LS = '1' and instr_rvalid_id_intt= '1';

    if parallel_execution_cond then
      ls_parallel_exec_int  <= '0';
    else 
      ls_parallel_exec_int  <= '1';
    end if;

    busy_ID <= '0';  -- wait for a valid instruction or process the instruction 
    -- A data deoendency is only valid to make a stall when the current dependent instruction is not flushed 
    if core_busy_IE = '1' or core_busy_LS = '1' or ls_parallel_exec_int = '0' then
      busy_ID <= '1';  -- wait for the stall to finish, block new instructions
    end if; 
  end process;
  end generate;

  Superscalar_Disable: if superscalar_exec_en = 0 generate
  fsm_ID_comb : process(
                          instr_word_ID, busy_LS, instr_rvalid_ID_intt,
                          core_busy_IE, core_busy_LS, ls_parallel_exec_int
                       ) --VHDL1993
  variable OPCODE_wires  : std_logic_vector (6 downto 0);
  variable parallel_execution_cond : boolean;
  begin
    OPCODE_wires      := OPCODE(instr_word_ID); 
    busy_ID           <= '0';
    parallel_execution_cond := busy_LS = '1' and instr_rvalid_id_intt= '1';

    if parallel_execution_cond then
      ls_parallel_exec_int  <= '0';
    else
      ls_parallel_exec_int <= '1';
    end if;

    -- A data deoendency is only valid to make a stall when the current dependent instruction is not flushed
    if core_busy_IE = '1' or core_busy_LS = '1' or ls_parallel_exec_int = '0' then
      busy_ID <= '1';  -- wait for the stall to finish, block new instructions 
    end if; 
  end process;
  end generate;

---------------------------------------------------------------------- end of ID stage -----------
--------------------------------------------------------------------------------------------------
end DECODE;
--------------------------------------------------------------------------------------------------
-- END of ID architecture ------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------
