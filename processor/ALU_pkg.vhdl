library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Package con las constantes de opcodes de la ALU.
-- Usado tanto por los testbenches exhaustivos como por el testbench manual.
package ALU_pkg is

    constant OP_NOP  : STD_LOGIC_VECTOR(4 downto 0) := b"00000"; -- No Operation
    constant OP_ADD  : STD_LOGIC_VECTOR(4 downto 0) := b"00001"; -- ADD
    constant OP_ADC  : STD_LOGIC_VECTOR(4 downto 0) := b"00010"; -- ADD with Carry
    constant OP_SUB  : STD_LOGIC_VECTOR(4 downto 0) := b"00011"; -- SUBtract
    constant OP_SBB  : STD_LOGIC_VECTOR(4 downto 0) := b"00100"; -- SUBtract with Borrow
    constant OP_LSL  : STD_LOGIC_VECTOR(4 downto 0) := b"00101"; -- Logical Shift Left
    constant OP_LSR  : STD_LOGIC_VECTOR(4 downto 0) := b"00110"; -- Logical Shift Right
    constant OP_ROL  : STD_LOGIC_VECTOR(4 downto 0) := b"00111"; -- Rotate Left
    constant OP_ROR  : STD_LOGIC_VECTOR(4 downto 0) := b"01000"; -- Rotate Right
    constant OP_INC  : STD_LOGIC_VECTOR(4 downto 0) := b"01001"; -- Increment
    constant OP_DEC  : STD_LOGIC_VECTOR(4 downto 0) := b"01010"; -- Decrement
    constant OP_AND  : STD_LOGIC_VECTOR(4 downto 0) := b"01011"; -- AND
    constant OP_OR   : STD_LOGIC_VECTOR(4 downto 0) := b"01100"; -- OR
    constant OP_XOR  : STD_LOGIC_VECTOR(4 downto 0) := b"01101"; -- XOR
    constant OP_NOT  : STD_LOGIC_VECTOR(4 downto 0) := b"01110"; -- NOT
    constant OP_ASL  : STD_LOGIC_VECTOR(4 downto 0) := b"01111"; -- Arithmetic Shift Left
    constant OP_PA   : STD_LOGIC_VECTOR(4 downto 0) := b"10001"; -- Pass A
    constant OP_PB   : STD_LOGIC_VECTOR(4 downto 0) := b"10010"; -- Pass B
    constant OP_CL   : STD_LOGIC_VECTOR(4 downto 0) := b"10011"; -- Clear ACC
    constant OP_SET  : STD_LOGIC_VECTOR(4 downto 0) := b"10100"; -- Set ACC
    constant OP_MUL  : STD_LOGIC_VECTOR(4 downto 0) := b"10101"; -- Multiply Low
    constant OP_MUH  : STD_LOGIC_VECTOR(4 downto 0) := b"10110"; -- Multiply High
    constant OP_CMP  : STD_LOGIC_VECTOR(4 downto 0) := b"10111"; -- Compare
    constant OP_ASR  : STD_LOGIC_VECTOR(4 downto 0) := b"11000"; -- Arithmetic Shift Right
    constant OP_SWAP : STD_LOGIC_VECTOR(4 downto 0) := b"11001"; -- Swap Nibbles

end package ALU_pkg;
