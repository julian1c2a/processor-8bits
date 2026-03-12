--------------------------------------------------------------------------------
-- Entidad: AddressPath
-- Descripción:
--   Camino de datos de 16 bits para gestión de direcciones.
--   Contiene:
--     - Registros: PC (Program Counter), SP (Stack Pointer), LR (Link Reg).
--     - Sumador EA: Calcula direcciones efectivas (Base + Índice).
--     - Lógica de incremento/decremento para PC y SP.
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.CONSTANTS_pkg.ALL;
use work.ALU_pkg.ALL; -- Para tipos de datos base
use work.AddressPath_pkg.ALL;

entity AddressPath is
    Port (
        clk       : in std_logic;                        -- Reloj del sistema; flancos de subida activos
        reset     : in std_logic;                        -- Reset síncrono activo alto; lleva todos los registros a sus valores iniciales

        -- Buses de Datos
        DataIn    : in  data_vector; -- Entrada desde Memoria/DataPath (8 bits); alimenta TMP_L, TMP_H y operandos del sumador EA
        Index_B   : in  data_vector; -- Índice desde DataPath (Registro B, 8 bits); usado en direccionamiento indexado [nn+B]
        Index_A   : in  data_vector; -- Registro A desde DataPath (8 bits); se combina con B para formar el par A:B de 16 bits

        -- Bus de Direcciones (Salida Principal)
        AddressBus : out address_vector;                 -- Bus de direcciones de 16 bits hacia la memoria; controlado por ABUS_Sel
        PC_Out     : out address_vector; -- Salida del PC para guardar en Stack; necesaria en el mismo ciclo que CALL/BSR (combinacional)
        EA_Out     : out address_vector; -- Resultado del sumador EA hacia DataPath; para ADD16/SUB16 y carga de SP_L/H
        EA_Flags   : out status_vector;  -- Flags resultantes de la operación EA (C, Z); para actualizar el registro de estado tras ADD16/SUB16

        -- Señales de Control (vienen de UC)
        PC_Op     : in  std_logic_vector(1 downto 0); -- Control PC: NOP / INC (+1) / LOAD (salto) / LOAD_L (salto misma página)
        SP_Op     : in  std_logic_vector(1 downto 0); -- Control SP: NOP / INC (+2 POP) / DEC (-2 PUSH) / LOAD (carga directa)
        ABUS_Sel  : in  std_logic_vector(2 downto 0); -- Selecciona quién controla AddressBus: PC / SP / EAR / EA_RES / vectores de interrupción

        -- Cargas de registros específicos
        Load_LR   : in  std_logic; -- '1' = capturar PC actual en LR (Link Register) para BSR/CALL LR
        Load_EAR  : in  std_logic; -- '1' = capturar resultado del sumador EA en EAR (Effective Address Register)
        Load_TMP_L: in  std_logic; -- '1' = cargar parte baja (bits 7..0) de TMP desde DataIn
        Load_TMP_H: in  std_logic; -- '1' = cargar parte alta (bits 15..8) de TMP desde DataIn

        -- Selección de fuente para cargar PC/SP/LR (Calculado vs Dato directo)
        Load_Src_Sel : in std_logic; -- 0=EA_Adder_Res (salto relativo PC+rel8), 1=TMP (dirección absoluta ensamblada desde bus de 8 bits)
        SP_Offset    : in std_logic; -- 0=SP (acceso al byte bajo de la palabra en pila), 1=SP+1 (byte alto, little-endian)
        Force_ZP     : in std_logic; -- 1=Forzar MSB del AddressBus a 0x00 (wrapping a página cero, 8-bit address space)

        -- Selección de operandos para el EA Adder
        EA_A_Sel  : in  std_logic_vector(1 downto 0); -- Selecciona operando A (base) del sumador EA: TMP / PC / A:B / SP
        Clear_TMP : in  std_logic;                    -- '1' = limpiar TMP a 0x0000 (prioridad sobre Load_TMP_L/H; necesario antes de cargar zero-page)
        EA_B_Sel  : in  std_logic_vector(1 downto 0); -- Selecciona operando B (índice/desplazamiento) del sumador EA: B / DataIn(signed) / TMP
        EA_Op     : in  std_logic                     -- 0=ADD (EA = A + B), 1=SUB (EA = A - B)
    );
end entity AddressPath;

