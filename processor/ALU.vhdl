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

    -------------------------------------------------------------------------
    -- Funciones auxiliares puras
    -------------------------------------------------------------------------

    -- Calcula flags comunes: Zero (Z), Greater (G), Equal (E)
    function calc_common_flags(res : data_vector; opA, opB : data_vector) return status_vector is
        variable st : status_vector := (others => '0');
    begin
        if signed(res) = 0 then st(4) := '1'; end if; -- Z
        if signed(opA) > signed(opB) then st(3) := '1'; end if; -- G
        if opA = opB then st(2) := '1'; end if; -- E
        return st;
    end function;

    -- Suma Genérica (soporta ADD, ADC, INC)
    function do_add(opA, opB : data_vector; cin : std_logic) return alu_result_record is
        variable ret : alu_result_record;
        variable full9 : signed(8 downto 0);
        variable nibble_res : unsigned(4 downto 0);
    begin
        -- Cálculo principal (9 bits)
        full9 := resize(signed(opA), 9) + resize(signed(opB), 9) + resize(unsigned'('0' & cin), 9);
        ret.acc := std_logic_vector(full9(7 downto 0));
        
        -- Flags base
        ret.status := calc_common_flags(ret.acc, opA, opB);
        ret.status(7) := full9(8); -- C (Carry)
        
        -- Half-Carry
        nibble_res := resize(unsigned(opA(3 downto 0)), 5) + resize(unsigned(opB(3 downto 0)), 5) + unsigned'('0' & cin);
        ret.status(6) := nibble_res(4); -- H

        -- Overflow (V): Pos+Pos=Neg o Neg+Neg=Pos
        if opA(7) = opB(7) and ret.acc(7) /= opA(7) then
            ret.status(5) := '1';
        end if;
        
        return ret;
    end function;

    -- Resta Genérica (soporta SUB, SBB, DEC, NEG, CMP)
    function do_sub(opA, opB : data_vector; cin : std_logic) return alu_result_record is
        variable ret : alu_result_record;
        variable full9 : signed(8 downto 0);
        variable nibble_res : unsigned(4 downto 0);
    begin
        -- Cálculo principal
        full9 := resize(signed(opA), 9) - resize(signed(opB), 9) - resize(unsigned'('0' & cin), 9);
        ret.acc := std_logic_vector(full9(7 downto 0));

        -- Flags base
        ret.status := calc_common_flags(ret.acc, opA, opB);
        ret.status(7) := not full9(8); -- C (Not Borrow)
        
        -- Half-Borrow
        nibble_res := resize(unsigned(opA(3 downto 0)), 5) - resize(unsigned(opB(3 downto 0)), 5) - unsigned'('0' & cin);
        ret.status(6) := not nibble_res(4); -- H

        -- Overflow (V): Pos-Neg=Neg o Neg-Pos=Pos
        if opA(7) /= opB(7) and ret.acc(7) = opB(7) then
            ret.status(5) := '1';
        end if;

        return ret;
    end function;

    -- Operaciones de Desplazamiento y Rotación
    function do_shift(op : opcode_vector; val : data_vector) return alu_result_record is
        variable ret : alu_result_record;
    begin
        ret.status := (others => '0'); -- Se sobrescribirá luego
        case op is
            when OP_LSL => -- Logical Left
                ret.acc := val(6 downto 0) & '0';
                ret.status(0) := val(7); -- L
            when OP_LSR => -- Logical Right
                ret.acc := '0' & val(7 downto 1);
                ret.status(1) := val(0); -- R
            when OP_ROL => -- Rotate Left
                ret.acc := val(6 downto 0) & val(7);
            when OP_ROR => -- Rotate Right
                ret.acc := val(0) & val(7 downto 1);
            when OP_ASL => -- Arithmetic Left
                ret.acc := val(6 downto 0) & '0';
                ret.status(0) := val(7); -- L
                if val(7) /= ret.acc(7) then ret.status(5) := '1'; end if; -- V
            when OP_ASR => -- Arithmetic Right
                ret.acc := val(7) & val(7 downto 1);
                ret.status(1) := val(0); -- R
            when others => 
                ret.acc := val;
        end case;
        
        -- Flags comunes (solo Z es relevante aquí, G y E dependen de entradas originales A y B en wrapper)
        if signed(ret.acc) = 0 then ret.status(4) := '1'; end if;
        return ret;
    end function;

begin

    alu_process: process(RegInA, RegInB, Oper, Carry_in)
        variable res : alu_result_record;
        variable mul_res       : unsigned(15 downto 0);
        
        -- Constantes para reutilización
        constant ONE  : data_vector := x"01";
        constant ZERO : data_vector := x"00";
    begin
        -- 1. Inicialización por defecto de las salidas en cada ejecución
        res.acc    := x"00";
        res.status := (others => '0');

        case Oper is
            when OP_NOP => -- NOP (No Operation)
                res.acc := (others => '0');
                res.status := calc_common_flags(x"00", RegInA, RegInB); -- Para NOP, G y E se calculan

            -- Aritmética: Reutilizamos do_add y do_sub
            when OP_ADD  => res := do_add(RegInA, RegInB, '0');
            when OP_ADC  => res := do_add(RegInA, RegInB, Carry_in);
            when OP_SUB  => res := do_sub(RegInA, RegInB, '0');
            when OP_SBB  => res := do_sub(RegInA, RegInB, Carry_in);
            
            when OP_INC  => res := do_add(RegInA, ONE, '0');    -- INC A = ADD A, 1
            when OP_INB  => res := do_add(RegInB, ONE, '0');    -- INC B = ADD B, 1
            
            when OP_DEC  => res := do_sub(RegInA, ONE, '0');    -- DEC A = SUB A, 1
            when OP_DEB  => res := do_sub(RegInB, ONE, '0');    -- DEC B = SUB B, 1
            
            when OP_NEG  => res := do_sub(ZERO, RegInA, '0');   -- NEG A = SUB 0, A
            
            when OP_CMP  => 
                res := do_sub(RegInA, RegInB, '0'); -- Calcula flags como una resta
                res.acc := RegInA;                  -- Pero restaura A en ACC
                -- Nota: Z se setea en do_sub según (A-B). Si A=B, Z=1. Correcto.

            -- Lógica
            when OP_AND => res.acc := RegInA and RegInB; res.status := calc_common_flags(res.acc, RegInA, RegInB);
            when OP_IOR => res.acc := RegInA or  RegInB; res.status := calc_common_flags(res.acc, RegInA, RegInB);
            when OP_XOR => res.acc := RegInA xor RegInB; res.status := calc_common_flags(res.acc, RegInA, RegInB);
            when OP_NOT => res.acc := not RegInA;        res.status := calc_common_flags(res.acc, RegInA, RegInB);
            when OP_CLR => res.acc := (others => '0');   res.status := calc_common_flags(res.acc, RegInA, RegInB);
            when OP_SET => res.acc := (others => '1');   res.status := calc_common_flags(res.acc, RegInA, RegInB);
            
            -- Transferencia
            when OP_PSA => res.acc := RegInA; res.status := calc_common_flags(res.acc, RegInA, RegInB);
            when OP_PSB => res.acc := RegInB; res.status := calc_common_flags(res.acc, RegInA, RegInB);
            when OP_SWP => 
                res.acc := RegInA(3 downto 0) & RegInA(7 downto 4);
                res.status := calc_common_flags(res.acc, RegInA, RegInB);

            -- Desplazamientos: delegamos en do_shift, y añadimos G y E
            when OP_LSL | OP_LSR | OP_ROL | OP_ROR | OP_ASL | OP_ASR =>
                res := do_shift(Oper, RegInA);
                -- do_shift no ve B, así que recalculamos G y E externos
                if signed(RegInA) > signed(RegInB) then res.status(3) := '1'; end if; -- G
                if RegInA = RegInB then res.status(2) := '1'; end if; -- E

            -- Multiplicación
            when OP_MUL => 
                mul_res := unsigned(RegInA) * unsigned(RegInB);
                res.acc := std_logic_vector(mul_res(7 downto 0));
                res.status := calc_common_flags(res.acc, RegInA, RegInB);
                if mul_res(15 downto 8) /= x"00" then res.status(7) := '1'; end if; -- C

            when OP_MUH => 
                mul_res := unsigned(RegInA) * unsigned(RegInB);
                res.acc := std_logic_vector(mul_res(15 downto 8));
                res.status := calc_common_flags(res.acc, RegInA, RegInB);
                if mul_res(15 downto 8) /= x"00" then res.status(7) := '1'; end if; -- C

            when others => -- Opcodes reservados (11100–11111): salida = 0x00
                null;

        end case;

        -- Asignación final al registro de estado de salida
        RegOutACC <= res.acc;
        RegStatus <= res.status;

    end process alu_process;

end architecture unique;
