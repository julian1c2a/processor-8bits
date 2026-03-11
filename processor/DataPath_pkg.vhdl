library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.CONSTANTS_pkg.ALL;
use work.ALU_pkg.ALL; -- Necesario para status_vector

package DataPath_pkg is

    -- Constantes para Bus_Op (Selección de la fuente para el bus de escritura)
    constant ACC_ALU_elected  : std_logic_vector(1 downto 0) := b"00";
    constant MEM_MDR_elected : std_logic_vector(1 downto 0) := b"01";
    constant EA_LOW_elected   : std_logic_vector(1 downto 0) := b"10"; -- Byte bajo del resultado EA
    constant EA_HIGH_elected  : std_logic_vector(1 downto 0) := b"11"; -- Byte alto del resultado EA

    -- Constantes para Out_Sel (Selección de dato a Memoria)
    constant OUT_SEL_A    : std_logic_vector(2 downto 0) := b"000";
    constant OUT_SEL_B    : std_logic_vector(2 downto 0) := b"001";
    constant OUT_SEL_ZERO : std_logic_vector(2 downto 0) := b"010";
    constant OUT_SEL_PCL  : std_logic_vector(2 downto 0) := b"011"; -- PC Low Byte
    constant OUT_SEL_PCH  : std_logic_vector(2 downto 0) := b"100"; -- PC High Byte
    constant OUT_SEL_F    : std_logic_vector(2 downto 0) := b"101"; -- Flags (Status Register)

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
            RegA_Out  : out data_vector; -- Salida directa de A para AddressPath
            PC_In     : in  address_vector; -- Entrada del PC actual para guardar en stack
            ALU_Op    : in  opcode_vector;
            Bus_Op    : in  std_logic_vector(1 downto 0);
            Write_A   : in  std_logic;
            Write_B   : in  std_logic;
            Reg_Sel   : in  std_logic_vector(MSB_REG_SEL downto 0);
            Write_F   : in  std_logic;
            Flag_Mask : in  status_vector;
            MDR_WE    : in  std_logic;
            ALU_Bin_Sel : in std_logic;
            Out_Sel   : in  std_logic_vector(2 downto 0);
            Load_F_Direct : in std_logic;
            EA_In     : in  address_vector; -- Entrada de resultado de 16 bits desde AddressPath
            EA_Flags_In : in status_vector; -- Flags generados por AddressPath
            F_Src_Sel : in  std_logic;      -- Selección fuente flags: 0=ALU, 1=AddressPath
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