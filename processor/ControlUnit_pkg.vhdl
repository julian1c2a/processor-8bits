--------------------------------------------------------------------------------
-- Paquete: ControlUnit_pkg
-- Descripción:
--   Define los tipos de datos y registros para la Unidad de Control.
--   Contiene el registro 'control_bus_t' que agrupa TODAS las señales de control
--   físicas que van hacia el DataPath, AddressPath y Memoria.
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use work.CONSTANTS_pkg.ALL;
use work.ALU_pkg.ALL;
use work.DataPath_pkg.ALL;
use work.AddressPath_pkg.ALL;

package ControlUnit_pkg is

    -- =========================================================================
    -- Type: control_bus_t (Palabra de Control)
    -- =========================================================================
    type control_bus_t is record
        -- === DATA PATH ===
        ALU_Op      : opcode_vector;                -- Operación de la ALU
        Bus_Op      : std_logic_vector(1 downto 0); -- Selección mux escritura (ALU vs MDR)
        Write_A     : std_logic;                    -- Escribir en A (R0)
        Write_B     : std_logic;                    -- Escribir en Registro seleccionado
        Reg_Sel     : std_logic_vector(MSB_REG_SEL downto 0); -- Selección de registro (R0..R7)
        Write_F     : std_logic;                    -- Actualizar Flags
        Flag_Mask   : status_vector;                -- Máscara de flags a actualizar
        MDR_WE      : std_logic;                    -- Write Enable para MDR (captura de memoria)
        ALU_Bin_Sel : std_logic;                    -- Selección entrada B ALU: 0=Reg, 1=MDR
        Out_Sel     : std_logic_vector(1 downto 0); -- Selección dato salida a memoria (00=A, 01=B, 10=Zero)

        -- === ADDRESS PATH ===
        PC_Op       : std_logic_vector(1 downto 0); -- Control PC (Hold, Inc, Load)
        SP_Op       : std_logic_vector(1 downto 0); -- Control SP (Hold, Inc, Dec, Load)
        ABUS_Sel    : std_logic_vector(1 downto 0); -- Fuente del Bus de Direcciones (PC, SP, EAR...)
        Load_LR     : std_logic;                    -- Cargar Link Register
        Load_EAR    : std_logic;                    -- Cargar Effective Address Register
        Load_TMP_L  : std_logic;                    -- Cargar TMP bajo
        Load_TMP_H  : std_logic;                    -- Cargar TMP alto
        Load_Src_Sel: std_logic;                    -- Fuente de carga para PC/SP (0=EA_Adder, 1=TMP)
        SP_Offset   : std_logic;                    -- Offset para dirección de Stack (0=+0, 1=+1)
        EA_A_Sel    : std_logic;                    -- Selección entrada A del EA Adder (PC o TMP)
        EA_B_Sel    : std_logic;                    -- Selección entrada B del EA Adder (RegB o DataIn)

        -- === MEMORIA / IO ===
        Mem_WE      : std_logic;                    -- Write Enable Memoria
        Mem_RE      : std_logic;                    -- Read Enable Memoria
        IO_WE       : std_logic;                    -- Write Enable I/O
        IO_RE       : std_logic;                    -- Read Enable I/O
    end record;

    -- =========================================================================
    -- Constante: INIT_CTRL_BUS
    -- =========================================================================
    -- Define un estado "seguro" o NOP por defecto para todas las señales.
    -- Se usa en el reset y como base para construir microinstrucciones.
    constant INIT_CTRL_BUS : control_bus_t := (
        -- Data Path
        ALU_Op      => OP_NOP,
        Bus_Op      => ACC_ALU_elected,
        Write_A     => '0',
        Write_B     => '0',
        Reg_Sel     => (others => '0'), -- R0 por defecto
        Write_F     => '0',
        Flag_Mask   => (others => '0'),
        MDR_WE      => '0',
        ALU_Bin_Sel => '0', -- Por defecto usa operandos de registro
        Out_Sel     => "00", -- Por defecto A

        -- Address Path
        PC_Op       => PC_OP_NOP,
        SP_Op       => SP_OP_NOP,
        ABUS_Sel    => ABUS_SRC_PC, -- Por defecto fetch (PC al bus)
        Load_LR     => '0',
        Load_EAR    => '0',
        Load_TMP_L  => '0',
        Load_TMP_H  => '0',
        Load_Src_Sel=> LOAD_SRC_ALU_RES,
        SP_Offset   => '0',
        EA_A_Sel    => EA_A_SRC_TMP, -- Por defecto, EA usa TMP
        EA_B_Sel    => EA_B_SRC_REG_B, -- Por defecto, EA usa RegB

        -- Mem/IO
        Mem_WE      => '0', Mem_RE => '0',
        IO_WE       => '0', IO_RE  => '0'
    );

end package ControlUnit_pkg;

    component ControlUnit_comp is
        Port (
            clk      : in  std_logic;
            reset    : in  std_logic;
            FlagsIn  : in  status_vector;
            InstrIn  : in  data_vector;
            CtrlBus  : out control_bus_t;
            EA_A_Sel : out std_logic;
            EA_B_Sel : out std_logic
        );
    end component ControlUnit_comp;