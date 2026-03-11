--------------------------------------------------------------------------------
-- Entidad: ALU
-- Descripción:
--   Unidad Aritmético-Lógica de 8 bits.
--   Implementa todas las operaciones definidas en la ISA (aritméticas, lógicas,
--   desplazamientos, etc.) de forma combinacional.
--   Utiliza 'ALU_functions_pkg' para delegar la lógica compleja y mantener
--   este archivo limpio y estructural.
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.ALU_pkg.ALL;
use work.CONSTANTS_pkg.ALL;
use work.ALU_functions_pkg.ALL;

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

begin

    -- =========================================================================
    -- Proceso Principal de la ALU
    -- =========================================================================
    alu_process: process(RegInA, RegInB, Oper, Carry_in)
        variable res : alu_result_record;
        variable mul_res       : unsigned_double_data_vector;
        
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
                res.acc := get_slv_low_nibble(RegInA) & get_slv_high_nibble(RegInA);
                res.status := calc_common_flags(res.acc, RegInA, RegInB);

            -- Desplazamientos: delegamos en do_shift, y añadimos G y E
            when OP_LSL | OP_LSR | OP_ROL | OP_ROR | OP_ASL | OP_ASR =>
                res := do_shift(Oper, RegInA);
                -- do_shift no ve B, así que recalculamos G y E externos
                if get_sig_data(RegInA) > get_sig_data(RegInB) then res.status(idx_fG) := '1'; end if; -- G
                if RegInA = RegInB then res.status(idx_fE) := '1'; end if; -- E

            -- Multiplicación
            when OP_MUL => 
                mul_res := get_uns_data(RegInA) * get_uns_data(RegInB);
                res.acc := get_slv_low_data_from_double(mul_res);
                res.status := calc_common_flags(res.acc, RegInA, RegInB);
                if is_high_data_nonzero(mul_res) then 
                    res.status(idx_fC) := '1'; -- C si la parte alta no es cero
                end if;

            when OP_MUH => 
                mul_res := get_uns_data(RegInA) * get_uns_data(RegInB);
                res.acc := get_slv_high_data_from_double(mul_res);
                res.status := calc_common_flags(res.acc, RegInA, RegInB);
                if is_high_data_nonzero(mul_res) then 
                    res.status(idx_fC) := '1'; -- C
                end if;

            when others => -- Opcodes reservados (11100–11111): salida = 0x00
                null;

        end case;

        -- Asignación final al registro de estado de salida
        RegOutACC <= res.acc;
        RegStatus <= res.status;

    end process alu_process;

end architecture unique;
