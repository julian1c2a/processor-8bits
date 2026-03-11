library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use work.CONSTANTS_pkg.ALL;
use work.ALU_pkg.ALL;
use work.DataPath_pkg.ALL;
use work.AddressPath_pkg.ALL;
use work.ControlUnit_pkg.ALL;

entity ControlUnit is
    Port (
        clk      : in  std_logic;
        reset    : in  std_logic;
        
        -- Inputs from DataPath/AddressPath
        FlagsIn  : in  status_vector;
        InstrIn  : in  data_vector; -- Instruction byte from memory
        
        -- Output to the rest of the processor
        CtrlBus  : out control_bus_t
    );
end entity ControlUnit;

architecture Behavioral of ControlUnit is
begin
    -- Por ahora, la unidad de control es una caja negra que no hace nada.
    -- Simplemente emite los valores seguros de NOP/reset.
    CtrlBus <= INIT_CTRL_BUS;
end architecture Behavioral;