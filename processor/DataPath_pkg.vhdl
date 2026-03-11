library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.CONSTANTS_pkg.ALL;
use work.ALU_pkg.ALL; -- Necesario para status_vector

package DataPath_pkg is

    -- Constantes para Bus_Op (Selección de la fuente para el bus de escritura)
    constant ACC_ALU_elected  : std_logic_vector(1 downto 0) := b"00";
    constant MEM_MDR_elected : std_logic_vector(1 downto 0) := b"01";

    -- Constantes para Out_Sel (Selección de dato a Memoria)
    constant OUT_SEL_A    : std_logic_vector(1 downto 0) := b"00";
    constant OUT_SEL_B    : std_logic_vector(1 downto 0) := b"01";
    constant OUT_SEL_ZERO : std_logic_vector(1 downto 0) := b"10";

    -- Definición del Banco de Registros
    type register_file_t is array(0 to MSB_REGISTERS) of data_vector;

    -- Convierte un vector (std_logic_vector) a entero para indexar el banco de registros
    function to_register_index(sel : std_logic_vector) return integer;

    -- Aplica la máscara de actualización de flags:
    -- Retorna (current and not mask) OR (new and mask)
    function apply_flag_mask(current_flags : status_vector; new_flags : status_vector; mask : status_vector) return status_vector;

    -- Componente
    component DataPath_comp is
        Port (
            clk       : in std_logic;
            reset     : in std_logic;
            MemDataIn : in  data_vector;
            MemDataOut: out data_vector;
            IndexB_Out: out data_vector;
            ALU_Op    : in  opcode_vector;
            Bus_Op    : in  std_logic_vector(1 downto 0);
            Write_A   : in  std_logic;
            Write_B   : in  std_logic;
            Reg_Sel   : in  std_logic_vector(MSB_REG_SEL downto 0);
            Write_F   : in  std_logic;
            Flag_Mask : in  status_vector;
            MDR_WE    : in  std_logic;
            ALU_Bin_Sel : in std_logic;
            Out_Sel   : in  std_logic_vector(1 downto 0);
            FlagsOut  : out status_vector
        );
    end component DataPath_comp;

end package DataPath_pkg;

package body DataPath_pkg is

    function to_register_index(sel : std_logic_vector) return integer is
    begin
        return to_integer(unsigned(sel));
    end function;

    function apply_flag_mask(current_flags : status_vector; new_flags : status_vector; mask : status_vector) return status_vector is
    begin
        return (current_flags and not mask) or (new_flags and mask);
    end function;

end package body DataPath_pkg;