----------------------------------------------------------------------------------------------------------------
--  Stage ID - (Instruction decode and registerfile read)                                                     --
--  Author(s): Abdallah Cheikh abdallah.cheikh@uniroma1.it (abdallah93.as@gmail.com)                          --
--                                                                                                            --
--  Date Modified: 07-04-2020                                                                                 --
----------------------------------------------------------------------------------------------------------------
--  Registerfiles of the incoming hart are read in this stage in parallel with the decoding                   --
--  Two types of registerfiles can be generaated for XILINX FPGAs LUTAM based or FF based dpeneding on the    --
--  setting of the generic variaabble chosen                                                                  --
--  The scratchpad memory mapper also exists in this stage, which maps the address to the corresponding SPM   --
--  This pipeline stage always takes one cycle latency                                                        --
----------------------------------------------------------------------------------------------------------------

-- ieee packages ------------
library ieee;
use ieee.math_real.all;
use ieee.std_logic_1164.all;
use ieee.std_logic_misc.all;
use ieee.numeric_std.all;
use std.textio.all;

-- local packages ------------
use work.riscv_klessydra.all;
--use work.klessydra_parameters.all;

-- pipeline  pinout --------------------
entity REGISTERFILE is
  generic(
    THREAD_POOL_SIZE           : natural;
    lutram_rf                  : natural;
    latch_rf                   : natural;
    RF_SIZE                    : natural;
    RF_CEIL                    : natural
    );
  port (
    -- clock, reset active low
    clk_i                   : in  std_logic;
    rst_ni                  : in  std_logic;
    -- Branch Control Signals
    harc_ID                 : in  natural range THREAD_POOL_SIZE-1 downto 0;
    pc_ID                   : in  std_logic_vector(31 downto 0);  -- pc_ID is PC entering ID stage
    core_busy_IE            : in  std_logic;
    core_busy_LS            : in  std_logic;
    ls_parallel_exec        : in  std_logic;
    instr_rvalid_ID         : in  std_logic;
    instr_rvalid_ID_int     : in  std_logic;
    instr_word_ID           : in  std_logic_vector(31 downto 0);
    LS_WB_EN                : in  std_logic;
    IE_WB_EN                : in  std_logic;
    MUL_WB_EN               : in  std_logic;
    IE_WB                   : in  std_logic_vector(31 downto 0);
    MUL_WB                  : in  std_logic_vector(31 downto 0);
    LS_WB                   : in  std_logic_vector(31 downto 0);
    instr_word_LS_WB        : in  std_logic_vector(31 downto 0);
    instr_word_IE_WB        : in  std_logic_vector(31 downto 0);
    harc_LS_WB              : in  natural range THREAD_POOL_SIZE-1 downto 0;
    harc_IE_WB              : in  natural range THREAD_POOL_SIZE-1 downto 0;
    zero_rs1                : out std_logic;
    zero_rs2                : out std_logic;
    pass_BEQ                : out std_logic;
    pass_BNE                : out std_logic;
    pass_BLT                : out std_logic;
    pass_BLTU               : out std_logic;
    pass_BGE                : out std_logic;
    pass_BGEU               : out std_logic;
    RS1_Data_IE             : out std_logic_vector(31 downto 0);
    RS2_Data_IE             : out std_logic_vector(31 downto 0);
    RD_Data_IE              : out std_logic_vector(31 downto 0);
    data_addr_internal_IE   : out std_logic_vector(31 downto 0)
    );
end entity;  ------------------------------------------


