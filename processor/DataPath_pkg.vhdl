library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.CONSTANTS_pkg.ALL;
use work.ALU_pkg.ALL; -- Necesario para status_vector

-- =========================================================================
-- Paquete: DataPath_pkg
-- Descripción:
--   Define las constantes de control del DataPath (mux de escritura y mux
--   de salida a memoria), el tipo del banco de registros y las funciones
--   auxiliares de indexación y actualización de flags.
--
--   El DataPath es el camino de datos de 8 bits que contiene:
--     - El banco de registros R0..R7 (R0=A acumulador, R1=B índice)
--     - La ALU de 8 bits
--     - El MDR (Memory Data Register) para sincronización con memoria
--     - El registro de flags F
-- =========================================================================

package DataPath_pkg is

    -- =========================================================================
    -- Constantes para Bus_Op (Selección de la fuente para el bus interno de escritura)
    -- =========================================================================
    -- Bus_Op controla el multiplexor que elige qué dato se escribe en el banco
    -- de registros al flanco de subida del reloj (cuando Write_A='1' o Write_B='1').

    -- Resultado de la ALU → bus interno de escritura.
    -- Seleccionado en instrucciones aritméticas/lógicas (ADD, SUB, AND, OP_INC, etc.)
    -- donde el resultado de la ALU se escribe directamente en A o en Reg_Sel.
    constant ACC_ALU_elected  : std_logic_vector(1 downto 0) := b"00";

    -- Dato de memoria (vía MDR) → bus interno de escritura.
    -- Seleccionado en instrucciones de carga (LD A, LD B, POP) donde el dato
    -- proviene de la memoria y ha sido latched en el MDR para estabilizarlo.
    constant MEM_MDR_elected : std_logic_vector(1 downto 0) := b"01";

    -- Byte bajo del resultado del sumador EA → bus interno de escritura.
    -- Seleccionado en instrucciones de 16 bits (ADD16, SUB16) cuando se escribe
    -- el byte bajo de la dirección efectiva calculada en un registro de 8 bits.
    -- También usado en ST SP para guardar SP[7:0] en memoria.
    constant EA_LOW_elected   : std_logic_vector(1 downto 0) := b"10"; -- Byte bajo del resultado EA

    -- Byte alto del resultado del sumador EA → bus interno de escritura.
    -- Complementario a EA_LOW_elected: escribe EA[15:8] en el registro destino.
    -- Permite descomponer un resultado de 16 bits en dos registros de 8 bits.
    constant EA_HIGH_elected  : std_logic_vector(1 downto 0) := b"11"; -- Byte alto del resultado EA

    -- =========================================================================
    -- Constantes para Out_Sel (Selección del dato que DataPath envía a MemDataOut)
    -- =========================================================================
    -- Out_Sel controla el multiplexor que elige qué dato se coloca en el bus de
    -- datos de salida hacia memoria (MemDataOut). Solo es relevante cuando Mem_WE='1'.

    -- Salida hacia memoria = R0 (Acumulador A).
    -- Usado en instrucciones ST A y en el ciclo de escritura de CALL (byte alto o bajo
    -- según el ciclo, dependiendo del SP_Offset) cuando el contenido a guardar es A.
    constant OUT_SEL_A    : std_logic_vector(2 downto 0) := b"000";

    -- Salida hacia memoria = R1 (Registro B, índice).
    -- Usado en ST B cuando se necesita guardar el contenido del registro B en memoria.
    constant OUT_SEL_B    : std_logic_vector(2 downto 0) := b"001";

    -- Salida hacia memoria = 0x00 (byte cero).
    -- Usado como padding en instrucciones PUSH de registros de 8 bits cuando se
    -- necesita completar una palabra de 16 bits en la pila (byte alto = 0x00).
    constant OUT_SEL_ZERO : std_logic_vector(2 downto 0) := b"010";

    -- Salida hacia memoria = PC[7:0] (byte bajo del Program Counter).
    -- Usado en CALL durante el ciclo de push de la dirección de retorno:
    -- guarda el byte bajo del PC en la pila para que RET pueda restaurarlo.
    constant OUT_SEL_PCL  : std_logic_vector(2 downto 0) := b"011"; -- PC Low Byte

    -- Salida hacia memoria = PC[15:8] (byte alto del Program Counter).
    -- Complementario a OUT_SEL_PCL: guarda el byte alto del PC de retorno en la pila.
    -- El orden de escritura (L antes que H o viceversa) respeta la convención Little-Endian.
    constant OUT_SEL_PCH  : std_logic_vector(2 downto 0) := b"100"; -- PC High Byte

    -- Salida hacia memoria = Registro de Flags F (status_vector de 8 bits).
    -- Usado en PUSH F para guardar el estado completo del procesador en la pila,
    -- permitiendo su restauración posterior con POP F (Load_F_Direct='1').
    constant OUT_SEL_F    : std_logic_vector(2 downto 0) := b"101"; -- Flags (Status Register)

    -- =========================================================================
    -- Definición del Banco de Registros
    -- =========================================================================
    -- Array de NUM_REGISTERS=8 registros de 8 bits, indexado de 0 a MSB_REGISTERS(=7).
    -- Índice 0 = R0 = Acumulador A (destino implícito de la mayoría de instrucciones ALU).
    -- Índice 1 = R1 = Registro B (operando B de la ALU e índice del modo indexado).
    -- Índices 2..7 = R2..R7 (registros de propósito general, acceso explícito vía Reg_Sel).
    type register_file_t is array(0 to MSB_REGISTERS) of data_vector;

    -- =========================================================================
    -- Funciones auxiliares
    -- =========================================================================

    -- Convierte un vector (std_logic_vector) a entero para indexar el banco de registros.
    -- Necesario porque register_file_t es un array de tipo integer y Reg_Sel es std_logic_vector.
    -- La conversión a unsigned intermedia garantiza interpretación sin signo del selector.
    function to_register_index(sel : std_logic_vector) return integer;

    -- Aplica la máscara de actualización de flags:
    -- Retorna (current and not mask) OR (new and mask)
    --
    -- Semántica de la máscara:
    --   - mask(i)='1': el flag i se actualiza con new_flags(i).
    --   - mask(i)='0': el flag i conserva su valor actual (current_flags(i)).
    --
    -- Ejemplo: si solo se quiere actualizar fZ y fC tras un ADD:
    --   mask = b"10010000" → actualiza bits 7(C) y 4(Z), preserva H,V,G,E,R,L.
    --
    -- Esta función permite que cada instrucción actualice solo los flags relevantes
    -- sin que la UC necesite leer-modificar-escribir el registro F explícitamente.
    function apply_flag_mask(current_flags : status_vector; new_flags : status_vector; mask : status_vector) return status_vector;

    -- =========================================================================
    -- Declaración del componente DataPath
    -- =========================================================================
    component DataPath_comp is
        Port (
            clk       : in std_logic;                              -- Reloj del sistema
            reset     : in std_logic;                              -- Reset síncrono activo alto
            MemDataIn : in  data_vector;                           -- Dato leído de memoria (bus entrada)
            MemDataOut: out data_vector;                           -- Dato a escribir en memoria (bus salida)
            IndexB_Out: out data_vector;                           -- Salida directa de R1(B) hacia AddressPath (modo indexado)
            RegA_Out  : out data_vector; -- Salida directa de A para AddressPath
                                         -- Usada en instrucciones que combinan A:B como par de 16 bits (EA_A_SRC_REG_AB)
            PC_In     : in  address_vector; -- Entrada del PC actual para guardar en stack
                                            -- La UC provee este valor durante CALL para que OUT_SEL_PCL/PCH funcionen
            ALU_Op    : in  opcode_vector;                         -- Operación ALU (ver ALU_pkg: OP_ADD, OP_SUB, etc.)
            Bus_Op    : in  std_logic_vector(1 downto 0);          -- Mux escritura: ACC_ALU / MDR / EA_LOW / EA_HIGH
            Write_A   : in  std_logic;                             -- '1' = escribir resultado en R0 (acumulador A)
            Write_B   : in  std_logic;                             -- '1' = escribir resultado en el registro Reg_Sel
            Reg_Sel   : in  std_logic_vector(MSB_REG_SEL downto 0); -- Índice del registro B fuente/destino (000..111)
            Write_F   : in  std_logic;                             -- '1' = actualizar registro de flags F
            Flag_Mask : in  status_vector;                         -- Bits en '1' indican qué flags se actualizan
            MDR_WE    : in  std_logic;                             -- '1' = capturar MemDataIn en el MDR este ciclo
            ALU_Bin_Sel : in std_logic;                            -- '0'=entrada B ALU desde Reg_Sel; '1'=desde MDR (inmediato)
            Out_Sel   : in  std_logic_vector(2 downto 0);          -- Selección del dato hacia MemDataOut
            Load_F_Direct : in std_logic;                          -- '1'=carga F directamente desde bus interno (POP F); ignora Flag_Mask
            EA_In     : in  address_vector; -- Entrada de resultado de 16 bits desde AddressPath
                                            -- Proporciona EA[15:8] y EA[7:0] para Bus_Op=EA_HIGH/EA_LOW
            EA_Flags_In : in status_vector; -- Flags generados por AddressPath
                                            -- Usados cuando F_Src_Sel='1' (instrucciones ADD16/SUB16)
            F_Src_Sel : in  std_logic;      -- Selección fuente flags: 0=ALU, 1=AddressPath
                                            -- '1' en instrucciones de 16 bits donde los flags vienen del sumador EA
            Fwd_A_En  : in  std_logic;      -- '1' = ALU usa Fwd_A_Data en lugar de RegA (bypass)
            Fwd_A_Data: in  data_vector;    -- Valor a reenviar al operando A de la ALU
            FlagsOut  : out status_vector   -- Estado actual del registro F (hacia la UC para ramificaciones)
        );
    end component DataPath_comp;

end package DataPath_pkg;

package body DataPath_pkg is

    -- Convierte sel (std_logic_vector de REG_SEL_WIDTH bits) a entero.
    -- La interpretación unsigned garantiza que "000"→0, "001"→1, ..., "111"→7.
    function to_register_index(sel : std_logic_vector) return integer is
    begin
        return to_integer(unsigned(sel));
    end function;

    -- Implementa la actualización selectiva de flags mediante máscara de bits.
    -- La expresión booleana (current AND NOT mask) OR (new AND mask) es equivalente
    -- a un multiplexor bit a bit controlado por mask: si mask(i)='1' → new(i), si no → current(i).
    function apply_flag_mask(current_flags : status_vector; new_flags : status_vector; mask : status_vector) return status_vector is
    begin
        return (current_flags and not mask) or (new_flags and mask);
    end function;

end package body DataPath_pkg;
