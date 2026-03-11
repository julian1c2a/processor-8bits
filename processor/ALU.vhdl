library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.ALU_pkg.ALL;

entity ALU is
    Port (
        RegInA    : in  data_vector;
        RegInB    : in  data_vector;
        Oper      : in  opcode_vector;
        Carry_in  : in  STD_LOGIC := '0'; -- Entrada de carry para ADC y SBB
        RegOutACC : out data_vector;
        RegStatus : out status_vector
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
        variable v_RegStatus   : status_vector;

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
            when OP_NOP => -- NOP (No Operation)
                -- The ACC will output 0x00 by default. A true NOP would be handled
                -- by the CPU control unit by not clocking the result.
                null;

            when OP_ADD => -- ADD
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

            when OP_ADC => -- ADC (ADD with Carry)
                nibble_res := nibbleA_ext + nibbleB_ext + unsigned'('0' & Carry_in);
                v_RegStatus(6) := nibble_res(4); -- fH

                acc_ext := signed(resize(unsigned(RegInA), 9) + resize(unsigned(RegInB), 9) + resize(unsigned'('0' & Carry_in),9));
                v_RegStatus(7) := acc_ext(8); -- fC

                if RegInA(7) = RegInB(7) and acc_ext(7) /= RegInA(7) then
                    v_RegStatus(5) := '1'; -- fV
                end if;

            when OP_SUB => -- SUB
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

            when OP_SBB => -- SBB (SUBtract with Borrow)
                nibble_res := nibbleA_ext - nibbleB_ext - unsigned'('0' & Carry_in);
                v_RegStatus(6) := not nibble_res(4); -- fH (Borrow)

                acc_ext := resize(signed(RegInA), 9) - resize(signed(RegInB), 9) - signed'("0" & Carry_in);
                v_RegStatus(7) := not acc_ext(8); -- fC (Borrow)

                if RegInA(7) /= RegInB(7) and acc_ext(7) = RegInB(7) then
                    v_RegStatus(5) := '1'; -- fV
                end if;

            when OP_LSL => -- LSL (Logical Shift Left)
                acc_ext(7 downto 0) := signed(RegInA(6 downto 0) & '0');
                v_RegStatus(0) := RegInA(7); -- fL

            when OP_LSR => -- LSR (Logical Shift Right)
                acc_ext(7 downto 0) := signed('0' & RegInA(7 downto 1));
                v_RegStatus(1) := RegInA(0); -- fR

            when OP_ROL => -- ROL (Rotate Left)
                acc_ext(7 downto 0) := signed(RegInA(6 downto 0) & RegInA(7));

            when OP_ROR => -- ROR (Rotate Right)
                acc_ext(7 downto 0) := signed(RegInA(0) & RegInA(7 downto 1));

            when OP_INC => -- INC (Increment)
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

            when OP_DEC => -- DEC (Decrement)
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

            when OP_AND => -- AND
                acc_ext(7 downto 0) := signed(RegInA and RegInB);

            when OP_IOR => -- OR
                acc_ext(7 downto 0) := signed(RegInA or RegInB);

            when OP_XOR => -- XOR
                acc_ext(7 downto 0) := signed(RegInA xor RegInB);

            when OP_NOT => -- NOT
                acc_ext(7 downto 0) := signed(not RegInA);

            when OP_ASL => -- ASL (Arithmetic Shift Left)
                acc_ext(7 downto 0) := signed(RegInA(6 downto 0) & '0');
                v_RegStatus(0) := RegInA(7); -- fL: bit desplazado fuera
                -- Overflow (V): el bit de signo cambia (x2 signed desborda)
                if RegInA(7) /= acc_ext(7) then
                    v_RegStatus(5) := '1'; -- fV
                end if;

            when OP_NEG => -- NEG (Two's Complement Negate: 0 - A)
                -- Half-borrow del nibble bajo: 0 - nibbleA
                nibble_res := unsigned'("00000") - nibbleA_ext;
                v_RegStatus(6) := not nibble_res(4); -- fH (borrow convention igual que SUB)

                -- Resta principal 9 bits: 0 - sign_ext(A)
                acc_ext := - resize(signed(RegInA), 9);
                v_RegStatus(7) := not acc_ext(8); -- fC: NOT borrow (C=1 sólo si A=0x00)

                -- Overflow: único caso es A=0x80 (-128); negarlo daría +128 (no cabe en signed 8-bit)
                if RegInA = "10000000" then
                    v_RegStatus(5) := '1'; -- fV
                end if;

            when OP_PSA => -- PA (Pass A)
                acc_ext(7 downto 0) := signed(RegInA);

            when OP_PSB => -- PB (Pass B)
                acc_ext(7 downto 0) := signed(RegInB);

            when OP_CLR => -- CL (Clear ACC)
                acc_ext(7 downto 0) := (others => '0');

            when OP_SET => -- SET (Set ACC)
                acc_ext(7 downto 0) := (others => '1');

            when OP_MUL => -- MUL (Multiply Low)
                mul_res := unsigned(RegInA) * unsigned(RegInB);
                acc_ext(7 downto 0) := signed(mul_res(7 downto 0));
                if mul_res(15 downto 8) /= x"00" then
                    v_RegStatus(7) := '1'; -- fC
                end if;

            when OP_MUH => -- MUH (Multiply High)
                mul_res := unsigned(RegInA) * unsigned(RegInB);
                acc_ext(7 downto 0) := signed(mul_res(15 downto 8));
                if mul_res(15 downto 8) /= x"00" then
                    v_RegStatus(7) := '1'; -- fC
                end if;

            when OP_CMP => -- CMP (Compare)
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
                
                acc_ext(7 downto 0) := signed(RegInA); -- ACC no cambia, mantiene el valor de A

            when OP_ASR => -- ASR (Arithmetic Shift Right)
                acc_ext(7 downto 0) := signed(RegInA(7) & RegInA(7 downto 1));
                v_RegStatus(1) := RegInA(0); -- fR, store shifted-out bit

            when OP_SWP => -- SWAP (Swap Nibbles)
                acc_ext(7 downto 0) := signed(RegInA(3 downto 0) & RegInA(7 downto 4));

            when OP_INB => -- INCB (Increment B → ACC)
                -- El resultado de B+1 sale por ACC; la UC lo enruta hacia el registro B.
                nibble_res := nibbleB_ext + 1;
                v_RegStatus(6) := nibble_res(4); -- fH

                acc_ext := resize(signed(RegInB), 9) + 1;
                v_RegStatus(7) := acc_ext(8); -- fC

                if RegInB = "01111111" then -- 127+1 = 128: overflow signed
                    v_RegStatus(5) := '1'; -- fV
                end if;

            when OP_DEB => -- DECB (Decrement B → ACC)
                -- El resultado de B-1 sale por ACC; la UC lo enruta hacia el registro B.
                nibble_res := nibbleB_ext - 1;
                v_RegStatus(6) := not nibble_res(4); -- fH

                acc_ext := resize(signed(RegInB), 9) - 1;
                v_RegStatus(7) := not acc_ext(8); -- fC (borrow convention)

                if RegInB = "10000000" then -- -128-1 = -129: overflow signed
                    v_RegStatus(5) := '1'; -- fV
                end if;

            when others => -- Opcodes reservados (11100–11111): salida = 0x00
                null;

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