-- Klessydra T03x (4 stages) pipeline implementation -----------------------
architecture RF of REGISTERFILE is

  attribute DONT_TOUCH   : boolean;

  subtype harc_range is natural range THREAD_POOL_SIZE - 1 downto 0;
  subtype rf_range is natural range RF_SIZE - 1 downto 0;

  signal RF_res          : std_logic_vector(31 downto 0);
  signal WB_EN_lat       : std_logic;
  signal harc_LAT        : harc_range;
  signal instr_word_LAT  : std_logic_vector(31 downto 0);

  signal regfile_lutram_rs1 : lutram_array;
  signal regfile_lutram_rs2 : lutram_array;
  signal regfile_lutram_rd  : lutram_array;

  attribute ram_style : string;
  attribute ram_style of RS1_Data_IE        : signal is "reg"; -- AAA i think these are unecessary and need to be removed
  attribute ram_style of RS2_Data_IE        : signal is "reg"; -- AAA i think these are unecessary and need to be removed
  attribute ram_style of RD_Data_IE         : signal is "reg"; -- AAA i think these are unecessary and need to be removed
  attribute ram_style of regfile_lutram_rs1 : signal is "distributed";
  attribute ram_style of regfile_lutram_rs2 : signal is "distributed";
  attribute ram_style of regfile_lutram_rd  : signal is "distributed";

  signal RS1_Data_IE_wire       : std_logic_vector(31 downto 0);
  signal RS2_Data_IE_wire       : std_logic_vector(31 downto 0);
  signal RD_Data_IE_wire        : std_logic_vector(31 downto 0);

  -- instruction operands
  signal RS1_Addr_IE            : std_logic_vector(4 downto 0);   -- debugging signals
  signal RS2_Addr_IE            : std_logic_vector(4 downto 0);   -- debugging signals
  signal RD_Addr_IE             : std_logic_vector(4 downto 0);   -- debugging signals
  signal RD_EN                  : std_logic;
  signal WB_RD                  : std_logic_vector(31 downto 0);
  signal WB_EN                  : std_logic;
  signal harc_WB                : harc_range;
  signal instr_word_WB          : std_logic_vector(31 downto 0);

  --internal signals (VHDL1993)
  signal regfile_int                   : regfile_array;
  attribute DONT_TOUCH of regfile_int : signal is true;

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