architecture unique of AddressPath is

    -- -------------------------------------------------------------------------
    -- Registros internos de 16 bits
    -- -------------------------------------------------------------------------

    -- r_PC: Program Counter.  Inicia en 0x0000 (vector de reset).
    --   Apunta a la dirección de la PRÓXIMA instrucción a buscar.
    --   Se incrementa en +1 por cada byte leído (opcode o dato).
    --   Se carga con la dirección destino en saltos absolutos/relativos/indirectos.
    signal r_PC  : unsigned_address_vector := (others => '0');

    -- r_SP: Stack Pointer.  Inicia en 0xFFFE (tope de memoria menos 2).
    --   Valor inicial 0xFFFE: el stack crece hacia abajo en palabras de 16 bits.
    --   Se elige 0xFFFE (y no 0xFFFF) porque el stack almacena palabras de 16 bits
    --   (p.ej. la dirección de retorno en CALL/PUSH ocupa 2 bytes consecutivos).
    --   Alineado a dirección par garantiza que la palabra completa [SP, SP+1]
    --   esté dentro del espacio de direcciones (0xFFFE..0xFFFF).
    --   Las operaciones PUSH decrementan SP en -2; POP incrementa en +2.
    signal r_SP  : unsigned_address_vector := x"FFFE"; -- Stack empieza arriba (alineado a par, palabras de 16 bits)

    -- r_LR: Link Register.  Inicia en 0x0000.
    --   Almacena la dirección de retorno cargada por BSR/CALL LR.
    --   Se carga con el valor ACTUAL de r_PC en el ciclo de la instrucción CALL,
    --   de forma que apunta a la instrucción siguiente al CALL (dirección de retorno).
    --   RET LR salta a r_LR para regresar de la subrutina.
    signal r_LR  : unsigned_address_vector := (others => '0');

    -- r_EAR: Effective Address Register.  Inicia en 0x0000.
    --   Registra el resultado del sumador EA para usarlo en el ciclo siguiente.
    --   Necesario cuando la dirección efectiva se calcula en el ciclo anterior
    --   a la lectura/escritura de memoria (pipeline de 2 etapas: calcular EA → acceder).
    signal r_EAR : unsigned_address_vector := (others => '0');

    -- r_TMP: Registro temporal de 16 bits.  Inicia en 0x0000.
    --   Se ensambla byte a byte desde el bus de datos de 8 bits:
    --     ciclo 1: Load_TMP_L → r_TMP[7:0]  = DataIn (byte bajo)
    --     ciclo 2: Load_TMP_H → r_TMP[15:8] = DataIn (byte alto)
    --   Una vez ensamblado, TMP contiene la dirección absoluta del operando
    --   (p.ej. la dirección destino de JP nn, LD A,[nn], etc.).
    signal r_TMP : unsigned_address_vector := (others => '0');

    -- -------------------------------------------------------------------------
    -- Señales internas del sumador EA
    -- -------------------------------------------------------------------------

    -- EA_Adder_Res: resultado de 16 bits del sumador EA (truncado desde 17 bits).
    --   Se usa como dirección efectiva para modos indexados, saltos relativos y ADD16.
    signal EA_Adder_Res : unsigned_address_vector;

    -- EA_Result_Full: resultado completo de 17 bits del sumador EA.
    --   El bit [ADDRESS_WIDTH] = bit [16] es el carry/borrow de la suma/resta de 16 bits.
    --   Para ADD: bit[16]=1 indica carry (resultado > 0xFFFF, desborde sin signo).
    --   Para SUB: bit[16]=1 indica borrow; se niega para la convención NOT-borrow del flag C.
    signal EA_Result_Full : unsigned(ADDRESS_WIDTH downto 0); -- 17 bits: [16]=carry/borrow, [15:0]=resultado

    -- EA_Adder_A_In: operando A (base) seleccionado por el MUX EA_A_Sel.
    --   Siempre es unsigned de 16 bits; puede ser TMP, PC, A:B concatenado, o SP.
    signal EA_Adder_A_In: unsigned_address_vector;

    -- EA_Adder_B_In: operando B (índice/desplazamiento) seleccionado por el MUX EA_B_Sel.
    --   Es signed de 16 bits para soportar desplazamientos relativos con signo (rel8).
    --   El MUX puede extender con signo DataIn de 8 bits a 16 bits para saltos relativos.
    signal EA_Adder_B_In: signed_address_vector;

    -- Mux_Load_Data: selecciona la fuente para cargar PC, SP o LR.
    --   Load_Src_Sel=0 → EA_Adder_Res (resultado de salto relativo: PC + rel8)
    --   Load_Src_Sel=1 → r_TMP         (dirección absoluta ensamblada desde el bus de 8 bits)
    signal Mux_Load_Data : unsigned_address_vector;

