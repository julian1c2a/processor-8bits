library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.CONSTANTS_pkg.ALL;
use work.ALU_pkg.ALL;

-- =============================================================================
-- Paquete: ALU_functions_pkg
-- Descripción:
--   Contiene las funciones puras que implementan la lógica aritmética y de
--   desplazamiento de la ALU de 8 bits.  Al ser funciones puras (sin estado),
--   el sintetizador las trata como lógica combinacional reutilizable.
--   Separar estas funciones del archivo ALU.vhdl permite:
--     a) Mantener ALU.vhdl limpio y estructural (solo el case/mux).
--     b) Reutilizar la lógica en simulación o en otros módulos si fuera necesario.
--     c) Facilitar las pruebas unitarias de cada función de forma independiente.
-- =============================================================================
package ALU_functions_pkg is

    -- -------------------------------------------------------------------------
    -- calc_common_flags:
    --   Calcula los flags comunes Z (Zero), G (Greater) y E (Equal).
    --   Recibe el RESULTADO de la operación (res) y los dos OPERANDOS originales
    --   (opA, opB).  Nota importante: G y E se calculan a partir de los operandos
    --   ORIGINALES (opA vs opB), no del resultado, porque representan la relación
    --   entre los datos de entrada, no el resultado de la operación.
    --   Esto es necesario para que instrucciones como AND, OR, MOV, etc. actualicen
    --   G y E correctamente (útil para saltos condicionales JG, JE sin ejecutar CMP).
    -- -------------------------------------------------------------------------
    function calc_common_flags(res : data_vector; opA, opB : data_vector) return status_vector;

    -- -------------------------------------------------------------------------
    -- do_add:
    --   Suma genérica de 8 bits con acarreo de entrada (cin).
    --   Soporta ADD (cin='0'), ADC (cin=Carry_in) e INC (opB=1, cin='0').
    --   Produce resultado de 8 bits en ret.acc y todos los flags aritméticos.
    -- -------------------------------------------------------------------------
    function do_add(opA, opB : data_vector; cin : std_logic) return alu_result_record;

    -- -------------------------------------------------------------------------
    -- do_sub:
    --   Resta genérica de 8 bits con borrow de entrada (cin).
    --   Soporta SUB (cin='0'), SBB (cin=Carry_in), DEC (opB=1), NEG (opA=0),
    --   y CMP (solo flags, el llamador restaura acc).
    --   Produce resultado de 8 bits en ret.acc y todos los flags aritméticos.
    -- -------------------------------------------------------------------------
    function do_sub(opA, opB : data_vector; cin : std_logic) return alu_result_record;

    -- -------------------------------------------------------------------------
    -- do_shift:
    --   Ejecuta la operación de desplazamiento/rotación indicada por 'op'.
    --   Solo recibe el operando 'val' (= RegInA); no conoce RegInB, por lo que
    --   los flags G y E deben añadirse externamente desde ALU.vhdl.
    -- -------------------------------------------------------------------------
    function do_shift(op : opcode_vector; val : data_vector) return alu_result_record;

    -- -------------------------------------------------------------------------
    -- Helpers semánticos para slicing y conversión de datos.
    -- Estas funciones existen por tres razones:
    --   1. Seguridad de tipos: VHDL no permite mezclar std_logic_vector con
    --      unsigned/signed sin conversión explícita.  Los helpers centralizan
    --      las conversiones y evitan errores silenciosos de tipo.
    --   2. Legibilidad: "get_slv_low_nibble(x)" es más claro que "x(3 downto 0)".
    --   3. Mantenibilidad: si cambia DATA_WIDTH, basta con actualizar las
    --      constantes MSB_DATA/NIBBLE_WIDTH; los llamadores no cambian.
    -- -------------------------------------------------------------------------
    function get_slv_low_nibble(val : data_vector) return nibble_data;           -- Nibble bajo [3:0]
    function get_slv_high_nibble(val : data_vector) return nibble_data;          -- Nibble alto [7:4]
    function get_slv_low_data_from_double(val : unsigned_double_data_vector) return data_vector;  -- Byte bajo de 16 bits
    function get_slv_high_data_from_double(val : unsigned_double_data_vector) return data_vector; -- Byte alto de 16 bits
    function is_high_data_nonzero(val : unsigned_double_data_vector) return boolean;              -- ¿Hay datos en el byte alto?
    function get_uns_data(val : data_vector) return unsigned_data_vector;        -- Convierte a unsigned (sin signo)
    function get_sig_data(val : data_vector) return signed_data_vector;          -- Convierte a signed (con signo, complemento a 2)

