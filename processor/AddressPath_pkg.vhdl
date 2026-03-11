library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use work.CONSTANTS_pkg.ALL;

package AddressPath_pkg is

    -- Seleccion de operacion para el PC
    constant PC_OP_NOP  : std_logic_vector(1 downto 0) := "00"; -- Hold
    constant PC_OP_INC  : std_logic_vector(1 downto 0) := "01"; -- PC + 1
    constant PC_OP_LOAD : std_logic_vector(1 downto 0) := "10"; -- Cargar valor (saltos)
    -- "11" Reservado

    -- Seleccion de operacion para el SP (Stack Pointer)
    -- El SP siempre se mueve de 2 en 2 segun la ISA (alineado a par)
    constant SP_OP_NOP  : std_logic_vector(1 downto 0) := "00"; -- Hold
    constant SP_OP_INC  : std_logic_vector(1 downto 0) := "01"; -- SP + 2 (POP)
    constant SP_OP_DEC  : std_logic_vector(1 downto 0) := "10"; -- SP - 2 (PUSH)
    constant SP_OP_LOAD : std_logic_vector(1 downto 0) := "11"; -- Cargar valor

    -- Seleccion de la fuente para el Bus de Direcciones (ABUS)
    constant ABUS_SRC_PC  : std_logic_vector(1 downto 0) := "00"; -- Fetch instrucciones
    constant ABUS_SRC_SP  : std_logic_vector(1 downto 0) := "01"; -- Stack Ops
    constant ABUS_SRC_EAR : std_logic_vector(1 downto 0) := "10"; -- Effective Address (LD/ST)
    constant ABUS_SRC_LR  : std_logic_vector(1 downto 0) := "11"; -- Link Register (no suele ir directo al bus, pero util)

    -- Seleccion de la fuente para cargar datos en registros internos (PC, LR, EAR)
    -- Usualmente viene de: Resultado del EA-Adder, Bus de Datos (concatenado), o Registros internos
    constant LOAD_SRC_ALU_RES : std_logic := '0'; -- Resultado calculado (saltos relativos, EA)
    constant LOAD_SRC_DATA_IN : std_logic := '1'; -- Dato directo (LD SP, #nnnn)

    -- Componente
    component AddressPath_comp is
        Port (
            clk       : in std_logic;
            reset     : in std_logic;
            DataIn    : in  data_vector;
            Index_B   : in  data_vector;
            AddressBus : out address_vector;
            PC_Op     : in  std_logic_vector(1 downto 0);
            SP_Op     : in  std_logic_vector(1 downto 0);
            ABUS_Sel  : in  std_logic_vector(1 downto 0);
            Load_LR   : in  std_logic;
            Load_EAR  : in  std_logic;
            Load_TMP_L: in  std_logic;
            Load_TMP_H: in  std_logic;
            Load_Src_Sel : in std_logic
        );
    end component AddressPath_comp;

end package AddressPath_pkg;