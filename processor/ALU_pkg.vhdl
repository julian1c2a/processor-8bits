library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Package con las constantes de opcodes de la ALU.
-- Usado tanto por los testbenches exhaustivos como por el testbench manual.
package ALU_pkg is

    -- Tipos globales del sistema
    subtype data_vector is std_logic_vector(7 downto 0);
    subtype address_vector is std_logic_vector(15 downto 0);
    subtype opcode_vector is std_logic_vector(4 downto 0);
    subtype status_vector is std_logic_vector(7 downto 0);

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

end package ALU_pkg;