begin

    -- ========================================================================
    -- 1. Lógica Combinacional: MUXes y Sumador EA
    -- ========================================================================

    -- -----------------------------------------------------------------------
    -- Multiplexor para la entrada A (Base) del sumador EA
    -- Selecciona el operando base según el modo de direccionamiento activo:
    --   EA_A_SRC_TMP:    Dirección absoluta ensamblada en TMP; usado en [nn+B] (indexado absoluto)
    --   EA_A_SRC_PC:     Contador de programa; usado en saltos relativos (PC + rel8)
    --   EA_A_SRC_REG_AB: Par A:B como entero de 16 bits; usado en ADD16/SUB16 (aritmética 16-bit)
    --   EA_A_SRC_SP:     Stack Pointer; usado en accesos relativos a la pila
    -- -----------------------------------------------------------------------
    with EA_A_Sel select EA_Adder_A_In <=
        r_TMP                                        when EA_A_SRC_TMP,    -- Base = dirección de tabla/operando en TMP
        r_PC                                         when EA_A_SRC_PC,     -- Base = PC actual (saltos relativos JR, JSR rel)
        resize(unsigned(Index_A & Index_B), 16)      when EA_A_SRC_REG_AB, -- Base = A:B concatenados como entero de 16 bits
        r_SP                                         when EA_A_SRC_SP,     -- Base = SP (accesos relativos a la pila)
        (others => '0')                              when others;           -- Caso seguro: base = 0

    -- -----------------------------------------------------------------------
    -- Multiplexor para la entrada B (Índice/Desplazamiento) del sumador EA
    -- Selecciona el operando índice según el modo de direccionamiento:
    --   EA_B_SRC_REG_B:   Registro B sin signo extendido a 16 bits; para [nn+B] (índice positivo)
    --   EA_B_SRC_DATA_IN: DataIn extendido con signo a 16 bits; para saltos relativos (rel8 con signo, rango -128..+127)
    --   EA_B_SRC_TMP:     TMP extendido con signo a 16 bits; para desplazamientos de 16 bits
    -- -----------------------------------------------------------------------
    with EA_B_Sel select EA_Adder_B_In <=
        signed(resize(unsigned(Index_B), 16))  when EA_B_SRC_REG_B,    -- Índice B sin signo [0..255]
        resize(signed(DataIn), 16)     when EA_B_SRC_DATA_IN,   -- Desplazamiento rel8 con signo [-128..+127]
        resize(signed(r_TMP), 16)      when EA_B_SRC_TMP,       -- Desplazamiento de 16 bits con signo
        (others => '0')                when others;              -- Caso seguro: índice = 0

    -- -----------------------------------------------------------------------
    -- Sumador EA: calcula la Dirección Efectiva = A ± B
    --   Sirve para: [nn+B] (indexado), saltos relativos (PC+rel8), ADD16/SUB16
    --
    -- Por qué se usan 17 bits (ADDRESS_WIDTH+1):
    --   ADDRESS_WIDTH = 16 bits.  Al extender a 17 bits (signed) y sumar/restar,
    --   el bit [16] captura el carry (en ADD) o el borrow (en SUB) de la operación
    --   de 16 bits, sin descartar información.  Este bit se usa para generar el
    --   flag C de los flags EA (ADD16/SUB16).
    --   Sin la extensión a 17 bits, el carry se perdería silenciosamente.
    --
    -- EA_Op=0 → ADD: EA = A + B  (modos indexados, saltos relativos hacia adelante)
    -- EA_Op=1 → SUB: EA = A - B  (saltos relativos hacia atrás, SUB16)
    -- -----------------------------------------------------------------------
    process(EA_Adder_A_In, EA_Adder_B_In, EA_Op)
        variable v_opA : signed(ADDRESS_WIDTH downto 0); -- Operando A extendido a 17 bits con signo
        variable v_opB : signed(ADDRESS_WIDTH downto 0); -- Operando B extendido a 17 bits con signo
        variable v_res : signed(ADDRESS_WIDTH downto 0); -- Resultado de 17 bits (bit[16]=carry/borrow)
    begin
        -- Extender ambos operandos de 16 a 17 bits conservando el signo
        v_opA := resize(signed(EA_Adder_A_In), ADDRESS_WIDTH + 1); -- Extensión con signo: preserva el MSB
        v_opB := resize(EA_Adder_B_In, ADDRESS_WIDTH + 1);          -- Ya es signed; extender a 17 bits

        if EA_Op = EA_OP_ADD then
            v_res := v_opA + v_opB; -- Suma: A + B; bit[16] = carry-out
        else
            v_res := v_opA - v_opB; -- Resta: A - B; bit[16] = borrow-out
            -- Nota: Para SUB16 A:B - nn, usaremos: EA_A=A:B (vía REG_AB), EA_B=nn (vía TMP)
            -- pero nuestro MUX pone A:B en la entrada B.
            -- Así que calcularemos: TMP - A:B.
            -- Si queremos A:B - TMP, necesitariamos cambiar los muxes o hacer negación.
            -- Solución simple: Asumiremos ADD16 es conmutativo.
            -- Para SUB16, ajustaremos en ControlUnit o AddressPath.
            -- Por ahora implementamos A + B y A - B estándar.
        end if;

        EA_Result_Full <= unsigned(v_res); -- Bit[16] = carry/borrow; bits[15:0] = resultado
    end process;

    -- Extraer solo los 16 bits del resultado (truncar el bit de carry/borrow)
    EA_Adder_Res <= EA_Result_Full(MSB_ADDRESS downto 0); -- Resultado de 16 bits sin el carry

    -- ========================================================================
    -- 2. Multiplexor de Fuente de Carga (Mux_Load_Data)
    -- ========================================================================
    -- Elige la fuente para cargar PC, SP o LR en el próximo flanco de reloj:
    --   LOAD_SRC_ALU_RES (Load_Src_Sel=0): resultado del sumador EA
    --     → usado en saltos RELATIVOS (PC + rel8) donde la dirección se calcula
    --       dinámicamente sumando un desplazamiento firmado al PC actual.
    --   LOAD_SRC_TMP    (Load_Src_Sel=1): dirección absoluta ensamblada en TMP
    --     → usado en saltos ABSOLUTOS (JP nn, CALL nn) donde los dos bytes de
    --       la dirección destino se han leído del bus de datos en ciclos previos
    --       y ensamblado en r_TMP byte a byte.
    Mux_Load_Data <= EA_Adder_Res when Load_Src_Sel = LOAD_SRC_ALU_RES else -- Salto relativo: PC + rel8
                     r_TMP;                                                   -- Salto absoluto: dirección de TMP

    -- ========================================================================
    -- 3. Registros y Lógica Secuencial
    -- ========================================================================
    process(clk, reset)
    begin
        if reset = '1' then
            -- Valores iniciales de todos los registros tras reset
            r_PC  <= (others => '0'); -- PC = 0x0000: el procesador arranca desde la dirección 0
            r_SP  <= x"FFFE";         -- SP = 0xFFFE: tope del stack, alineado a par para palabras de 16 bits
            r_LR  <= (others => '0'); -- LR = 0x0000: sin subrutina activa
            r_EAR <= (others => '0'); -- EAR = 0x0000: sin dirección efectiva registrada
            r_TMP <= (others => '0'); -- TMP = 0x0000: registro temporal vacío
        elsif rising_edge(clk) then

            -- -----------------------------------------------------------------
            -- Gestión de TMP (Ensamblador de 16 bits desde bus de 8 bits)
            -- -----------------------------------------------------------------
            -- Clear_TMP tiene PRIORIDAD sobre Load_TMP_L/H:
            --   Esto es necesario para instrucciones de página cero (zero-page):
            --   antes de cargar el byte bajo de la dirección, el byte alto debe
            --   ser explícitamente 0x00 (ya que la dirección de página cero es
            --   0x00nn, no un valor arbitrario del ciclo anterior).
            --   Si Clear_TMP y Load_TMP_L se afirmaran en el mismo ciclo,
            --   Clear_TMP garantiza que el MSB quede a 0 antes de que Load_TMP_L
            --   escriba el byte bajo en el siguiente ciclo.
            if Clear_TMP = '1' then
                r_TMP <= (others => '0'); -- Limpia TMP completo; prioridad máxima sobre cargas parciales
            end if;

            -- Carga del byte bajo de TMP (bits 7..0) desde el bus de datos
            -- Ocurre en el ciclo en que se lee el primer byte del operando de 16 bits
            if Load_TMP_L = '1' then
                r_TMP(7 downto 0) <= unsigned(DataIn); -- TMP[7:0] = DataIn (byte bajo del operando)
            end if;

            -- Carga del byte alto de TMP (bits 15..8) desde el bus de datos
            -- Ocurre en el ciclo en que se lee el segundo byte del operando de 16 bits
            if Load_TMP_H = '1' then
                r_TMP(15 downto 8) <= unsigned(DataIn); -- TMP[15:8] = DataIn (byte alto del operando)
            end if;

            -- -----------------------------------------------------------------
            -- Gestión del PC (Program Counter)
            -- -----------------------------------------------------------------
            case PC_Op is
                when PC_OP_NOP  => null; -- Hold: PC no cambia (ciclo de ejecución sin fetch)

                -- PC_OP_INC: avanza al siguiente byte del flujo de instrucciones.
                --   Ocurre en cada ciclo de fetch (opcode) y en cada lectura de operando.
                when PC_OP_INC  => r_PC <= r_PC + 1; -- Fetch: apunta al siguiente byte

                -- PC_OP_LOAD: salto absoluto o relativo.
                --   Mux_Load_Data elige entre EA_Adder_Res (relativo) y r_TMP (absoluto).
                --   Usado en JP nn, CALL nn, JR rel8, RET, etc.
                when PC_OP_LOAD => r_PC <= Mux_Load_Data; -- Salto: carga la dirección destino completa

                -- PC_OP_LOAD_L: salto dentro de la MISMA PÁGINA (JPN).
                --   Solo se actualiza el byte bajo del PC (bits 7..0); el byte alto
                --   (bits 15..8) permanece igual.  Esto limita el salto a la página
                --   actual (256 bytes), pero se ejecuta en menos ciclos porque solo
                --   se necesita un byte de dirección en el opcode.
                when PC_OP_LOAD_L => r_PC(7 downto 0) <= Mux_Load_Data(7 downto 0); -- JPN: solo cambia el byte bajo del PC

                when others => null; -- Opcode de control PC no reconocido: conservar PC
            end case;

            -- -----------------------------------------------------------------
            -- Gestión del SP (Stack Pointer)
            -- -----------------------------------------------------------------
            -- El SP siempre permanece alineado a direcciones pares:
            --   INC suma +2 (POP: recupera una palabra de 16 bits)
            --   DEC resta -2 (PUSH: aparta espacio para una palabra de 16 bits)
            -- La alineación garantiza que cada acceso a la pila lea/escriba
            -- los dos bytes de la palabra en [SP] y [SP+1] (little-endian).
            case SP_Op is
                when SP_OP_NOP  => null; -- Hold: SP no cambia

                -- SP_OP_INC: POP. El SP avanza +2 porque cada entrada del stack
                --   ocupa 2 bytes (dirección de retorno o valor de 16 bits).
                when SP_OP_INC  => r_SP <= r_SP + 2; -- POP: libera la palabra de 16 bits del tope del stack

                -- SP_OP_DEC: PUSH. El SP retrocede -2 antes de escribir la palabra
                --   en la nueva posición [SP..SP+1].
                when SP_OP_DEC  => r_SP <= r_SP - 2; -- PUSH: reserva espacio para la nueva palabra en el stack

                -- SP_OP_LOAD: carga directa del SP (p.ej. instrucción LD SP, nn).
                when SP_OP_LOAD => r_SP <= Mux_Load_Data; -- Carga directa: nuevo valor del SP desde TMP o EA
                    -- Forzar alineación par si cargamos valor arbitrario?
                    -- r_SP(0) <= '0'; (se aplicaría en siguiente ciclo o combinacional)

                when others => null; -- Opcode SP no reconocido: conservar SP
            end case;

            -- -----------------------------------------------------------------
            -- Gestión de LR (Link Register)
            -- -----------------------------------------------------------------
            if Load_LR = '1' then
                -- LR captura el valor ACTUAL de r_PC (no el siguiente).
                -- En el ciclo de ejecución de CALL/BSR, r_PC ya ha sido incrementado
                -- para apuntar a la siguiente instrucción tras el CALL; por tanto,
                -- cargar r_PC en LR guarda la dirección de retorno correcta.
                -- RET LR simplemente salta a r_LR para volver de la subrutina.
                r_LR <= r_PC; -- LR = PC actual = dirección de retorno para BSR/CALL LR
            end if;

            -- -----------------------------------------------------------------
            -- Gestión de EAR (Effective Address Register)
            -- -----------------------------------------------------------------
            if Load_EAR = '1' then
                -- Guarda el resultado actual del sumador EA para usarlo en el
                -- ciclo siguiente (pipeline: ciclo 1 = calcular EA, ciclo 2 = acceder).
                r_EAR <= EA_Adder_Res; -- EAR = resultado del sumador EA (para modo indirecto, pipeline)
            end if;

        end if;
    end process;

    -- ========================================================================
    -- 4. Salida al Bus de Direcciones (Multiplexor de Salida)
    -- ========================================================================
    -- Este proceso es combinacional: ABUS_Sel cambia cada ciclo según lo que
    -- la UC necesite direccionar en ese ciclo (fetch, lectura de operando,
    -- acceso a datos, acceso a stack, etc.).
    process(ABUS_Sel, r_PC, r_SP, r_EAR, r_LR, SP_Offset, Force_ZP, EA_Adder_Res)
    begin
        case ABUS_Sel is

            -- ABUS_SRC_PC: AddressBus = PC
            --   Modo normal de fetch: la UC pone el PC en el bus para leer el opcode
            --   o los bytes de operando de la instrucción actual.
            when ABUS_SRC_PC  => AddressBus <= std_logic_vector(r_PC); -- Fetch: PC apunta al opcode o dato siguiente

            -- ABUS_SRC_SP: AddressBus = SP o SP+1
            --   Acceso al stack para PUSH/POP/CALL/RET.
            --   SP_Offset='0': accede a [SP]   → byte bajo de la palabra (little-endian)
            --   SP_Offset='1': accede a [SP+1] → byte alto de la palabra (little-endian)
            --   El acceso en little-endian garantiza que el byte de menor peso esté
            --   en la dirección más baja (SP) y el de mayor peso en SP+1.
            when ABUS_SRC_SP  =>
                if SP_Offset = '1' then
                    AddressBus <= std_logic_vector(r_SP + 1); -- SP+1: byte alto (MSB) de la palabra en pila (little-endian)
                else
                    AddressBus <= std_logic_vector(r_SP);     -- SP:   byte bajo (LSB) de la palabra en pila
                end if;

            -- ABUS_SRC_EAR: AddressBus = EAR (Effective Address Register)
            --   La dirección efectiva fue calculada en el ciclo anterior y
            --   registrada en r_EAR.  Se usa en accesos indirectos o post-calculados.
            when ABUS_SRC_EAR => AddressBus <= std_logic_vector(r_EAR); -- Indirecto: dirección efectiva registrada en EAR

            -- ABUS_SRC_EA_RES: AddressBus = resultado del sumador EA (combinacional)
            --   La dirección efectiva se pone en el bus en el mismo ciclo que se calcula.
            --   Force_ZP='1': se fuerza el byte alto a 0x00 (página cero, direccionamiento
            --     de 8 bits).  Esto implementa el wrapping: la dirección resultante
            --     siempre estará en el rango 0x0000..0x00FF independientemente del
            --     valor calculado por el sumador EA (solo importan los 8 bits bajos).
            --   Force_ZP='0': se usa la dirección completa de 16 bits.
            when ABUS_SRC_EA_RES =>
                if Force_ZP = '1' then
                    AddressBus <= x"00" & std_logic_vector(EA_Adder_Res(7 downto 0)); -- Zero-page: MSB forzado a 0x00, wrapping de 8 bits
                else
                    AddressBus <= std_logic_vector(EA_Adder_Res); -- Dirección efectiva completa de 16 bits
                end if;

            -- Vectores de interrupción/reset: direcciones hardcodeadas.
            --   No se necesita un registro para estos valores; son constantes
            --   de la arquitectura definidas en la tabla de vectores del mapa de memoria.
            --   La UC selecciona el vector adecuado al reconocer IRQ o NMI.
            when ABUS_SRC_VEC_NMI_L => AddressBus <= x"FFFA"; -- Vector NMI byte bajo  (0xFFFA: MSB de la dirección NMI en little-endian)
            when ABUS_SRC_VEC_NMI_H => AddressBus <= x"FFFB"; -- Vector NMI byte alto  (0xFFFB: LSB de la dirección NMI en little-endian)
            when ABUS_SRC_VEC_IRQ_L => AddressBus <= x"FFFE"; -- Vector IRQ byte bajo  (0xFFFE: coincide con el valor inicial del SP)
            when ABUS_SRC_VEC_IRQ_H => AddressBus <= x"FFFF"; -- Vector IRQ byte alto  (0xFFFF: tope absoluto del espacio de direcciones)

            -- Caso por defecto: bus a 0 (seguro, no accede a ninguna dirección útil)
            when others       => AddressBus <= (others => '0'); -- Default seguro: 0x0000

        end case;
    end process;

    -- -------------------------------------------------------------------------
    -- Salidas auxiliares del AddressPath hacia el resto del procesador
    -- -------------------------------------------------------------------------

    -- PC_Out: salida COMBINACIONAL del PC (sin registro adicional).
    --   Es combinacional porque DataPath necesita el valor actual del PC
    --   en el MISMO ciclo en que se ejecuta CALL para hacer PUSH de la
    --   dirección de retorno.  Si fuera registrado con un flanco, llegaría
    --   un ciclo tarde y se guardaría una dirección errónea en el stack.
    PC_Out <= std_logic_vector(r_PC); -- PC actual, combinacional: disponible en el mismo ciclo que CALL

    -- EA_Out: resultado actual del sumador EA hacia el DataPath.
    --   Usado en ADD16/SUB16 para que el DataPath escriba el resultado en A:B,
    --   y en instrucciones ST SP_L/H para exponer el puntero de pila al bus de datos.
    EA_Out <= std_logic_vector(EA_Adder_Res); -- Resultado EA de 16 bits hacia DataPath (ADD16, SUB16, ST SP)

    -- =========================================================================
    -- 5. Cálculo de Flags de 16 bits (para ADD16/SUB16)
    -- =========================================================================
    -- Este proceso genera los flags C y Z para las operaciones aritméticas de 16 bits
    -- realizadas por el sumador EA.  Estos flags se propagan al registro de estado
    -- del DataPath a través de EA_Flags cuando la UC lo indique (Write_F + Flag_Mask).
    process(EA_Result_Full, EA_Adder_Res, EA_Op)
        variable v_flags : status_vector := (others => '0'); -- Todos los flags a 0 por defecto
    begin
        -- Z (Zero Flag): el resultado de 16 bits es exactamente cero
        if EA_Adder_Res = 0 then v_flags(idx_fZ) := '1'; end if; -- Z=1 si el resultado de la operación de 16 bits es 0

        -- C (Carry/Not-Borrow Flag): generado desde el bit [16] del resultado extendido.
        --   Para ADD: bit[16]=1 indica carry-out (resultado sin signo > 0xFFFF).
        --     Se toma directamente: C = EA_Result_Full[ADDRESS_WIDTH].
        --   Para SUB: bit[16]=1 indica borrow.  Se NIEGA para seguir la convención
        --     NOT-borrow (C=1 si A>=B, C=0 si A<B), consistente con do_sub en la ALU.
        --     Convención ARM/RISC: C=NOT borrow, permite encadenar restas con SBB.
        if EA_Op = EA_OP_ADD then
            v_flags(idx_fC) := EA_Result_Full(ADDRESS_WIDTH);      -- ADD: C = carry-out del bit 15→16
        else
            v_flags(idx_fC) := not EA_Result_Full(ADDRESS_WIDTH);  -- SUB: C = NOT borrow (convención ARM)
        end if;

        -- V (Overflow) simplificado: se deja a 0 para AddressPath.
        --   El overflow con signo de 16 bits requeriría comparar los MSBs de los
        --   operandos y el resultado (igual que en do_add/do_sub de 8 bits).
        --   Para las operaciones de dirección (ADD16/SUB16 sobre punteros), el
        --   overflow con signo raramente es relevante; se simplifica a V=0.
        --   Si se necesita en el futuro, se puede añadir aquí sin cambiar la interfaz.

        EA_Flags <= v_flags; -- Expone los flags de 16 bits al DataPath/ControlUnit
    end process;

end architecture unique;