begin

  ------------------------------------------------------------
  --  ██████╗ ███████╗ ██████╗ ███████╗██╗██╗     ███████╗  --
  --  ██╔══██╗██╔════╝██╔════╝ ██╔════╝██║██║     ██╔════╝  --
  --  ██████╔╝█████╗  ██║  ███╗█████╗  ██║██║     █████╗    --
  --  ██╔══██╗██╔══╝  ██║   ██║██╔══╝  ██║██║     ██╔══╝    --
  --  ██║  ██║███████╗╚██████╔╝██║     ██║███████╗███████╗  --
  --  ╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═╝     ╚═╝╚══════╝╚══════╝  --
  ------------------------------------------------------------

  RF_FF : if lutram_rf = 0 generate

  LATCH_REGFILE : if latch_rf = 1 generate

  RF_WR_ACCESS : process(
                          WB_EN_lat, RF_res
                        )  -- synch single state process
  begin
      for h in harc_range loop
        regfile_int(h)(0) <= (others => '0');
      end loop;
      if WB_EN_lat = '1' then
        regfile_int(harc_LAT)(rd(instr_word_LAT)) <= RF_res;
      end if;
  end process;

  end generate; -- latch_rf = 1


  FF_REGFILE : if latch_rf = 0 generate

  RF_WR_ACCESS : process(clk_i, rst_ni, instr_word_ID)  -- synch single state process
  begin
    if rst_ni = '0' then
      for h in harc_range loop
        if latch_rf = 0 then
          for g in rf_range loop
            regfile_int(h)(g) <= (others => '0');
          end loop;
          --regfile_int(h)(0) <= (others => '0');
        end if;
      end loop;
    elsif rising_edge(clk_i) then
      if WB_EN = '1' then
        regfile_int(harc_WB)(rd(instr_word_WB)) <= WB_RD;
      end if;
    end if;  -- clk
  end process;

  end generate; -- latch_rf = 0


  RF_RD_ACCESS : process(clk_i, rst_ni, instr_word_ID)  -- synch single state process
  begin
    if rst_ni = '0' then
      WB_EN_lat <= '0';
      harc_LAT <= THREAD_POOL_SIZE-1;
      instr_word_LAT <= (others => '0');
    elsif rising_edge(clk_i) then
      harc_LAT <= harc_WB;
      instr_word_LAT <= instr_word_WB;
      WB_EN_lat <= WB_EN;
      if core_busy_IE = '1' or core_busy_LS = '1' or ls_parallel_exec = '0' then -- the instruction pipeline is halted
      elsif instr_rvalid_ID_int = '0' then -- wait for a valid instruction
      else  -- process the incoming instruction 

        data_addr_internal_IE <= std_logic_vector(signed(regfile_int(harc_ID)(rs1(instr_word_ID))) + signed(S_immediate(instr_word_ID)));

        ----- REGISTERFILE READ IS DONE HERE --------------------------------------------------------------------------------------------------------------
         RS1_Data_IE <= RS1_Data_IE_wire; 
         RS2_Data_IE <= RS2_Data_IE_wire; 

       -- pragma translate_off
        RD_Data_IE  <= regfile_int(harc_ID)(rd(instr_word_ID)); -- reading the 'rd' data here is only for debugging purposes if the acclerator is disabled
        RS1_Addr_IE <= std_logic_vector(to_unsigned(rs1(instr_word_ID), 5)); -- debugging signals
        RS2_Addr_IE <= std_logic_vector(to_unsigned(rs2(instr_word_ID), 5)); -- debugging signals
        RD_Addr_IE  <= std_logic_vector(to_unsigned(rd(instr_word_ID), 5)); -- debugging signals
       -- pragma translate_on
       ----------------------------------------------------------------------------------------------------------------------------------------------------
      end if;  -- instr. conditions
      if WB_EN = '1' then
        if latch_rf = 1 then
          RF_res <= WB_RD;
        end if;
      end if;
    end if;  -- clk
  end process;

  RS1_Data_IE_wire <= regfile_int(harc_ID)(rs1(instr_word_ID)); 
  RS2_Data_IE_wire <= regfile_int(harc_ID)(rs2(instr_word_ID));
  RD_Data_IE_wire  <= regfile_int(harc_ID)(rd(instr_word_ID));

  end generate; -- lutram_rf = 0

  RF_LUTRAM : if lutram_rf = 1 generate

  RF_RD_EN : process(
                      core_busy_IE, core_busy_LS, ls_parallel_exec, instr_rvalid_ID_int,
                      instr_word_ID, regfile_lutram_rs1, regfile_lutram_rs2
                    )  -- synch single state process
  begin
    RD_EN <= '0';
    if core_busy_IE = '1' or core_busy_LS = '1' or ls_parallel_exec = '0' then -- the instruction pipeline is halted
    elsif instr_rvalid_ID_int = '0' then -- wait for a valid instruction
    else  -- process the incoming instruction 
      RD_EN <= '1';
    end if;  -- instr. conditions
    if rs1(instr_word_ID) /= 0 then
      RS1_Data_IE_wire <= regfile_lutram_rs1(32*harc_ID+rs1(instr_word_ID));
    else
      RS1_Data_IE_wire <= (others => '0');
    end if;
    if rs2(instr_word_ID) /= 0 then
      RS2_Data_IE_wire <= regfile_lutram_rs2(32*harc_ID+rs2(instr_word_ID));
    else
      RS2_Data_IE_wire <= (others => '0');
    end if;
  end process;

  RS1_ACCESS : process(clk_i)  -- synch single state process
  begin
    if rising_edge(clk_i) then
      if RD_EN = '1' then 
        data_addr_internal_IE <= std_logic_vector(signed(regfile_lutram_rs1(32*harc_ID+rs1(instr_word_ID))) + signed(S_immediate(instr_word_ID))); -- else bypass condition
        RS1_Data_IE <= RS1_Data_IE_wire;
      -- pragma translate_off
       RS1_Addr_IE <= std_logic_vector(to_unsigned(rs1(instr_word_ID), 5)); -- debugging signals
       RS2_Addr_IE <= std_logic_vector(to_unsigned(rs2(instr_word_ID), 5)); -- debugging signals
       RD_Addr_IE  <= std_logic_vector(to_unsigned(rd(instr_word_ID), 5)); -- debugging signals
      -- pragma translate_on
      end if;  -- instr. conditions
      if WB_EN = '1' then
        regfile_lutram_rs1(32*harc_WB+rd(instr_word_WB)) <= WB_RD;
      end if;
    end if;  -- clk
  end process;

  RS2_ACCESS : process(clk_i)  -- synch single state process
  begin
    if rising_edge(clk_i) then
      if RD_EN = '1' then 
        RS2_Data_IE <= RS2_Data_IE_wire;
      end if;  -- instr. conditions
      if WB_EN = '1' then
        regfile_lutram_rs2(32*harc_WB+rd(instr_word_WB)) <= WB_RD;
      end if;
    end if;  -- clk
  end process;

  end generate; -- lutram_rf = 1

