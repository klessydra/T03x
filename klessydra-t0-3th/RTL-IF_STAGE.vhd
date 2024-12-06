--------------------------------------------------------------------------------------------------------------
--  stage IF -- (Instruction Fetch)                                                                         --
--  Author(s): Abdallah Cheikh abdallah.cheikh@uniroma1.it (abdallah93.as@gmail.com)                        --
--                                                                                                          --
--  Date Modified: 26-02-2021                                                                               --
--------------------------------------------------------------------------------------------------------------
--  The fetch stage requests an instruction from the program memory, and the instruction arrives in the     --
--  next cycle going directly to the decode stage. The fetch stage does not hold any buffers                --
--------------------------------------------------------------------------------------------------------------

-- ieee packages ------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_misc.all;
use ieee.numeric_std.all;
use std.textio.all;

-- local packages ------------
use work.riscv_klessydra.all;
--use work.klessydra_parameters.all;

-- pipeline  pinout --------------------
entity IF_STAGE is
  generic(
    THREAD_POOL_SIZE           : natural;
    RF_CEIL                    : natural
    );
  port(
    pc_IF                      : in  std_logic_vector(31 downto 0);
    busy_ID                    : in  std_logic;
    instr_rvalid_i             : in  std_logic;
    served_irq                 : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
    harc_IF                    : in  natural range THREAD_POOL_SIZE-1 downto 0;
    harc_ID                    : out natural range THREAD_POOL_SIZE-1 downto 0;
    pc_ID                      : out std_logic_vector(31 downto 0);  -- pc_ID is PC entering ID stage
    instr_rvalid_ID            : out std_logic; 
    instr_word_ID              : out std_logic_vector(31 downto 0);
    rs1_valid_ID               : out std_logic;
    rs2_valid_ID               : out std_logic;
    rd_valid_ID                : out std_logic;
    rd_read_valid_ID           : out std_logic;
    instr_rvalid_IE            : in  std_logic;
    pc_IE                      : in  std_logic_vector(31 downto 0);
    -- branch related signals
    absolute_jump              : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
    -- clock, reset active low
    clk_i                      : in  std_logic;
    rst_ni                     : in  std_logic;
    -- program memory interface
    instr_req_o                : out std_logic;
    instr_gnt_i                : in  std_logic;
    instr_rdata_i              : in  std_logic_vector(31 downto 0);
    core_enable_i              : in  std_logic
    );
end entity;  ------------------------------------------


-- Klessydra T03x (4 stages) pipeline implementation -----------------------
architecture FETCH of IF_STAGE is

  subtype harc_range is natural range THREAD_POOL_SIZE-1 downto 0;

  -- state signals
  signal instr_word_ID_lat       : std_logic_vector(31 downto 0);

  signal Immediate               : std_logic_vector(31 downto 0); -- AAA change this to variable as well in the ID_stage

  signal rs1_valid_ID_int        : std_logic;
  signal rs2_valid_ID_int        : std_logic;
  signal rd_valid_ID_int         : std_logic;
  signal rd_read_valid_ID_int    : std_logic;
  signal rs1_valid_ID_lat        : std_logic;
  signal rs2_valid_ID_lat        : std_logic;
  signal rd_valid_ID_lat         : std_logic;
  signal rd_read_valid_ID_lat    : std_logic;

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

----------------------------------------------------------------------------------------------------
------------------------- ARCHITECTURE BEGIN -------------------------------------------------------
begin

----------------------------------------------------------------------------------------------------
-- stage IF -- (instruction fetch)
----------------------------------------------------------------------------------------------------
-- This pipeline stage is implicitly present as the program memory is synchronous
-- with 1 cycle latency.
-- The fsm_IF manages the interface with program memory. 
-- The PC_IF is updated by a dedicated unit which is transparent to the fsm_IF.
----------------------------------------------------------------------------------------------------


  instr_req_o <= not busy_ID;

  process(clk_i, rst_ni)
  begin
    if rising_edge(clk_i) then
      if instr_gnt_i = '1' then
        pc_ID   <= pc_IF;
        harc_ID <= harc_IF;
      end if;
      if instr_rvalid_i = '1' then 
        instr_word_ID_lat <= instr_rdata_i;
      end if;
    end if;
  end process;

  instr_rvalid_ID <= instr_rvalid_i;
  instr_word_ID   <= instr_rdata_i when instr_rvalid_i = '1' else instr_word_ID_lat;

--------------------------------------------------------------------- end of IF stage -------------
---------------------------------------------------------------------------------------------------

end FETCH;
--------------------------------------------------------------------------------------------------
-- END of IE architecture ------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------