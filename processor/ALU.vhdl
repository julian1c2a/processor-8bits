library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity ALU is
    Port (
        RegInA    : in  STD_LOGIC_VECTOR(7 downto 0);
        RegInB    : in  STD_LOGIC_VECTOR(7 downto 0);
        Oper      : in  STD_LOGIC_VECTOR(4 downto 0);
        Carry_in  : in  STD_LOGIC := '0'; -- Entrada de carry para ADC y SBB
        RegOutACC : out STD_LOGIC_VECTOR(7 downto 0);
        RegStatus : out STD_LOGIC_VECTOR(7 downto 0)
    );
end entity ALU;

architecture unique of ALU is

    -- Los alias facilitan la lectura del código para los flags
    alias fC is RegStatus(7); -- Carry/Borrow
    alias fH is RegStatus(6); -- HalfCarry/HalfBorrow
    alias fV is RegStatus(5); -- Overflow
    alias fZ is RegStatus(4); -- Zero
    alias fG is RegStatus(3); -- A greater than B
    alias fE is RegStatus(2); -- A equal B
    alias fR is RegStatus(1); -- LSR: ACC(0)
    alias fL is RegStatus(0); -- LSL: ACC(7)

begin

    -- Toda la lógica de la ALU se encapsula en un solo proceso combinacional.
    -- Se recalcula cada vez que una de las entradas (RegInA, RegInB, Oper, Carry_in) cambia.
    alu_process: process(RegInA, RegInB, Oper, Carry_in)
        -- Variables para cálculos intermedios. Se usan solo dentro del proceso.
        variable acc_ext       : signed(8 downto 0);
        variable nibbleA_ext   : unsigned(4 downto 0);
        variable nibbleB_ext   : unsigned(4 downto 0);
        variable nibble_res    : unsigned(4 downto 0);
        variable mul_res       : unsigned(15 downto 0);
        variable cmp_res       : signed(8 downto 0);
        variable is_cmp_op     : boolean;
        variable v_RegStatus   : STD_LOGIC_VECTOR(7 downto 0);

    begin
        -- 1. Inicialización por defecto de las salidas en cada ejecución
        v_RegStatus := (others => '0');
        acc_ext     := (others => '0');
        is_cmp_op   := false;

        -- 2. Preparación de operandos para cálculos de 4 y 8 bits
        -- Extendemos los nibbles bajos a 5 bits para detectar el HalfCarry
        nibbleA_ext := resize(unsigned(RegInA(3 downto 0)), 5);
        nibbleB_ext := resize(unsigned(RegInB(3 downto 0)), 5);

        -- 3. Lógica principal de la ALU basada en el código de operación
        case Oper is
            when b"00000" => -- NOP (No Operation)
                -- The ACC will output 0x00 by default. A true NOP would be handled
                -- by the CPU control unit by not clocking the result.
                null;

            when b"00001" => -- ADD
                -- Half-Carry (H): Suma de 4 bits, el acarreo es el bit 4 del resultado de 5 bits.
                nibble_res := nibbleA_ext + nibbleB_ext;
                v_RegStatus(6) := nibble_res(4); -- fH

                -- Suma principal de 8 bits. Extendemos a 9 bits para capturar el Carry.
                acc_ext := signed(resize(unsigned(RegInA), 9) + resize(unsigned(RegInB), 9));
                v_RegStatus(7) := acc_ext(8); -- fC

                -- Overflow (V): si los signos de los operandos son iguales y el del resultado es diferente.
                if RegInA(7) = RegInB(7) and acc_ext(7) /= RegInA(7) then
                    v_RegStatus(5) := '1'; -- fV
                end if;

            when b"00010" => -- ADC (ADD with Carry)
                nibble_res := nibbleA_ext + nibbleB_ext + unsigned'('0' & Carry_in);
                v_RegStatus(6) := nibble_res(4); -- fH

                acc_ext := signed(resize(unsigned(RegInA), 9) + resize(unsigned(RegInB), 9) + resize(unsigned'('0' & Carry_in),9));
                v_RegStatus(7) := acc_ext(8); -- fC

                if RegInA(7) = RegInB(7) and acc_ext(7) /= RegInA(7) then
                    v_RegStatus(5) := '1'; -- fV
                end if;

            when b"00011" => -- SUB
                -- Half-Borrow (H): Es un préstamo, que es lo contrario a un acarreo en la resta.
                nibble_res := nibbleA_ext - nibbleB_ext;
                v_RegStatus(6) := not nibble_res(4); -- fH (Borrow)

                -- Resta principal. El bit de acarreo (acc_ext(8)) es el Borrow.
                acc_ext := resize(signed(RegInA), 9) - resize(signed(RegInB), 9);
                v_RegStatus(7) := not acc_ext(8); -- fC (Borrow)

                -- Overflow (V): si los signos de los operandos son diferentes y el del resultado es igual al de B.
                if RegInA(7) /= RegInB(7) and acc_ext(7) = RegInB(7) then
                    v_RegStatus(5) := '1'; -- fV
                end if;

            when b"00100" => -- SBB (SUBtract with Borrow)
                nibble_res := nibbleA_ext - nibbleB_ext - unsigned'('0' & Carry_in);
                v_RegStatus(6) := not nibble_res(4); -- fH (Borrow)

                acc_ext := resize(signed(RegInA), 9) - resize(signed(RegInB), 9) - signed'("0" & Carry_in);
                v_RegStatus(7) := not acc_ext(8); -- fC (Borrow)

                if RegInA(7) /= RegInB(7) and acc_ext(7) = RegInB(7) then
                    v_RegStatus(5) := '1'; -- fV
                end if;

            when b"00101" => -- LSL (Logical Shift Left)
                acc_ext(7 downto 0) := signed(RegInA(6 downto 0) & '0');
                v_RegStatus(0) := RegInA(7); -- fL

            when b"00110" => -- LSR (Logical Shift Right)
                acc_ext(7 downto 0) := signed('0' & RegInA(7 downto 1));
                v_RegStatus(1) := RegInA(0); -- fR

            when b"00111" => -- ROL (Rotate Left)
                acc_ext(7 downto 0) := signed(RegInA(6 downto 0) & RegInA(7));

            when b"01000" => -- ROR (Rotate Right)
                acc_ext(7 downto 0) := signed(RegInA(0) & RegInA(7 downto 1));

            when b"01001" => -- INC (Increment)
                -- Half-Carry
                nibble_res := nibbleA_ext + 1;
                v_RegStatus(6) := nibble_res(4); -- fH

                -- Main operation
                acc_ext := resize(signed(RegInA), 9) + 1;
                v_RegStatus(7) := acc_ext(8); -- fC

                -- Overflow (V)
                if RegInA = "01111111" then -- 127 + 1 = 128 (overflow for signed 8-bit)
                    v_RegStatus(5) := '1'; -- fV
                end if;

            when b"01010" => -- DEC (Decrement)
                -- Half-Borrow
                nibble_res := nibbleA_ext - 1;
                v_RegStatus(6) := not nibble_res(4); -- fH

                -- Main operation
                acc_ext := resize(signed(RegInA), 9) - 1;
                v_RegStatus(7) := not acc_ext(8); -- fC

                -- Overflow (V)
                if RegInA = "10000000" then -- -128 - 1 = -129 (overflow for signed 8-bit)
                    v_RegStatus(5) := '1'; -- fV
                end if;

            when b"01011" => -- AND
                acc_ext(7 downto 0) := signed(RegInA and RegInB);

            when b"01100" => -- OR
                acc_ext(7 downto 0) := signed(RegInA or RegInB);

            when b"01101" => -- XOR
                acc_ext(7 downto 0) := signed(RegInA xor RegInB);

            when b"01110" => -- NOT
                acc_ext(7 downto 0) := signed(not RegInA);

            when b"10001" => -- PA (Pass A)
                acc_ext(7 downto 0) := signed(RegInA);

            when b"10010" => -- PB (Pass B)
                acc_ext(7 downto 0) := signed(RegInB);

            when b"10011" => -- CL (Clear ACC)
                acc_ext(7 downto 0) := (others => '0');

            when b"10100" => -- SET (Set ACC)
                acc_ext(7 downto 0) := (others => '1');

            when b"10101" => -- MUL (Multiply Low)
                mul_res := unsigned(RegInA) * unsigned(RegInB);
                acc_ext(7 downto 0) := signed(mul_res(7 downto 0));
                if mul_res(15 downto 8) /= x"00" then
                    v_RegStatus(7) := '1'; -- fC
                end if;

            when b"10110" => -- MUH (Multiply High)
                mul_res := unsigned(RegInA) * unsigned(RegInB);
                acc_ext(7 downto 0) := signed(mul_res(15 downto 8));
                if mul_res(15 downto 8) /= x"00" then
                    v_RegStatus(7) := '1'; -- fC
                end if;

            when b"10111" => -- CMP (Compare)
                is_cmp_op := true; -- Prevent common Z flag logic from running

                -- Half-Borrow (H)
                nibble_res := nibbleA_ext - nibbleB_ext;
                v_RegStatus(6) := not nibble_res(4); -- fH

                -- Main subtraction for flags
                cmp_res := resize(signed(RegInA), 9) - resize(signed(RegInB), 9);
                
                -- Set flags based on CMP result
                v_RegStatus(7) := not cmp_res(8); -- fC (Borrow)

                if RegInA(7) /= RegInB(7) and cmp_res(7) = RegInB(7) then
                    v_RegStatus(5) := '1'; -- fV (Overflow)
                end if;

                if cmp_res(7 downto 0) = x"00" then
                    v_RegStatus(4) := '1'; -- fZ (Zero)
                end if;
                
                -- ACC is not modified, will output the default 0x00.

            when b"11000" => -- ASR (Arithmetic Shift Right)
                acc_ext(7 downto 0) := signed(RegInA(7) & RegInA(7 downto 1));
                v_RegStatus(1) := RegInA(0); -- fR, store shifted-out bit

            when b"11001" => -- SWAP (Swap Nibbles)
                acc_ext(7 downto 0) := signed(RegInA(3 downto 0) & RegInA(7 downto 4));

            when others => -- Comportamiento por defecto si la operación no está implementada
                acc_ext := (others => '0');

        end case;

        -- 4. Asignación de flags comunes y la salida principal
        RegOutACC <= std_logic_vector(acc_ext(7 downto 0));

        -- Flag Zero (Z): si el resultado de 8 bits es cero.
        if not is_cmp_op and acc_ext(7 downto 0) = x"00" then
            v_RegStatus(4) := '1'; -- fZ
        end if;
        
        -- Flag Greater Than (G)
        if signed(RegInA) > signed(RegInB) then
            v_RegStatus(3) := '1'; -- fG
        end if;
        
        -- Flag Equal (E)
        if RegInA = RegInB then
            v_RegStatus(2) := '1'; -- fE
        end if;

        -- Asignación final al registro de estado de salida
        RegStatus <= v_RegStatus;

    end process alu_process;

end architecture unique;