-----------------------------------------------------------------------------------------------------
-- Stage WB - (WRITEBACK)
-----------------------------------------------------------------------------------------------------

  harc_WB <= harc_LS_WB when LS_WB_EN = '1' else harc_IE_WB;
  instr_word_WB <= instr_word_LS_WB when LS_WB_EN = '1' else instr_word_IE_WB;
  WB_EN <= LS_WB_EN or IE_WB_EN or MUL_WB_EN;
  WB_RD <= LS_WB when LS_WB_EN = '1' else MUL_WB when MUL_WB_EN = '1' else IE_WB;  

--------------------------------------------------------------------- end of WB Stage ----------------
------------------------------------------------------------------------------------------------------

  ------------------------------------------------------------------------------------------------------
  --   ██████╗ ██████╗ ███╗   ███╗██████╗  █████╗ ██████╗  █████╗ ████████╗ ██████╗ ██████╗ ███████╗  --
  --  ██╔════╝██╔═══██╗████╗ ████║██╔══██╗██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝██╔═══██╗██╔══██╗██╔════╝  --
  --  ██║     ██║   ██║██╔████╔██║██████╔╝███████║██████╔╝███████║   ██║   ██║   ██║██████╔╝███████╗  --
  --  ██║     ██║   ██║██║╚██╔╝██║██╔═══╝ ██╔══██║██╔══██╗██╔══██║   ██║   ██║   ██║██╔══██╗╚════██║  --
  --  ╚██████╗╚██████╔╝██║ ╚═╝ ██║██║     ██║  ██║██║  ██║██║  ██║   ██║   ╚██████╔╝██║  ██║███████║  --
  --   ╚═════╝ ╚═════╝ ╚═╝     ╚═╝╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚══════╝  --
  ------------------------------------------------------------------------------------------------------

  comparator_enable_comb : process(rst_ni, clk_i)
  begin
    if rst_ni = '0' then
      pass_BEQ  <= '0';
      pass_BNE  <= '0';
      pass_BLT  <= '0';
      pass_BGE  <= '0';
      pass_BLTU <= '0';
      pass_BGEU <= '0';
      zero_rs1  <= '0';
      zero_rs2  <= '0';
    elsif rising_edge(clk_i) then
      if core_busy_IE = '1' or core_busy_LS = '1' or ls_parallel_exec = '0' then -- the instruction pipeline is halted
      elsif instr_rvalid_ID_int = '0' then -- wait for a valid instruction
      else  -- process the incoming instruction 
        pass_BEQ  <= '0';
        pass_BNE  <= '0';
        pass_BLT  <= '0';
        pass_BGE  <= '0';
        pass_BLTU <= '0';
        pass_BGEU <= '0';
        zero_rs1  <= '0';
        zero_rs2  <= '0';
        if unsigned(RS1_Data_IE_wire) = 0 then
          zero_rs1 <= '1';
        end if;
        if unsigned(RS2_Data_IE_wire) = 0 then
          zero_rs2 <= '1';
        end if;
        if (signed(RS1_Data_IE_wire) = signed(RS2_Data_IE_wire)) then
          pass_BEQ <= '1';
        else
          pass_BNE <= '1';
        end if;
        if (signed(RS1_Data_IE_wire) < signed(RS2_Data_IE_wire)) then
          pass_BLT <= '1';
        else
          pass_BGE <= '1';
        end if;
        if (unsigned(RS1_Data_IE_wire) < unsigned(RS2_Data_IE_wire)) then
          pass_BLTU <= '1';
        else
          pass_BGEU <= '1';
        end if;
      end if;
    end if;
  end process;

---------------------------------------------------------------------- end of ID stage -----------
--------------------------------------------------------------------------------------------------
end RF;
--------------------------------------------------------------------------------------------------
-- END of ID architecture ------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------
