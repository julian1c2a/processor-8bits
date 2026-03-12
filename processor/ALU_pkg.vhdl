library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.CONSTANTS_pkg.ALL;

-- =========================================================================
-- Paquete: ALU_pkg
-- Descripción:
--   Define los tipos de datos, subtypes, registros de resultado y constantes
--   de opcode de la Unidad Aritmético-Lógica (ALU) de 8 bits.
--
--   Usado tanto por los testbenches exhaustivos como por el testbench manual,
--   y por la Unidad de Control para construir las microinstrucciones ALU.
-- =========================================================================
package ALU_pkg is

    -- =========================================================================
    -- Tipos globales del sistema (subtypes de std_logic_vector)
    -- =========================================================================
    -- Los subtypes encapsulan el ancho de cada bus y evitan errores de asignación
    -- entre señales de distinta función (aunque tengan el mismo ancho en bits).

    -- Vector de dato de 8 bits: representa un byte de datos del procesador.
    -- Usado como tipo de todos los registros de propósito general (R0..R7),
    -- el bus de datos de memoria y las entradas/salidas de la ALU.
    subtype data_vector is std_logic_vector(MSB_DATA downto 0);

    -- Vector de dirección de 16 bits: representa una dirección del espacio de 64 KB.
    -- Usado en el PC, el SP, el EAR (Effective Address Register) y el bus de direcciones.
    subtype address_vector is std_logic_vector(MSB_ADDRESS downto 0);

    -- Vector de opcode de 5 bits: selecciona una de las 32 operaciones de la ALU.
    -- Conecta la salida del decodificador de instrucciones con la entrada Oper de la ALU.
    subtype opcode_vector is std_logic_vector(MSB_OPCODE downto 0);

    -- Vector de estado de 8 bits: contiene los 8 flags del procesador (C,H,V,Z,G,E,R,L).
    -- Usado como tipo del registro F y de las salidas de flags de la ALU y del AddressPath.
    subtype status_vector is std_logic_vector(MSB_STATUS downto 0);

    -- Nibble de 4 bits: mitad inferior (o superior) de un byte de datos.
    -- Usado exclusivamente en el cálculo del Half-Carry (fH) para detectar
    -- el acarreo entre los bits [3:0] y [4:7] del resultado de una suma.
    subtype nibble_data is std_logic_vector(MSB_NIBBLE downto 0);

    -- =========================================================================
    -- Variantes numéricas (unsigned/signed) de los tipos base
    -- =========================================================================
    -- Se definen para operaciones aritméticas donde el tipo importa (multiplicación,
    -- comparaciones con signo, desplazamientos aritméticos).

    -- Dato sin signo de 8 bits: usado en sumas, restas y multiplicación sin signo.
    subtype unsigned_data_vector is unsigned(MSB_DATA downto 0);

    -- Dato con signo de 8 bits (complemento a 2): usado en comparaciones signed (fG)
    -- y en el desplazamiento aritmético derecho (ASR) que preserva el bit de signo.
    subtype signed_data_vector is signed(MSB_DATA downto 0);

    -- Dirección sin signo de 16 bits: usada en el sumador EA y en el PC como entero.
    subtype unsigned_address_vector is unsigned(MSB_ADDRESS downto 0);

    -- Dirección con signo de 16 bits: usada en el sumador EA para desplazamientos
    -- relativos con signo (saltos relativos rel8 extendidos a 16 bits).
    subtype signed_address_vector is signed(MSB_ADDRESS downto 0);

    -- Nibble sin signo de 4 bits: para calcular el carry del nibble bajo en half-carry.
    subtype unsigned_nibble is unsigned(MSB_NIBBLE downto 0);

    -- Dato extendido con signo de 9 bits: el bit extra (bit 8) recibe el carry/borrow
    -- de la suma completa, permitiendo detectar tanto overflow sin signo (carry) como
    -- overflow con signo (diferencia entre bit 7 del resultado y el carry de bit 7).
    subtype signed_extended_data_vector is signed(MSB_EXTENDED_DATA downto 0);

    -- Nibble extendido sin signo de 5 bits: el bit extra (bit 4) captura el carry
    -- del nibble bajo, que se mapea directamente al flag Half-Carry (fH).
    subtype unsigned_extended_nibble is unsigned(MSB_EXTENDED_NIBBLE downto 0);

    -- =========================================================================
    -- Tipos para resultados de doble ancho (Multiplicación 16 bits)
    -- =========================================================================
    -- La multiplicación de dos operandos de 8 bits produce hasta 16 bits de resultado.
    -- Se necesitan dos ciclos/instrucciones para obtener el byte bajo (MUL) y el alto (MUH).

    -- Vector de 16 bits sin tipo numérico: para almacenar el producto completo.
    subtype double_data_vector is std_logic_vector(MSB_DOUBLE_DATA downto 0);

    -- Producto de 16 bits sin signo: usado internamente en la ALU para la multiplicación.
    subtype unsigned_double_data_vector is unsigned(MSB_DOUBLE_DATA downto 0);

    -- Byte alto del producto (bits [15:8]): retornado por OP_MUH.
    -- El sufijo _H indica que es la mitad superior del resultado de 16 bits.
    subtype unsigned_double_data_vector_H is unsigned(MSB_DOUBLE_DATA downto DATA_WIDTH);

    -- Byte bajo del producto (bits [7:0]): retornado por OP_MUL.
    -- El sufijo _L indica que es la mitad inferior del resultado de 16 bits.
    subtype unsigned_double_data_vector_L is unsigned(MSB_DATA downto 0);

    -- =========================================================================
    -- Tipo de retorno para funciones de la ALU: par (Valor, Flags)
    -- =========================================================================
    -- Agrupar el resultado y los flags en un record permite que las funciones de
    -- la ALU retornen ambos valores atómicamente, simplificando el código del testbench
    -- y del componente ALU (no se necesitan parámetros out separados en funciones puras).
    type alu_result_record is record
        -- acc: resultado de la operación aritmética o lógica (8 bits).
        -- En OP_CMP este campo se descarta; la UC no escribe Write_A para esa instrucción.
        acc    : data_vector;

        -- status: flags generados por la operación, codificados en 8 bits.
        -- El registro F del procesador se actualiza con estos flags filtrados por Flag_Mask.
        status : status_vector;
    end record;

    -- =========================================================================
    -- Índices de los flags en el registro de estado (status_vector)
    -- =========================================================================
    -- Orden de bits: [7]=C, [6]=H, [5]=V, [4]=Z, [3]=G, [2]=E, [1]=R, [0]=L
    -- Mnemónico: C H V Z G E R L
    --
    -- Los índices se definen como constantes enteras para usar en expresiones
    -- de indexación: status(idx_fC) en lugar del literal "7" (menos legible).

    -- Carry / NOT Borrow (bit 7 del registro de estado).
    -- En sumas (ADD, ADC): '1' si hay acarreo de salida del bit 7 (resultado > 0xFF).
    -- En restas (SUB, SBB): '1' si NO hay borrow, convención ARM/VHDL (C = NOT borrow).
    -- También captura el bit desplazado fuera en LSL/ASL (bit 7 antes del desplazamiento).
    constant idx_fC : integer := 7; -- Carry / Borrow

    -- Half-Carry (bit 6): acarreo del nibble bajo al nibble alto (bits 3 → 4).
    -- Se activa cuando la suma de los nibbles bajos (bits [3:0]) produce carry.
    -- Usado principalmente en ajuste BCD (Binary-Coded Decimal) para aritmética decimal.
    constant idx_fH : integer := 6; -- Half-Carry

    -- Overflow con signo (bit 5): desbordamiento en aritmética de complemento a 2.
    -- Se activa cuando el resultado no puede representarse en 8 bits con signo
    -- (rango -128..+127). Detectado comparando el carry del bit 6 con el del bit 7.
    -- En ASL también se activa si el desplazamiento cambia el bit de signo (bit 7).
    constant idx_fV : integer := 5; -- Overflow

    -- Zero (bit 4): el resultado de la operación es exactamente 0x00.
    -- Calculado como NOR de todos los bits del resultado.
    -- Usado en ramificaciones condicionales (BEQ, BNE) y en CMP.
    constant idx_fZ : integer := 4; -- Zero

    -- Greater signed (bit 3): A > B en aritmética con signo (complemento a 2).
    -- Calculado siempre (incluido en OP_CMP), no solo en comparaciones explícitas.
    -- Equivalente a: (A - B) > 0 con signo, es decir, NOT(fZ) AND NOT(fV XOR fC_sign).
    constant idx_fG : integer := 3; -- Greater

    -- Equal (bit 2): A = B byte a byte (comparación bit a bit exacta).
    -- Calculado siempre. Equivalente a fZ del resultado de A XOR B (o A - B).
    -- Activo también en OP_CMP cuando A y B son idénticos.
    constant idx_fE : integer := 2; -- Equal

    -- Bit desplazado hacia la derecha (bit 1): valor del bit 0 de A antes de LSR/ASR/ROR.
    -- Captura el bit que "sale" por la derecha durante operaciones de desplazamiento.
    -- Permite recuperar el bit perdido o encadenar desplazamientos de precisión múltiple.
    constant idx_fR : integer := 1; -- Rotated/Shifted bit (Right)

    -- Bit desplazado hacia la izquierda (bit 0): valor del bit 7 de A antes de LSL/ASL/ROL.
    -- Captura el bit que "sale" por la izquierda durante operaciones de desplazamiento.
    -- Útil para encadenar desplazamientos o detectar el bit de signo original.
    constant idx_fL : integer := 0; -- Rotated/Shifted bit (Left)

    -- =========================================================================
    -- Constantes de opcode de la ALU (opcode_vector de 5 bits)
    -- =========================================================================
    -- Cada constante selecciona una operación distinta en el componente ALU_comp.
    -- Los códigos son continuos para simplificar la implementación (case statement).
    -- Los códigos 11100..11111 están reservados para expansiones futuras.

    -- No Operation: ACC = 0x00, flags no significativos.
    -- Usado en el estado de reset y en ciclos de fetch sin operación ALU.
    constant OP_NOP  : opcode_vector := b"00000"; -- No Operation

    -- ADD sin carry: ACC = A + B, genera fC, fH, fV, fZ.
    -- Suma sin signo estándar; el carry de entrada se ignora (Cin forzado a 0).
    constant OP_ADD  : opcode_vector := b"00001"; -- ADD

    -- ADD con carry: ACC = A + B + Cin, genera fC, fH, fV, fZ.
    -- Permite encadenar sumas de precisión múltiple usando el Cin desde el flag fC anterior.
    constant OP_ADC  : opcode_vector := b"00010"; -- ADD with Carry

    -- SUBtract sin borrow: ACC = A - B, genera fC (NOT borrow), fH, fV, fZ.
    -- El borrow de entrada se ignora (Cin forzado a 0). Convención: fC='1' ⇒ no hubo borrow.
    constant OP_SUB  : opcode_vector := b"00011"; -- SUBtract

    -- SUBtract con borrow: ACC = A - B - Cin, genera fC (NOT borrow), fH, fV, fZ.
    -- Permite encadenar restas de precisión múltiple; Cin proviene del flag fC anterior.
    constant OP_SBB  : opcode_vector := b"00100"; -- SUBtract with Borrow

    -- Logical Shift Left: ACC = A << 1, bit 0 = '0', bit 7 saliente → fC y fL.
    -- El bit más significativo (bit 7) se captura en fL antes del desplazamiento.
    -- Equivale a multiplicar por 2 (sin signo); no detecta cambio de signo (usar ASL).
    constant OP_LSL  : opcode_vector := b"00101"; -- Logical Shift Left

    -- Logical Shift Right: ACC = A >> 1, bit 7 = '0', bit 0 saliente → fR.
    -- El bit menos significativo (bit 0) se captura en fR antes del desplazamiento.
    -- Equivale a dividir por 2 (sin signo, siempre positivo).
    constant OP_LSR  : opcode_vector := b"00110"; -- Logical Shift Right

    -- ROtate Left circular: ACC = A rotado izquierda, bit 7 → bit 0.
    -- A diferencia de LSL, el bit 7 que sale por la izquierda reingressa por bit 0.
    -- No pasa por el flag carry; rotación puramente circular de 8 bits.
    constant OP_ROL  : opcode_vector := b"00111"; -- Rotate Left

    -- ROtate Right circular: ACC = A rotado derecha, bit 0 → bit 7.
    -- El bit 0 que sale por la derecha reingressa por bit 7.
    -- No pasa por el flag carry; rotación puramente circular de 8 bits.
    constant OP_ROR  : opcode_vector := b"01000"; -- Rotate Right

    -- INCrement A: ACC = A + 1, genera fV, fZ (no genera fC).
    -- El carry no se actualiza en INC para no perturbar sumas de precisión múltiple
    -- donde INC se usa como paso auxiliar.
    constant OP_INC  : opcode_vector := b"01001"; -- Increment A

    -- DECrement A: ACC = A - 1, genera fV, fZ (no genera fC).
    -- Igual que INC, el carry no se actualiza para permitir uso en bucles de precisión múltiple.
    constant OP_DEC  : opcode_vector := b"01010"; -- Decrement A

    -- AND lógico: ACC = A AND B, bit a bit. Genera fZ; limpia fC, fV.
    -- Usado para enmascarar bits (seleccionar campos dentro de un byte).
    constant OP_AND  : opcode_vector := b"01011"; -- AND

    -- OR Inclusivo: ACC = A OR B, bit a bit. Genera fZ; limpia fC, fV.
    -- Usado para activar bits individuales de un registro.
    constant OP_IOR  : opcode_vector := b"01100"; -- OR (Inclusive OR)

    -- XOR: ACC = A XOR B, bit a bit. Genera fZ; limpia fC, fV.
    -- Usado para invertir bits seleccionados o comparar bytes (resultado=0 si A=B).
    constant OP_XOR  : opcode_vector := b"01101"; -- XOR

    -- NOT A (complemento a uno): ACC = NOT A, bit a bit. Genera fZ.
    -- Invierte todos los bits de A. Para complemento a dos usar OP_NEG.
    constant OP_NOT  : opcode_vector := b"01110"; -- NOT A

    -- Arithmetic Shift Left: ACC = A << 1, bit 0 = '0', bit 7 saliente → fC y fL.
    -- Idéntico a LSL en el desplazamiento, pero adicionalmente activa fV si el bit 7
    -- del resultado difiere del bit 7 original (cambio de signo en complemento a 2).
    constant OP_ASL  : opcode_vector := b"01111"; -- Arithmetic Shift Left

    -- NEGate (complemento a dos): ACC = 0x00 - A = ~A + 1.
    -- Equivale a negar el valor con signo. Si A=0x80 (−128), NEG produce overflow (fV='1').
    constant OP_NEG  : opcode_vector := b"10000"; -- NEG A (two's complement)

    -- PaSs A: ACC = A sin modificar. Genera fZ para reflejar si A es cero.
    -- Útil para mover el valor de A al bus de escritura sin alterar flags importantes,
    -- o para actualizar fZ basado en el contenido actual de A.
    constant OP_PSA  : opcode_vector := b"10001"; -- Pass A

    -- PaSs B: ACC = B sin modificar. Genera fZ para reflejar si B es cero.
    -- Permite enrutar B hacia el bus de escritura del DataPath con la misma lógica que PSA.
    constant OP_PSB  : opcode_vector := b"10010"; -- Pass B

    -- CLeaR acumulador: ACC = 0x00, fZ='1', fC='0', fV='0'.
    -- Pone el acumulador a cero sin necesidad de XOR A,A o SUB A,A.
    constant OP_CLR  : opcode_vector := b"10011"; -- Clear ACC

    -- SET acumulador: ACC = 0xFF, fZ='0'.
    -- Pone el acumulador a todos unos; equivalente a NOT(CLR) sin operando.
    constant OP_SET  : opcode_vector := b"10100"; -- Set ACC

    -- MULtiply Low: ACC = (A × B)[7:0], byte bajo del producto de 8×8 bits.
    -- El resultado completo de 16 bits se calcula internamente; solo se retorna la mitad baja.
    -- Para obtener el byte alto usar OP_MUH en un ciclo separado.
    constant OP_MUL  : opcode_vector := b"10101"; -- Multiply Low

    -- MUltiply High: ACC = (A × B)[15:8], byte alto del producto de 8×8 bits.
    -- Se repite el cálculo del producto; la UC debe garantizar que A y B no cambien entre MUL y MUH.
    constant OP_MUH  : opcode_vector := b"10110"; -- Multiply High

    -- CoMPare: calcula A - B para actualizar flags (fC, fH, fV, fZ, fG, fE),
    -- pero NO escribe el resultado en el ACC ni en ningún registro.
    -- La UC activa Write_F='1' pero mantiene Write_A='0' para este opcode.
    constant OP_CMP  : opcode_vector := b"10111"; -- Compare

    -- Arithmetic Shift Right: ACC = A >> 1, bit 7 = bit 7 original (signo preservado).
    -- El bit 0 que sale por la derecha se captura en fR.
    -- Equivale a dividir por 2 con signo (redondeo hacia −∞).
    constant OP_ASR  : opcode_vector := b"11000"; -- Arithmetic Shift Right

    -- SWaP nibbles: ACC = {A[3:0], A[7:4]}, intercambia nibble bajo con nibble alto.
    -- Útil en rutinas BCD, hash y codificación; no altera el valor numérico si A es palíndromo.
    constant OP_SWP  : opcode_vector := b"11001"; -- Swap Nibbles

    -- INcrement B: ACC = B + 1 (el resultado aparece en ACC).
    -- La UC enruta este resultado de vuelta al registro B mediante Write_B='1'.
    -- Permite incrementar B sin pasar por el acumulador A como efecto lateral.
    constant OP_INB  : opcode_vector := b"11010"; -- Increment B (result → ACC)

    -- DEcrement B: ACC = B - 1 (el resultado aparece en ACC).
    -- Igual que INB, la UC lo enruta a B con Write_B='1'.
    -- Permite decrementar B preservando el contenido de A.
    constant OP_DEB  : opcode_vector := b"11011"; -- Decrement B (result → ACC)

    -- Reservados: 11100, 11101, 11110, 11111
    -- Estos cuatro códigos no están asignados y producirán comportamiento indefinido
    -- si se utilizan. Reservados para futuras extensiones del conjunto de instrucciones.

    -- =========================================================================
    -- Declaración centralizada del componente ALU
    -- =========================================================================
    -- Se declara aquí para que cualquier entidad que use ALU_pkg pueda instanciar
    -- la ALU sin necesidad de declarar el componente localmente.
    component ALU_comp is
        Port (
            RegInA    : in  data_vector;    -- Operando A (generalmente R0/Acumulador)
            RegInB    : in  data_vector;    -- Operando B (registro o inmediato vía MDR)
            Oper      : in  opcode_vector;  -- Código de operación (selecciona la función ALU)
            Carry_in  : in  STD_LOGIC := '0'; -- Flag Carry de entrada (usado en ADC, SBB)
            RegOutACC : out data_vector;    -- Resultado de la operación (8 bits)
            RegStatus : out status_vector   -- Flags generados: C,H,V,Z,G,E,R,L
        );
    end component ALU_comp;

end package ALU_pkg;