end package ALU_functions_pkg;


package body ALU_functions_pkg is

    -- =========================================================================
    -- calc_common_flags
    -- =========================================================================
    -- Calcula flags comunes: Zero (Z), Greater (G), Equal (E)
    --
    -- Por qué G y E se calculan para TODAS las operaciones (no solo CMP):
    --   La ISA permite saltos condicionales como JG/JE después de cualquier
    --   instrucción que actualice flags (AND, OR, ADD, MOV, etc.).  Si G y E
    --   solo se actualizaran en CMP, el programador estaría forzado a insertar
    --   un CMP redundante tras cada operación, desperdiciando ciclos.
    --
    -- Por qué G usa comparación CON SIGNO (get_sig_data):
    --   El flag G representa "mayor que" en aritmética con signo (signed greater).
    --   Si se usara unsigned, comparar 0xFF > 0x01 daría G=1 (255 > 1 sin signo),
    --   pero en complemento a 2 es -1 < 1, por lo que G debería ser 0.
    --   La comparación signed respeta el bit de signo (MSB) correctamente.
    --
    -- Por qué E usa comparación directa de std_logic_vector (opA = opB):
    --   La igualdad bit a bit no depende de la interpretación del signo,
    --   así que la comparación directa de SLV es correcta y más eficiente.
    function calc_common_flags(res : data_vector; opA, opB : data_vector) return status_vector is
        variable st : status_vector := (others => '0'); -- Inicializar todos los flags a 0
    begin
        -- Z (Zero): se activa si el resultado de la operación es exactamente cero
        if get_sig_data(res) = 0 then st(idx_fZ) := '1'; end if; -- Z

        -- G (Greater): opA > opB con signo; refleja la relación entre los operandos originales
        if get_sig_data(opA) > get_sig_data(opB) then st(idx_fG) := '1'; end if; -- G

        -- E (Equal): opA = opB bit a bit; independiente del signo
        if opA = opB then st(idx_fE) := '1'; end if; -- E

        return st;
    end function;

    -- =========================================================================
    -- do_add
    -- =========================================================================
    -- Suma Genérica (soporta ADD, ADC, INC)
    --
    -- Truco del vector de 9 bits (signed_extended_data_vector):
    --   El resultado natural de sumar dos valores de 8 bits puede tener 9 bits
    --   (p.ej. 0xFF + 0x01 = 0x100).  Al ampliar ambos operandos a 9 bits con
    --   resize() y realizar la suma, el bit [8] (el noveno) captura exactamente
    --   el acarreo de salida (carry-out).  De este modo, full9(8) = carry.
    --   El resultado de 8 bits se obtiene con full9(7 downto 0).
    --
    -- Cálculo del Half-Carry (H):
    --   El half-carry indica acarreo del nibble bajo (bits [3:0]) al nibble alto
    --   (bits [7:4]), necesario para la instrucción DAA (ajuste decimal BCD).
    --   Se calcula extendiendo solo los nibbles bajos a 5 bits; el bit [4] es
    --   el half-carry.  La suma incluye cin para ADC/SBB encadenados.
    --
    -- Regla de Overflow (V) para la suma:
    --   Desbordamiento con signo ocurre cuando dos números de IGUAL signo producen
    --   un resultado de DISTINTO signo (imposible en aritmética real):
    --     Positivo + Positivo = Negativo → overflow
    --     Negativo + Negativo = Positivo → overflow
    --   Detección: opA[7] = opB[7] (misma polaridad) AND resultado[7] ≠ opA[7]
    function do_add(opA, opB : data_vector; cin : std_logic) return alu_result_record is
        variable ret        : alu_result_record;
        variable full9      : signed_extended_data_vector;  -- 9 bits: [8]=carry, [7:0]=resultado
        variable nibble_res : unsigned_extended_nibble;     -- 5 bits: [4]=half-carry, [3:0]=resultado nibble
    begin
        -- Cálculo principal (9 bits):
        --   Ambos operandos se amplían de 8 a 9 bits (resize con signo para conservar el MSB).
        --   cin se convierte de std_logic a unsigned de 1 bit antes de resize a 9 bits.
        --   El bit [8] de full9 es el carry-out de la suma de 8 bits.
        full9 := resize(get_sig_data(opA), full9'length)
               + resize(get_sig_data(opB), full9'length)
               + signed(resize(unsigned'('0' & cin), full9'length));
        ret.acc := std_logic_vector(full9(MSB_DATA downto 0)); -- Resultado de 8 bits

        -- Flags base (Z, G, E se derivan de los operandos originales y el resultado)
        ret.status := calc_common_flags(ret.acc, opA, opB);

        -- C (Carry): el bit [8] de full9 es el acarreo de salida del sumador de 8 bits
        ret.status(idx_fC) := full9(full9'high); -- C (Carry)

        -- Half-Carry (H):
        --   Se suman solo los nibbles bajos extendidos a 5 bits.
        --   El bit [4] indica si hubo acarreo del bit 3 al bit 4 (half-carry BCD).
        nibble_res := resize(unsigned(opA(MSB_NIBBLE downto 0)), nibble_res'length)
                    + resize(unsigned(opB(MSB_NIBBLE downto 0)), nibble_res'length)
                    + unsigned'('0' & cin);
        ret.status(idx_fH) := nibble_res(nibble_res'high); -- H (Half-Carry, bit[4])

        -- Overflow (V): Pos+Pos=Neg o Neg+Neg=Pos
        --   Condición: mismo signo en entradas (opA[7]=opB[7]) y signo diferente en salida
        if opA(MSB_DATA) = opB(MSB_DATA) and ret.acc(MSB_DATA) /= opA(MSB_DATA) then
            ret.status(idx_fV) := '1';
        end if;

        return ret;
    end function;

    -- =========================================================================
    -- do_sub
    -- =========================================================================
    -- Resta Genérica (soporta SUB, SBB, DEC, NEG, CMP)
    --
    -- Convención C = NOT borrow (convención ARM/RISC):
    --   En la mayoría de arquitecturas, el flag C en una resta indica NO-borrow:
    --     C=1 si opA >= opB (no hubo borrow, la resta "cabía")
    --     C=0 si opA <  opB (hubo borrow, el resultado es negativo sin signo)
    --   Esto es opuesto al bit de borrow natural del sumador.  Por ello se niega:
    --   ret.status(idx_fC) := NOT full9(8).
    --   Ventaja: permite encadenar restas con SBB de la misma forma que se
    --   encadenan sumas con ADC, usando el mismo flag C.
    --
    -- Cálculo del Half-Borrow (H):
    --   Análogo al half-carry pero para la resta del nibble bajo.
    --   El bit [4] del resultado de la resta de nibbles es 1 si hubo borrow
    --   del nibble bajo al alto.  Se niega para seguir la convención NOT-borrow.
    --
    -- Regla de Overflow (V) para la resta:
    --   Desbordamiento ocurre cuando operandos de DISTINTO signo producen un
    --   resultado con el MISMO signo que el sustraendo (opB):
    --     Positivo - Negativo = Negativo → overflow (debería ser positivo)
    --     Negativo - Positivo = Positivo → overflow (debería ser negativo)
    --   Detección: opA[7] ≠ opB[7] (distinta polaridad) AND resultado[7] = opB[7]
    function do_sub(opA, opB : data_vector; cin : std_logic) return alu_result_record is
        variable ret        : alu_result_record;
        variable full9      : signed_extended_data_vector;  -- 9 bits: [8]=borrow, [7:0]=resultado
        variable nibble_res : unsigned_extended_nibble;     -- 5 bits: [4]=half-borrow, [3:0]=resultado nibble
    begin
        -- Cálculo principal (9 bits):
        --   full9[8]=1 indica borrow (el resultado sin signo es negativo, opA < opB+cin).
        --   cin actúa como borrow-in para instrucciones SBB encadenadas.
        full9 := resize(get_sig_data(opA), full9'length)
               - resize(get_sig_data(opB), full9'length)
               - signed(resize(unsigned'('0' & cin), full9'length));
        ret.acc := std_logic_vector(full9(MSB_DATA downto 0)); -- Resultado de 8 bits

        -- Flags base (Z, G, E se derivan de los operandos originales y el resultado)
        ret.status := calc_common_flags(ret.acc, opA, opB);

        -- C (Not Borrow): NOT del bit de borrow natural del sumador de 9 bits.
        --   C=1 significa "no hubo borrow" → opA >= opB (unsigned).
        --   C=0 significa "hubo borrow"    → opA <  opB (unsigned).
        ret.status(idx_fC) := not full9(full9'high); -- C (Not Borrow)

        -- Half-Borrow (H):
        --   Se restan solo los nibbles bajos extendidos a 5 bits.
        --   El bit [4] es el borrow del nibble; se niega para la misma convención NOT-borrow.
        nibble_res := resize(unsigned(opA(MSB_NIBBLE downto 0)), nibble_res'length)
                    - resize(unsigned(opB(MSB_NIBBLE downto 0)), nibble_res'length)
                    - unsigned'('0' & cin);
        ret.status(idx_fH) := not nibble_res(nibble_res'high); -- H (Not Half-Borrow)

        -- Overflow (V): Pos-Neg=Neg o Neg-Pos=Pos
        --   Condición: distinto signo en entradas (opA[7]≠opB[7]) y
        --              el resultado tiene el mismo signo que el sustraendo (opB[7])
        if opA(MSB_DATA) /= opB(MSB_DATA) and ret.acc(MSB_DATA) = opB(MSB_DATA) then
            ret.status(idx_fV) := '1';
        end if;

        return ret;
    end function;

    -- =========================================================================
    -- do_shift
    -- =========================================================================
    -- Operaciones de Desplazamiento y Rotación
    --
    -- Cada variante:
    --   OP_LSL (Logical Shift Left):
    --     Desplaza hacia la izquierda; entra '0' por la derecha.
    --     El bit [7] (MSB) desalojado se guarda en el flag L (Lost/Carry izquierda).
    --     Útil para multiplicar por 2 (sin signo).
    --
    --   OP_LSR (Logical Shift Right):
    --     Desplaza hacia la derecha; entra '0' por la izquierda.
    --     El bit [0] (LSB) desalojado se guarda en el flag R (Resto).
    --     Útil para dividir por 2 (sin signo).
    --
    --   OP_ROL (Rotate Left):
    --     Rotación circular izquierda: el MSB reaparece como LSB.
    --     No modifica flags L/R (no hay bit "perdido").
    --     Útil para operaciones de cifrado o cíclicas.
    --
    --   OP_ROR (Rotate Right):
    --     Rotación circular derecha: el LSB reaparece como MSB.
    --     No modifica flags L/R.
    --     Útil para operaciones de cifrado o cíclicas.
    --
    --   OP_ASL (Arithmetic Shift Left):
    --     Igual a LSL en cuanto al resultado, pero activa el flag V (Overflow)
    --     si el signo del resultado difiere del signo original (el desplazamiento
    --     habría desbordado en aritmética con signo).
    --     El MSB desalojado se guarda en L.
    --
    --   OP_ASR (Arithmetic Shift Right):
    --     Desplaza hacia la derecha; el MSB (signo) se replica para conservar el signo.
    --     Equivale a dividir por 2 con signo (floor division).
    --     El LSB desalojado se guarda en R.
    --
    --   Z (Zero): se calcula al final para todas las variantes, comprobando si el
    --     resultado es cero (común a todos los desplazamientos).
    --
    --   NOTA: do_shift no ve RegInB, por lo que los flags G y E deben añadirse
    --   externamente en ALU.vhdl tras llamar a esta función.
    function do_shift(op : opcode_vector; val : data_vector) return alu_result_record is
        variable ret : alu_result_record;
    begin
        ret.status := (others => '0'); -- Inicializar todos los flags a 0; se sobrescribirán según la operación

        case op is
            -- LSL: desplaza izquierda, entra 0 por la derecha, MSB sale por el flag L
            when OP_LSL =>
                ret.acc := val(MSB_DATA-1 downto 0) & '0';  -- [6:0] || 0
                ret.status(idx_fL) := val(MSB_DATA);         -- L = bit desalojado por la izquierda

            -- LSR: desplaza derecha, entra 0 por la izquierda, LSB sale por el flag R
            when OP_LSR =>
                ret.acc := '0' & val(MSB_DATA downto 1);     -- 0 || [7:1]
                ret.status(idx_fR) := val(0);                 -- R = bit desalojado por la derecha

            -- ROL: rotación circular izquierda; el MSB regresa como LSB (sin pérdida de datos)
            when OP_ROL =>
                ret.acc := val(MSB_DATA-1 downto 0) & val(MSB_DATA); -- [6:0] || [7]

            -- ROR: rotación circular derecha; el LSB regresa como MSB (sin pérdida de datos)
            when OP_ROR =>
                ret.acc := val(0) & val(MSB_DATA downto 1);   -- [0] || [7:1]

            -- ASL: desplaza izquierda aritmético; detecta overflow si cambia el signo
            when OP_ASL =>
                ret.acc := val(MSB_DATA-1 downto 0) & '0';   -- Mismo resultado que LSL
                ret.status(idx_fL) := val(MSB_DATA);          -- L = MSB desalojado
                -- V = 1 si el bit de signo del resultado es distinto al original
                -- (el desplazamiento ha cambiado el signo → desbordamiento aritmético)
                if val(MSB_DATA) /= ret.acc(MSB_DATA) then ret.status(idx_fV) := '1'; end if; -- V

            -- ASR: desplaza derecha aritmético; replica el MSB para preservar el signo
            when OP_ASR =>
                ret.acc := val(MSB_DATA) & val(MSB_DATA downto 1); -- [7] || [7:1] (extensión de signo)
                ret.status(idx_fR) := val(0);                       -- R = LSB desalojado

            -- others: opcode no reconocido → pasa el valor sin modificar (operación segura)
            when others => ret.acc := val;
        end case;

        -- Z (Zero): flag común a todas las variantes de desplazamiento
        if get_sig_data(ret.acc) = 0 then ret.status(idx_fZ) := '1'; end if; -- Z

        return ret;
    end function;

    -- =========================================================================
    -- Implementación de helpers semánticos
    -- =========================================================================

    -- get_slv_low_nibble: extrae los bits [MSB_NIBBLE:0] (nibble bajo, bits 3..0)
    -- Centraliza el slicing para evitar literales mágicos en el código principal.
    function get_slv_low_nibble(val : data_vector) return nibble_data is
        variable res : nibble_data;
    begin
        res := val(MSB_NIBBLE downto 0); -- Nibble bajo: bits [3:0]
        return res;
    end function;

    -- get_slv_high_nibble: extrae los bits [MSB_DATA:NIBBLE_WIDTH] (nibble alto, bits 7..4)
    -- Centraliza el slicing del nibble alto para la instrucción SWP (swap nibbles).
    function get_slv_high_nibble(val : data_vector) return nibble_data is
        variable res : nibble_data;
    begin
        res := val(MSB_DATA downto NIBBLE_WIDTH); -- Nibble alto: bits [7:4]
        return res;
    end function;

    -- get_slv_low_data_from_double: extrae el byte bajo de un resultado de 16 bits.
    -- Usado en OP_MUL para obtener los 8 bits bajos del producto A*B.
    -- El rango unsigned_double_data_vector_L se define en ALU_pkg para evitar
    -- dependencias de literales aquí.
    function get_slv_low_data_from_double(val : unsigned_double_data_vector) return data_vector is
    begin
        return std_logic_vector(val(unsigned_double_data_vector_L'range)); -- Byte bajo del producto
    end function;

    -- get_slv_high_data_from_double: extrae el byte alto de un resultado de 16 bits.
    -- Usado en OP_MUH para obtener los 8 bits altos del producto A*B.
    function get_slv_high_data_from_double(val : unsigned_double_data_vector) return data_vector is
    begin
        return std_logic_vector(val(unsigned_double_data_vector_H'range)); -- Byte alto del producto
    end function;

    -- is_high_data_nonzero: devuelve true si el byte alto del producto es distinto de cero.
    -- Usado para activar el flag C tras MUL/MUH: C=1 indica que el resultado
    -- no cabe en 8 bits (la parte alta es significativa).
    function is_high_data_nonzero(val : unsigned_double_data_vector) return boolean is
    begin
        return val(unsigned_double_data_vector_H'range) /= 0; -- ¿Desborde a parte alta?
    end function;

    -- get_uns_data: convierte data_vector a unsigned_data_vector.
    -- Wrapper explícito para evitar cast directo en expresiones complejas;
    -- mejora la legibilidad y centraliza la política de conversión sin signo.
    function get_uns_data(val : data_vector) return unsigned_data_vector is
    begin
        return unsigned(val); -- Interpretación sin signo (unsigned)
    end function;

    -- get_sig_data: convierte data_vector a signed_data_vector (complemento a 2).
    -- Wrapper explícito para comparaciones con signo (flags G, V) y extensiones
    -- de signo en resize().  Centralizar aquí evita errores de cast en llamadores.
    function get_sig_data(val : data_vector) return signed_data_vector is
    begin
        return signed(val); -- Interpretación con signo (complemento a 2)
    end function;

end package body ALU_functions_pkg;
