--------------------------------------------------------------------------------
-- Archivo: CONSTANTS_pkg.vhdl
-- Descripción:
--   Define las constantes globales de dimensionamiento y arquitectura del sistema.
--   Centraliza los anchos de bus y parámetros fundamentales para facilitar
--   la escalabilidad y el mantenimiento.
--
--   Modificar aquí una constante base (p.ej. DATA_WIDTH) propagará el cambio
--   automáticamente a todos los tipos, subtypes y componentes que dependen de ella.
--
-- Dependencias: Utils_pkg (para funciones matemáticas como ceil_log2)
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use work.Utils_pkg.ALL;

package CONSTANTS_pkg is

    -- =========================================================================
    -- Constantes de dimensionamiento del sistema (Base)
    -- =========================================================================

    -- Ancho del bus de datos principal: 8 bits.
    -- Determina el tamaño de todos los registros de propósito general (R0..R7),
    -- el acumulador (A=R0), el registro índice (B=R1) y el bus de datos de memoria.
    constant DATA_WIDTH    : integer := 8;

    -- Ancho del bus de direcciones: 16 bits.
    -- Define el espacio de direccionamiento total del procesador: 2^16 = 65 536 bytes (64 KB).
    -- Abarca la RAM de usuario, la BRAM de instrucciones y los vectores de interrupción
    -- situados en los últimos bytes del mapa (0xFFFA..0xFFFF).
    constant ADDRESS_WIDTH : integer := 16;

    -- Ancho del campo opcode de la ALU: 5 bits.
    -- Permite codificar hasta 2^5 = 32 operaciones distintas en la ALU interna.
    -- Los opcodes van de OP_NOP (00000) hasta el último reservado (11111).
    constant OPCODE_WIDTH  : integer := 5;

    -- Ancho del registro de estado (flags): 8 bits.
    -- Los 8 flags son: C (Carry), H (Half-Carry), V (Overflow), Z (Zero),
    --                  G (Greater-signed), E (Equal), R (Shift-right bit), L (Shift-left bit).
    -- Mapear cada flag a un bit del byte de estado facilita las instrucciones PUSH F / POP F.
    constant STATUS_WIDTH  : integer := 8;

    -- Ancho de un nibble (medio byte): 4 bits.
    -- Derivado de DATA_WIDTH/2. Se usa en el cálculo del Half-Carry (fH),
    -- que detecta el acarreo entre el nibble bajo (bits 3..0) y el nibble alto (bits 7..4).
    -- Relevante para aritmética BCD (Binary-Coded Decimal).
    constant NIBBLE_WIDTH  : integer := DATA_WIDTH / 2;

    -- Ancho del resultado de multiplicación (doble precisión): 16 bits.
    -- El producto de dos operandos de 8 bits puede generar hasta 16 bits de resultado.
    -- OP_MUL retorna el byte bajo [7:0] y OP_MUH retorna el byte alto [15:8].
    constant DOUBLE_DATA_WIDTH : integer := DATA_WIDTH * 2;

    -- Ancho de la suma extendida con carry: 9 bits.
    -- Al sumar dos valores de 8 bits se genera un resultado de 9 bits (DATA_WIDTH+1).
    -- El bit extra (bit 8) es el carry de salida, esencial para detectar desbordamiento
    -- sin signo y para encadenar sumas de precisión múltiple.
    constant EXTENDED_DATA_WIDTH : integer := DATA_WIDTH + 1;

    -- Ancho del nibble extendido con carry: 5 bits.
    -- Equivalente a EXTENDED_DATA_WIDTH pero para la mitad inferior del dato (4+1 bits).
    -- Se usa internamente para calcular el Half-Carry (fH) al sumar los nibbles bajos.
    constant EXTENDED_NIBBLE_WIDTH : integer := NIBBLE_WIDTH + 1;

    -- Número de registros de propósito general en el DataPath (incluyendo A y B).
    -- R0=A (acumulador), R1=B (índice/operando B), R2..R7 (propósito general).
    -- Este valor determina el tamaño del banco de registros (register_file_t).
    constant NUM_REGISTERS : integer := 8;

    -- =========================================================================
    -- Constantes derivadas para rangos VHDL (índice más significativo, MSB)
    -- =========================================================================
    -- Estas constantes se usan en declaraciones "downto 0" para definir rangos
    -- de vectores de forma legible y consistente con los anchos base.
    -- Ejemplo: std_logic_vector(MSB_DATA downto 0) ≡ std_logic_vector(7 downto 0).

    -- Índice más alto del bus de datos (7): usado en rangos data_vector(7 downto 0).
    constant MSB_DATA      : integer := DATA_WIDTH - 1;

    -- Índice más alto del bus de direcciones (15): usado en address_vector(15 downto 0).
    constant MSB_ADDRESS   : integer := ADDRESS_WIDTH - 1;

    -- Índice más alto del campo opcode (4): usado en opcode_vector(4 downto 0).
    constant MSB_OPCODE    : integer := OPCODE_WIDTH - 1;

    -- Índice más alto del registro de estado (7): usado en status_vector(7 downto 0).
    constant MSB_STATUS    : integer := STATUS_WIDTH - 1;

    -- Índice más alto de un nibble (3): usado en nibble_data(3 downto 0).
    constant MSB_NIBBLE    : integer := NIBBLE_WIDTH - 1;

    -- Índice más alto del resultado de doble precisión (15): para double_data_vector(15 downto 0).
    constant MSB_DOUBLE_DATA : integer := DOUBLE_DATA_WIDTH - 1;

    -- Índice más alto del resultado extendido de 9 bits (8): bit de carry de suma completa.
    constant MSB_EXTENDED_DATA : integer := EXTENDED_DATA_WIDTH - 1;

    -- Índice más alto del nibble extendido de 5 bits (4): bit de half-carry de suma de nibbles.
    constant MSB_EXTENDED_NIBBLE : integer := EXTENDED_NIBBLE_WIDTH - 1;

    -- Índice más alto del banco de registros (7): el banco es un array de 0 a 7.
    constant MSB_REGISTERS : integer := NUM_REGISTERS - 1;

    -- =========================================================================
    -- Constantes derivadas para selección de registros (Log2)
    -- =========================================================================

    -- Número de bits necesarios para seleccionar un registro del banco: ceil_log2(8) = 3.
    -- Con 3 bits se pueden direccionar hasta 8 registros (000=R0 .. 111=R7).
    -- Se calcula dinámicamente para que escale si NUM_REGISTERS cambia.
    constant REG_SEL_WIDTH : integer := ceil_log2(NUM_REGISTERS);

    -- Índice más alto del selector de registro (2): para Reg_Sel(2 downto 0).
    -- El selector de 3 bits cubre los 8 registros: 000..111.
    constant MSB_REG_SEL   : integer := REG_SEL_WIDTH - 1;

end package CONSTANTS_pkg;
