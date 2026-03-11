library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.CONSTANTS_pkg.ALL;
use work.ALU_pkg.ALL;

package ALU_functions_pkg is

    -- Calcula flags comunes: Zero (Z), Greater (G), Equal (E)
    function calc_common_flags(res : data_vector; opA, opB : data_vector) return status_vector;

    -- Suma Genérica (soporta ADD, ADC, INC)
    function do_add(opA, opB : data_vector; cin : std_logic) return alu_result_record;

    -- Resta Genérica (soporta SUB, SBB, DEC, NEG, CMP)
    function do_sub(opA, opB : data_vector; cin : std_logic) return alu_result_record;

    -- Operaciones de Desplazamiento y Rotación
    function do_shift(op : opcode_vector; val : data_vector) return alu_result_record;

    -- Helpers semánticos para slicing y conversión de datos
    function get_slv_low_nibble(val : data_vector) return nibble_data;
    function get_slv_high_nibble(val : data_vector) return nibble_data;
    function get_slv_low_data_from_double(val : unsigned_double_data_vector) return data_vector;
    function get_slv_high_data_from_double(val : unsigned_double_data_vector) return data_vector;
    function is_high_data_nonzero(val : unsigned_double_data_vector) return boolean;
    function get_uns_data(val : data_vector) return unsigned_data_vector;
    function get_sig_data(val : data_vector) return signed_data_vector;

end package ALU_functions_pkg;


package body ALU_functions_pkg is

    -- Calcula flags comunes: Zero (Z), Greater (G), Equal (E)
    function calc_common_flags(res : data_vector; opA, opB : data_vector) return status_vector is
        variable st : status_vector := (others => '0');
    begin
        if get_sig_data(res) = 0 then st(idx_fZ) := '1'; end if; -- Z
        if get_sig_data(opA) > get_sig_data(opB) then st(idx_fG) := '1'; end if; -- G
        if opA = opB then st(idx_fE) := '1'; end if; -- E
        return st;
    end function;

    -- Suma Genérica (soporta ADD, ADC, INC)
    function do_add(opA, opB : data_vector; cin : std_logic) return alu_result_record is
        variable ret : alu_result_record;
        variable full9 : signed_extended_data_vector;
        variable nibble_res : unsigned_extended_nibble;
    begin
        -- Cálculo principal (9 bits)
        full9 := resize(get_sig_data(opA), full9'length) + resize(get_sig_data(opB), full9'length) + resize(unsigned'('0' & cin), full9'length);
        ret.acc := std_logic_vector(full9(MSB_DATA downto 0));
        
        -- Flags base
        ret.status := calc_common_flags(ret.acc, opA, opB);
        ret.status(idx_fC) := full9(full9'high); -- C (Carry)
        
        -- Half-Carry
        nibble_res := resize(unsigned(opA(MSB_NIBBLE downto 0)), nibble_res'length) + resize(unsigned(opB(MSB_NIBBLE downto 0)), nibble_res'length) + unsigned'('0' & cin);
        ret.status(idx_fH) := nibble_res(nibble_res'high); -- H

        -- Overflow (V): Pos+Pos=Neg o Neg+Neg=Pos
        if opA(MSB_DATA) = opB(MSB_DATA) and ret.acc(MSB_DATA) /= opA(MSB_DATA) then
            ret.status(idx_fV) := '1';
        end if;
        
        return ret;
    end function;

    -- Resta Genérica (soporta SUB, SBB, DEC, NEG, CMP)
    function do_sub(opA, opB : data_vector; cin : std_logic) return alu_result_record is
        variable ret : alu_result_record;
        variable full9 : signed_extended_data_vector;
        variable nibble_res : unsigned_extended_nibble;
    begin
        -- Cálculo principal
        full9 := resize(get_sig_data(opA), full9'length) - resize(get_sig_data(opB), full9'length) - resize(unsigned'('0' & cin), full9'length);
        ret.acc := std_logic_vector(full9(MSB_DATA downto 0));

        -- Flags base
        ret.status := calc_common_flags(ret.acc, opA, opB);
        ret.status(idx_fC) := not full9(full9'high); -- C (Not Borrow)
        
        -- Half-Borrow
        nibble_res := resize(unsigned(opA(MSB_NIBBLE downto 0)), nibble_res'length) - resize(unsigned(opB(MSB_NIBBLE downto 0)), nibble_res'length) - unsigned'('0' & cin);
        ret.status(idx_fH) := not nibble_res(nibble_res'high); -- H

        -- Overflow (V): Pos-Neg=Neg o Neg-Pos=Pos
        if opA(MSB_DATA) /= opB(MSB_DATA) and ret.acc(MSB_DATA) = opB(MSB_DATA) then
            ret.status(idx_fV) := '1';
        end if;

        return ret;
    end function;

    -- Operaciones de Desplazamiento y Rotación
    function do_shift(op : opcode_vector; val : data_vector) return alu_result_record is
        variable ret : alu_result_record;
    begin
        ret.status := (others => '0'); -- Se sobrescribirá luego
        case op is
            when OP_LSL => ret.acc := val(MSB_DATA-1 downto 0) & '0'; ret.status(idx_fL) := val(MSB_DATA); -- L
            when OP_LSR => ret.acc := '0' & val(MSB_DATA downto 1); ret.status(idx_fR) := val(0); -- R
            when OP_ROL => ret.acc := val(MSB_DATA-1 downto 0) & val(MSB_DATA);
            when OP_ROR => ret.acc := val(0) & val(MSB_DATA downto 1);
            when OP_ASL => 
                ret.acc := val(MSB_DATA-1 downto 0) & '0';
                ret.status(idx_fL) := val(MSB_DATA); -- L
                if val(MSB_DATA) /= ret.acc(MSB_DATA) then ret.status(idx_fV) := '1'; end if; -- V
            when OP_ASR => 
                ret.acc := val(MSB_DATA) & val(MSB_DATA downto 1);
                ret.status(idx_fR) := val(0); -- R
            when others => ret.acc := val;
        end case;
        
        if get_sig_data(ret.acc) = 0 then ret.status(idx_fZ) := '1'; end if; -- Z
        return ret;
    end function;

    -- Implementación de helpers semánticos
    function get_slv_low_nibble(val : data_vector) return nibble_data is
        variable res : nibble_data;
    begin
        res := val(MSB_NIBBLE downto 0);
        return res;
    end function;

    function get_slv_high_nibble(val : data_vector) return nibble_data is
        variable res : nibble_data;
    begin
        res := val(MSB_DATA downto NIBBLE_WIDTH);
        return res;
    end function;

    function get_slv_low_data_from_double(val : unsigned_double_data_vector) return data_vector is
    begin
        return std_logic_vector(val(unsigned_double_data_vector_L'range));
    end function;

    function get_slv_high_data_from_double(val : unsigned_double_data_vector) return data_vector is
    begin
        return std_logic_vector(val(unsigned_double_data_vector_H'range));
    end function;

    function is_high_data_nonzero(val : unsigned_double_data_vector) return boolean is
    begin
        return val(unsigned_double_data_vector_H'range) /= 0;
    end function;

    function get_uns_data(val : data_vector) return unsigned_data_vector is
    begin
        return unsigned(val);
    end function;

    function get_sig_data(val : data_vector) return signed_data_vector is
    begin
        return signed(val);
    end function;

end package body ALU_functions_pkg;