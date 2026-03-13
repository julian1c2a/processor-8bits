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
        RegInA    : in  data_vector;    -- Operando A: registro A de 8 bits (minuendo, primer operando)
        RegInB    : in  data_vector;    -- Operando B: registro B de 8 bits (sustraendo, segundo operando, índice)
        Oper      : in  opcode_vector;  -- Código de operación de la ISA (selecciona la función ALU)
        Carry_in  : in  STD_LOGIC := '0'; -- Entrada de carry/borrow para ADC y SBB (encadenamiento de operaciones)
        RegOutACC : out data_vector;    -- Resultado de 8 bits hacia el acumulador (registro destino)
        RegStatus : out status_vector   -- Vector de flags actualizado tras cada operación
    );
end entity ALU;

architecture unique of ALU is

begin

    -- =========================================================================
    -- Proceso Principal de la ALU
    -- =========================================================================
    -- Lista de sensibilidad: se incluyen los CUATRO inputs porque cualquier
    -- cambio en cualquiera de ellos debe re-evaluar la salida combinacional.
    --   - RegInA, RegInB: operandos; cambian cuando la UC selecciona nuevos registros.
    --   - Oper: código de operación; cambia en cada instrucción decodificada.
    --   - Carry_in: el flag C del ciclo anterior; solo importa para ADC/SBB,
    --     pero debe estar en la lista para que el proceso se reevalúe cuando
    --     el flag cambia incluso durante una instrucción ADC/SBB.
    -- Omitir cualquiera de ellos crearía un latch implícito en síntesis.
    alu_process: process(RegInA, RegInB, Oper, Carry_in)
        variable res     : alu_result_record;            -- Registro temporal que acumula resultado y flags
        variable mul_res : unsigned_double_data_vector;  -- Producto de 16 bits antes de extraer byte alto/bajo

        -- Constantes para reutilización en INC/DEC/NEG:
        --   ONE: valor 1 para INC y DEC (evita instanciar un literal numérico en cada rama).
        --   ZERO: valor 0 para NEG (NEG A = 0 - A); también sirve como base para do_sub.
        constant ONE  : data_vector := x"01";
        constant ZERO : data_vector := x"00";
    begin
        -- 1. Inicialización por defecto de las salidas en cada ejecución del proceso.
        --    Es IMPRESCINDIBLE en lógica combinacional: si no se asigna un valor
        --    por defecto antes del case, el sintetizador inferiría latches para
        --    los casos no cubiertos, convirtiendo el circuito en secuencial.
        --    Al asignar x"00" y (others=>'0') aquí, todos los casos no cubiertos
        --    (when others => null) heredan estos valores de forma segura.
        res.acc    := x"00";
        res.status := (others => '0');

        case Oper is

            -- -----------------------------------------------------------------
            -- OP_NOP: No Operation
            --   El acumulador no cambia (sale x"00" por la inicialización).
            --   Sin embargo, G y E SÍ se calculan: la ISA permite que instrucciones
            --   de salto condicional como JG/JE operen sobre flags dejados por
            --   cualquier instrucción previa, incluido NOP en ciertos contextos de
            --   pipeline o relleno.  Calcular G/E aquí garantiza que los flags
            --   reflejen la relación entre A y B en todo momento, sin necesidad
            --   de un CMP explícito previo.
            -- -----------------------------------------------------------------
            when OP_NOP =>
                res.acc := (others => '0');
                res.status := calc_common_flags(x"00", RegInA, RegInB); -- G y E válidos tras NOP

            -- -----------------------------------------------------------------
            -- Aritmética: Reutilizamos do_add y do_sub
            --   do_add y do_sub son funciones puras definidas en ALU_functions_pkg.
            --   Reciben los operandos y el carry-in y devuelven resultado + todos los flags.
            -- -----------------------------------------------------------------
            when OP_ADD  => res := do_add(RegInA, RegInB, '0');       -- A + B, sin carry
            when OP_ADC  => res := do_add(RegInA, RegInB, Carry_in);  -- A + B + C (suma con acarreo)
            when OP_SUB  => res := do_sub(RegInA, RegInB, '0');       -- A - B, sin borrow
            when OP_SBB  => res := do_sub(RegInA, RegInB, Carry_in);  -- A - B - C (resta con borrow)

            -- -----------------------------------------------------------------
            -- OP_INC / OP_DEC: Incremento y Decremento del registro A
            --   Se reutilizan do_add y do_sub con ONE como segundo operando,
            --   evitando duplicar la lógica de flags.  Carry_in = '0' porque
            --   INC/DEC no son operaciones encadenadas.
            -- -----------------------------------------------------------------
            when OP_INC  => res := do_add(RegInA, ONE, '0');    -- INC A = ADD A, 1
            -- -----------------------------------------------------------------
            -- OP_INB: Incremento del registro B a través de la ALU
            --   B entra por RegInB, la ALU calcula B+1 y coloca el resultado en
            --   RegOutACC.  La UC debe enrutar RegOutACC de vuelta al registro B
            --   mediante Write_B=1 y Reg_Sel=B en el DataPath.
            --   Este mecanismo evita un puerto adicional en la ALU para operar sobre B.
            -- -----------------------------------------------------------------
            when OP_INB  => res := do_add(RegInB, ONE, '0');    -- INC B = ADD B, 1

            when OP_DEC  => res := do_sub(RegInA, ONE, '0');    -- DEC A = SUB A, 1
            -- -----------------------------------------------------------------
            -- OP_DEB: Decremento del registro B a través de la ALU
            --   Igual que OP_INB pero con resta.  La UC enruta el resultado
            --   de la ALU de vuelta a B (Write_B=1, Reg_Sel=B).
            -- -----------------------------------------------------------------
            when OP_DEB  => res := do_sub(RegInB, ONE, '0');    -- DEC B = SUB B, 1

            -- -----------------------------------------------------------------
            -- OP_NEG: Negación aritmética (complemento a 2)
            --   NEG A = 0 - A.  Se implementa como do_sub(0, A, 0):
            --   el minuendo es ZERO y el sustraendo es A.
            --   Resultado: todos los flags aritméticos correctos, incluyendo
            --   V (overflow cuando A=0x80, ya que -128 no tiene representación
            --   positiva en 8 bits con signo).
            -- -----------------------------------------------------------------
            when OP_NEG  => res := do_sub(ZERO, RegInA, '0');   -- NEG A = SUB 0, A

            -- -----------------------------------------------------------------
            -- OP_CMP: Comparación (establece flags sin modificar A)
            --   Se calcula A - B para obtener todos los flags (Z, C, V, G, E).
            --   Luego se RESTAURA A en res.acc para que el DataPath no destruya
            --   el valor de A al escribir el acumulador.
            --   Nota sobre Z: do_sub lo calcula correctamente basándose en (A-B).
            --   Si A=B → (A-B)=0 → Z=1.  El reemplazar res.acc por RegInA no
            --   afecta a Z porque Z ya fue calculado a partir del resultado de la resta.
            -- -----------------------------------------------------------------
            when OP_CMP  =>
                res := do_sub(RegInA, RegInB, '0'); -- Calcula flags como una resta A - B
                res.acc := RegInA;                  -- Restaura A: CMP no debe modificar el acumulador

            -- -----------------------------------------------------------------
            -- Lógica: AND, OR, XOR, NOT, CLR, SET
            --   Operaciones bit a bit sobre los operandos.
            --   calc_common_flags calcula Z, G, E a partir del resultado y los operandos.
            --   C, H y V no tienen significado para operaciones lógicas (quedan a 0).
            -- -----------------------------------------------------------------
            when OP_AND => res.acc := RegInA and RegInB; res.status := calc_common_flags(res.acc, RegInA, RegInB); -- AND bit a bit
            when OP_IOR => res.acc := RegInA or  RegInB; res.status := calc_common_flags(res.acc, RegInA, RegInB); -- OR  bit a bit (Inclusive OR)
            when OP_XOR => res.acc := RegInA xor RegInB; res.status := calc_common_flags(res.acc, RegInA, RegInB); -- XOR bit a bit
            when OP_NOT => res.acc := not RegInA;        res.status := calc_common_flags(res.acc, RegInA, RegInB); -- NOT A (complemento a 1)
            when OP_CLR => res.acc := (others => '0');   res.status := calc_common_flags(res.acc, RegInA, RegInB); -- CLR A = 0x00 (Z=1 siempre)
            when OP_SET => res.acc := (others => '1');   res.status := calc_common_flags(res.acc, RegInA, RegInB); -- SET A = 0xFF (Z=0 siempre)

            -- -----------------------------------------------------------------
            -- Transferencia: PSA, PSB, SWP
            --   PSA/PSB pasan el valor de A o B al acumulador sin modificarlo.
            --   SWP intercambia los nibbles de A (bits [7:4] ↔ [3:0]).
            --   calc_common_flags actualiza Z, G, E con el valor transferido.
            -- -----------------------------------------------------------------
            when OP_PSA => res.acc := RegInA; res.status := calc_common_flags(res.acc, RegInA, RegInB);              -- Pass A: A → ACC
            when OP_PSB => res.acc := RegInB; res.status := calc_common_flags(res.acc, RegInA, RegInB);              -- Pass B: B → ACC
            when OP_SWP =>
                -- Intercambia nibble bajo [3:0] con nibble alto [7:4] de A
                res.acc := get_slv_low_nibble(RegInA) & get_slv_high_nibble(RegInA); -- SWP: [3:0]||[7:4]
                res.status := calc_common_flags(res.acc, RegInA, RegInB);

            -- -----------------------------------------------------------------
            -- Desplazamientos y Rotaciones: delegan en do_shift
            --   do_shift calcula el resultado y los flags L, R, V, Z según la
            --   operación, pero NO conoce RegInB (solo opera sobre val=RegInA).
            --   Por ello, después de la llamada a do_shift, los flags G y E se
            --   añaden externamente usando la misma lógica que calc_common_flags:
            --     G = RegInA > RegInB (con signo)
            --     E = RegInA = RegInB (comparación directa de SLV)
            --   Esto garantiza que las instrucciones de salto condicional que
            --   sigan a un desplazamiento tengan G y E correctos.
            -- -----------------------------------------------------------------
            when OP_LSL | OP_LSR | OP_ROL | OP_ROR | OP_ASL | OP_ASR =>
                res := do_shift(Oper, RegInA, Carry_in); -- do_shift calcula Z, L, R, V, C(ROL/ROR) pero no ve RegInB
                -- G y E se añaden externamente: do_shift solo ve RegInA, no RegInB
                if get_sig_data(RegInA) > get_sig_data(RegInB) then res.status(idx_fG) := '1'; end if; -- G (con signo)
                if RegInA = RegInB then res.status(idx_fE) := '1'; end if;                             -- E (igualdad bit a bit)

            -- -----------------------------------------------------------------
            -- Multiplicación: OP_MUL y OP_MUH
            --   El producto de dos valores de 8 bits puede tener hasta 16 bits.
            --   No se puede devolver un resultado de 16 bits en el acumulador de 8 bits
            --   en una sola operación sin ampliar el bus de datos.
            --   Por ello, se usan DOS opcodes separados:
            --     OP_MUL: devuelve los 8 bits BAJOS  del producto (A*B)[7:0]
            --     OP_MUH: devuelve los 8 bits ALTOS del producto (A*B)[15:8]
            --   El programador ejecuta MUL primero (guarda el resultado en memoria),
            --   luego MUH para obtener la parte alta.
            --   Flag C=1 en ambos casos si el byte alto del producto es distinto de 0,
            --   indicando que el resultado no cabe en 8 bits (desborde de multiplicación).
            -- -----------------------------------------------------------------
            when OP_MUL =>
                mul_res := get_uns_data(RegInA) * get_uns_data(RegInB); -- Producto completo de 16 bits (sin signo)
                res.acc := get_slv_low_data_from_double(mul_res);        -- Byte bajo: (A*B)[7:0]
                res.status := calc_common_flags(res.acc, RegInA, RegInB);
                if is_high_data_nonzero(mul_res) then
                    res.status(idx_fC) := '1'; -- C=1 si el resultado no cabe en 8 bits (parte alta ≠ 0)
                end if;

            when OP_MUH =>
                mul_res := get_uns_data(RegInA) * get_uns_data(RegInB); -- Producto completo de 16 bits (sin signo)
                res.acc := get_slv_high_data_from_double(mul_res);       -- Byte alto: (A*B)[15:8]
                res.status := calc_common_flags(res.acc, RegInA, RegInB);
                if is_high_data_nonzero(mul_res) then
                    res.status(idx_fC) := '1'; -- C=1 si la parte alta es significativa
                end if;

            -- -----------------------------------------------------------------
            -- when others: Opcodes reservados
            --   Los opcodes que no corresponden a ninguna operación definida
            --   caen aquí.  El 'null' no asigna nada, por lo que res conserva
            --   los valores de la inicialización: acc=0x00 y status=(others=>'0').
            --   Esto es un comportamiento seguro y determinista: la ALU produce
            --   cero en lugar de un valor indeterminado.  La UC no debería emitir
            --   estos opcodes en condiciones normales de operación.
            -- -----------------------------------------------------------------
            when others => -- Opcodes reservados (11100–11111): salida = 0x00 (por inicialización)
                null;

        end case;

        -- Asignación final al registro de estado de salida
        -- Se realiza fuera del case para garantizar una única asignación
        -- combinacional a las salidas en cada evaluación del proceso.
        RegOutACC <= res.acc;
        RegStatus <= res.status;

    end process alu_process;

end architecture unique;
