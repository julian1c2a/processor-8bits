library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.CONSTANTS_pkg.ALL;

-- Package con las constantes de opcodes de la ALU.
-- Usado tanto por los testbenches exhaustivos como por el testbench manual.
package ALU_pkg is

    -- Tipos globales del sistema
    subtype data_vector is std_logic_vector(MSB_DATA downto 0);
    subtype address_vector is std_logic_vector(MSB_ADDRESS downto 0);
    subtype opcode_vector is std_logic_vector(MSB_OPCODE downto 0);
    subtype status_vector is std_logic_vector(MSB_STATUS downto 0);
    subtype nibble_data is std_logic_vector(MSB_NIBBLE downto 0);

    subtype unsigned_data_vector is unsigned(MSB_DATA downto 0);
    subtype unsigned_address_vector is unsigned(MSB_ADDRESS downto 0);
    subtype unsigned_nibble is unsigned(MSB_NIBBLE downto 0);

    subtype signed_extended_data_vector is signed(MSB_EXTENDED_DATA downto 0);
    subtype unsigned_extended_nibble is unsigned(MSB_EXTENDED_NIBBLE downto 0);

    -- Tipos para resultados de doble ancho (Multiplicación 16 bits)
    subtype double_data_vector is std_logic_vector(MSB_DOUBLE_DATA downto 0);
    subtype unsigned_double_data_vector is unsigned(MSB_DOUBLE_DATA downto 0);
    subtype unsigned_double_data_vector_H is unsigned(MSB_DOUBLE_DATA downto DATA_WIDTH);
    subtype unsigned_double_data_vector_L is unsigned(MSB_DATA downto 0);

    -- Tipo de retorno para funciones de la ALU: par (Valor, Flags)
    type alu_result_record is record
        acc    : data_vector;
        status : status_vector;
    end record;

    constant OP_NOP  : opcode_vector := b"00000"; -- No Operation
    constant OP_ADD  : opcode_vector := b"00001"; -- ADD
    constant OP_ADC  : opcode_vector := b"00010"; -- ADD with Carry
    constant OP_SUB  : opcode_vector := b"00011"; -- SUBtract
    constant OP_SBB  : opcode_vector := b"00100"; -- SUBtract with Borrow
    constant OP_LSL  : opcode_vector := b"00101"; -- Logical Shift Left
    constant OP_LSR  : opcode_vector := b"00110"; -- Logical Shift Right
    constant OP_ROL  : opcode_vector := b"00111"; -- Rotate Left
    constant OP_ROR  : opcode_vector := b"01000"; -- Rotate Right
    constant OP_INC  : opcode_vector := b"01001"; -- Increment A
    constant OP_DEC  : opcode_vector := b"01010"; -- Decrement A
    constant OP_AND  : opcode_vector := b"01011"; -- AND
    constant OP_IOR  : opcode_vector := b"01100"; -- OR (Inclusive OR)
    constant OP_XOR  : opcode_vector := b"01101"; -- XOR
    constant OP_NOT  : opcode_vector := b"01110"; -- NOT A
    constant OP_ASL  : opcode_vector := b"01111"; -- Arithmetic Shift Left
    constant OP_NEG  : opcode_vector := b"10000"; -- NEG A (two's complement)
    constant OP_PSA  : opcode_vector := b"10001"; -- Pass A
    constant OP_PSB  : opcode_vector := b"10010"; -- Pass B
    constant OP_CLR  : opcode_vector := b"10011"; -- Clear ACC
    constant OP_SET  : opcode_vector := b"10100"; -- Set ACC
    constant OP_MUL  : opcode_vector := b"10101"; -- Multiply Low
    constant OP_MUH  : opcode_vector := b"10110"; -- Multiply High
    constant OP_CMP  : opcode_vector := b"10111"; -- Compare
    constant OP_ASR  : opcode_vector := b"11000"; -- Arithmetic Shift Right
    constant OP_SWP  : opcode_vector := b"11001"; -- Swap Nibbles
    constant OP_INB  : opcode_vector := b"11010"; -- Increment B (result → ACC)
    constant OP_DEB  : opcode_vector := b"11011"; -- Decrement B (result → ACC)
    -- Reservados: 11100, 11101, 11110, 11111

    -- Declaración centralizada del componente
    component ALU_comp is
        Port (
            RegInA    : in  data_vector;
            RegInB    : in  data_vector;
            Oper      : in  opcode_vector;
            Carry_in  : in  STD_LOGIC := '0';
            RegOutACC : out data_vector;
            RegStatus : out status_vector
        );
    end component ALU_comp;

end package ALU_pkg;
