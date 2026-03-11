library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use work.Utils_pkg.ALL;

package CONSTANTS_pkg is

    -- Constantes de dimensionamiento del sistema (Base)
    constant DATA_WIDTH    : integer := 8;
    constant ADDRESS_WIDTH : integer := 16;
    constant OPCODE_WIDTH  : integer := 5;
    constant STATUS_WIDTH  : integer := 8;
    constant NIBBLE_WIDTH  : integer := DATA_WIDTH / 2;
    constant DOUBLE_DATA_WIDTH : integer := DATA_WIDTH * 2;
    constant EXTENDED_DATA_WIDTH : integer := DATA_WIDTH + 1;
    constant EXTENDED_NIBBLE_WIDTH : integer := NIBBLE_WIDTH + 1;
    constant NUM_REGISTERS : integer := 8;

    -- Constantes derivadas para rangos (MSB)
    constant MSB_DATA      : integer := DATA_WIDTH - 1;
    constant MSB_ADDRESS   : integer := ADDRESS_WIDTH - 1;
    constant MSB_OPCODE    : integer := OPCODE_WIDTH - 1;
    constant MSB_STATUS    : integer := STATUS_WIDTH - 1;
    constant MSB_NIBBLE    : integer := NIBBLE_WIDTH - 1;
    constant MSB_DOUBLE_DATA : integer := DOUBLE_DATA_WIDTH - 1;
    constant MSB_EXTENDED_DATA : integer := EXTENDED_DATA_WIDTH - 1;
    constant MSB_EXTENDED_NIBBLE : integer := EXTENDED_NIBBLE_WIDTH - 1;
    constant MSB_REGISTERS : integer := NUM_REGISTERS - 1;

    -- Constantes derivadas para selección de registros (Log2)
    constant REG_SEL_WIDTH : integer := ceil_log2(NUM_REGISTERS);
    constant MSB_REG_SEL   : integer := REG_SEL_WIDTH - 1;

end package CONSTANTS_pkg;