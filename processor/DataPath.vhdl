--------------------------------------------------------------------------------
-- Entidad: DataPath
-- Descripción:
--   Implementa el camino de datos de 8 bits del procesador.
--   Contiene:
--     - Banco de Registros Unificado (8x8): R0 actúa como Acumulador (A).
--     - ALU: Realiza operaciones aritmético-lógicas.
--     - MDR: Registro de datos de memoria para sincronización.
--     - Lógica de Flags: Gestión de estado con escritura enmascarada.
--
--   Características clave:
--     - Permite usar cualquier registro (R0..R7) como operando B de la ALU.
--     - Doble puerto de escritura lógico (Write_A para R0, Write_B para R_Sel).
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.CONSTANTS_pkg.ALL;
use work.ALU_pkg.ALL;
use work.DataPath_pkg.ALL;

entity DataPath is
    Port (
        clk       : in std_logic;
        reset     : in std_logic;

        -- Bus de Datos con Memoria/IO
        MemDataIn : in  data_vector; -- Dato leído de memoria/IO
        MemDataOut: out data_vector; -- Dato a escribir en memoria/IO
        IndexB_Out: out data_vector; -- Salida de RegB para el AddressPath
        RegA_Out  : out data_vector; -- Salida directa de A para AddressPath
        PC_In     : in  address_vector; -- Entrada del PC para guardar en Stack

        -- Señales de Control (vienen de la UC)
        ALU_Op    : in  opcode_vector; -- Operación ALU
        Bus_Op    : in  std_logic_vector(1 downto 0); -- Control mux entrada (ej: 00=Mem, 01=ALU, 10=PC_Low...)

        Write_A   : in  std_logic; -- Habilitar escritura en A
        Write_B   : in  std_logic; -- Habilitar escritura en B
        Reg_Sel   : in  std_logic_vector(MSB_REG_SEL downto 0); -- Selección registro operando B
        Write_F   : in  std_logic; -- Habilitar actualización de Flags
        Flag_Mask : in  status_vector; -- Máscara para actualización parcial de flags (1=update)
        MDR_WE    : in  std_logic; -- Habilitar escritura en MDR (Memory Data Register)
        ALU_Bin_Sel : in std_logic; -- Selección entrada B ALU: 0=Reg, 1=MDR
        Out_Sel   : in  std_logic_vector(2 downto 0); -- Selección salida: A, B, Zero, PCL, PCH
        Load_F_Direct : in std_logic; -- Carga directa de Flags desde Bus_Int (POP F)
        EA_In     : in  address_vector; -- Entrada de resultado de 16 bits desde AddressPath
        EA_Flags_In : in status_vector; -- Flags generados por AddressPath
        F_Src_Sel : in  std_logic;      -- Selección fuente flags: 0=ALU, 1=AddressPath

        -- Forwarding EX→EX: camino de bypass para el operando A de la ALU.
        -- Cuando Fwd_A_En='1', la ALU recibe Fwd_A_Data en lugar de RegA.
        -- Fwd_A_Data debe ser conectado en el nivel superior (Processor_Top) al valor
        -- a reenviar (típicamente el último resultado de escritura en A).
        Fwd_A_En  : in  std_logic;      -- Habilita bypass del banco de registros para operando A
        Fwd_A_Data: in  data_vector;    -- Valor a reenviar (fuente externa del bypass)

        -- Salidas de Estado hacia la UC
        FlagsOut  : out status_vector -- Para saltos condicionales
    );
end entity DataPath;

architecture unique of DataPath is

    for all : ALU_comp use entity work.ALU(unique);

    -- =========================================================================
    -- Banco de Registros (Register File)
    -- =========================================================================
    -- Se define como un array de vectores de 8 bits indexados 0..7.
    -- R0 (RegA) cumple el rol de Acumulador: destino implícito de la mayoría
    -- de las operaciones ALU y fuente de ST/PUSH.
    -- R1 (RegB) es el segundo operando en operaciones registro-registro y
    -- también actúa como índice en modos de direccionamiento [n+B].
    -- R2..R7 son registros de propósito general accesibles vía Reg_Sel.
    -- Inicialización a 0 para simulación limpia (sin contenido indeterminado).
    signal Registers : register_file_t := (others => (others => '0'));

    -- Alias semánticos: R0 es siempre el Acumulador (A), R1 es el registro B por defecto.
    -- Estos alias son puramente textuales en VHDL; no generan lógica adicional.
    -- Mejoran la legibilidad sin impacto en hardware.
    alias RegA is Registers(0); -- Acumulador: destino principal de la ALU
    alias RegB is Registers(1); -- Registro B: índice y segundo operando por defecto

    -- =========================================================================
    -- Registros Internos de Estado y Temporales
    -- =========================================================================

    -- RegF: Registro de Flags de 8 bits (C, H, V, Z, G, E, R, L).
    -- Persiste entre instrucciones; sólo se modifica con Write_F='1' o Load_F_Direct='1'.
    -- Tras reset se pone a 0: interrupciones deshabilitadas (bit I=0), estado limpio.
    signal RegF   : status_vector := (others => '0'); -- Flags

    -- MDR (Memory Data Register): buffer de captura del bus de datos de memoria.
    -- Desacopla el tiempo de acceso a memoria del flanco de reloj del procesador:
    -- la UC aserta MDR_WE en el ciclo en que la memoria presenta el dato válido;
    -- a partir del siguiente flanco el dato es estable en MDR y puede ser leído
    -- sin dependencia de la memoria externa.
    signal MDR    : data_vector := (others => '0');   -- Memory Data Register

    -- =========================================================================
    -- Señales Combinacionales Internas
    -- =========================================================================

    -- ALU_Res: resultado combinacional de 8 bits producido por la ALU en el
    -- ciclo actual. Se latchea en el banco de registros sólo si Write_A='1'
    -- o Write_B='1' al flanco de subida.
    signal ALU_Res  : data_vector;

    -- ALU_Stat: flags combinacionales generados por la ALU junto con ALU_Res.
    -- Se latchean en RegF si Write_F='1' (con la máscara Flag_Mask aplicada)
    -- o si F_Src_Sel='0' (fuente ALU seleccionada frente a AddressPath).
    signal ALU_Stat : status_vector;

    -- Bus_Int: bus interno de escritura hacia el banco de registros.
    -- Actúa como salida del MUX de fuentes (Bus_Op); une el resultado seleccionado
    -- (ALU, MDR, byte bajo de EA, byte alto de EA) con los puertos de escritura
    -- del banco de registros y con la entrada de RegF en modo Load_F_Direct.
    signal Bus_Int  : data_vector; -- Bus interno de escritura (resultado mux)

    -- ALU_OpA: operando A seleccionado para la entrada A de la ALU (tras mux de forwarding).
    -- Fwd_A_En='0': viene de RegA (Registros(0)) → ruta normal del banco de registros.
    -- Fwd_A_En='1': viene de Fwd_A_Data (bypass externo) → ruta de forwarding EX→EX.
    signal ALU_OpA  : data_vector; -- Operando A seleccionado (banco o forwarding)

    -- ALU_OpB: operando B seleccionado para la entrada B de la ALU.
    -- ALU_Bin_Sel='0': viene de Registers(Reg_Sel) → instrucciones registro-registro.
    -- ALU_Bin_Sel='1': viene del MDR → instrucciones con inmediato #n (ya capturado
    --   en el ciclo anterior mediante MDR_WE='1' durante el fetch del operando).
    signal ALU_OpB  : data_vector; -- Operando B seleccionado

    -- (New_Flags fue señal; movido a variable dentro del proceso secuencial
    --  para garantizar que RegF recibe el valor correcto en el mismo ciclo.

begin

    -- =========================================================================
    -- 1. Instancia de la ALU
    -- =========================================================================
    -- La ALU es puramente combinacional: RegOutACC y RegStatus se actualizan
    -- inmediatamente ante cualquier cambio en sus entradas.
    -- Nota: Carry_in necesita lógica especial (puede venir de F(7) o ser 0 o 1)
    -- Por ahora lo conectamos al flag C actual para operaciones aritméticas.
    -- Carry_in conectado a RegF(idx_fC): el flag C actual alimenta las operaciones
    -- ADC (suma con acarreo) y SBB (resta con préstamo), que leen el carry previo.
    Inst_ALU: ALU_comp
    Port map (
        RegInA    => ALU_OpA,       -- Operando A: RegA o Fwd_A_Data (tras mux de forwarding)
        RegInB    => ALU_OpB,       -- Entrada B multiplexada: Rn o MDR (inmediato)
        Oper      => ALU_Op,        -- Código de operación desde la Unidad de Control
        Carry_in  => RegF(idx_fC),  -- Carry actual: necesario para ADC/SBB
        RegOutACC => ALU_Res,       -- Resultado combinacional; se latchea si Write_A/B='1'
        RegStatus => ALU_Stat       -- Flags combinacionales; se latchean si Write_F='1'
    );

    -- =========================================================================
    -- =========================================================================
    -- MUX Forwarding: Operando A de la ALU
    -- =========================================================================
    -- Selecciona entre el valor actual del banco de registros (RegA) y el valor
    -- externo de forwarding (Fwd_A_Data) proporcionado por el nivel superior.
    -- Fwd_A_En='0' → ruta normal (RegA del banco).
    -- Fwd_A_En='1' → bypass externo (Fwd_A_Data, típicamente el último WB de A).
    ALU_OpA <= Fwd_A_Data when Fwd_A_En = '1' else RegA;

    -- =========================================================================
    -- MUX Operando B de la ALU
    -- =========================================================================
    -- MUX Entrada B ALU:
    -- Permite flexibilidad total: ALU puede operar A con cualquier Rn o con MDR (inmediato).
    -- ALU_Bin_Sel='0': segundo operando viene del banco de registros; Reg_Sel
    --   indica cuál (instrucciones registro-registro, p.ej. ADD A,B o CMP A,R3).
    -- ALU_Bin_Sel='1': segundo operando viene del MDR (instrucciones con inmediato
    --   #n, p.ej. ADD A,#n); el MDR ya capturó el inmediato un ciclo antes.
    ALU_OpB <= Registers(to_register_index(Reg_Sel)) when ALU_Bin_Sel = '0' else MDR;

    -- =========================================================================
    -- 2. Lógica de Write-Back (Escritura en Registros)
    -- =========================================================================

    -- MUX Write-Back: Selecciona la fuente de datos a escribir en el banco de registros.
    -- Bus_Op determina qué dato llega a Bus_Int y de ahí a los registros destino.
    -- NOTA VHDL: la rama "when others" aparece antes de las dos últimas entradas
    -- concretas (EA_LOW_elected / EA_HIGH_elected). En VHDL-93/2008 el sintetizador
    -- acepta esto pero la semántica es que 'others' captura cualquier valor no
    -- cubierto por los casos anteriores; como EA_LOW_elected y EA_HIGH_elected son
    -- valores distintos de los previos, serán alcanzados correctamente por el
    -- sintetizador IEEE. No se modifica el código para preservar la intención original.
    process(Bus_Op, ALU_Res, MDR, EA_In)
    begin
        case Bus_Op is
            -- ACC_ALU_elected: la ALU computa; su resultado va al banco de registros.
            -- Usado por todas las instrucciones ALU (ADD, SUB, AND, INC, etc.).
            when ACC_ALU_elected  => Bus_Int <= ALU_Res;   -- Resultado ALU

            -- MEM_MDR_elected: dato de memoria (ya latched en MDR) va al banco.
            -- Usado por LD A,[nn], LD B,[nn], LD A,#n, LD B,#n, POP *, IN A,...
            when MEM_MDR_elected => Bus_Int <= MDR;       -- Dato de Memoria/IO (vía MDR)

            -- EA_LOW_elected: byte bajo (bits 7..0) del resultado de 16 bits del
            -- AddressPath (EA_In). Usado por ADD16/SUB16 para escribir el byte bajo
            -- en RegB (R1), y por ST SP_L para capturar el SP bajo en RegA.
            when EA_LOW_elected   => Bus_Int <= EA_In(7 downto 0);

            -- EA_HIGH_elected: byte alto (bits 15..8) del resultado de 16 bits.
            -- Usado por ADD16/SUB16 para escribir el byte alto en RegA (R0),
            -- y por ST SP_H para capturar el SP alto en RegA.
            when EA_HIGH_elected  => Bus_Int <= EA_In(15 downto 8);

            -- Relleno por defecto: cuando Bus_Op no corresponde a ningún caso
            -- semánticamente válido en el ciclo actual (p.ej. instrucciones ST
            -- donde no se escribe en registros de datos).
            when others => Bus_Int <= (others => '0');
        end case;
    end process;

    -- =========================================================================
    -- Proceso Secuencial: Actualización de Registros en Flanco de Reloj
    -- =========================================================================
    -- Toda escritura en estado persistente (banco de registros, RegF, MDR)
    -- ocurre en el flanco de subida del reloj o al activar reset asíncrono.
    process(clk, reset)
        variable v_new_flags : status_vector; -- Flags intermedios (ALU o EA); variable para actualización inmediata
    begin
        if reset = '1' then
            -- Reset asíncrono: inicializa todo a cero.
            -- RegF a cero implica interrupciones deshabilitadas (bit I=0) desde
            -- el primer ciclo; el procesador comenzará en modo seguro sin responder
            -- a IRQ hasta que la UC ejecute SEI.
            Registers <= (others => (others => '0')); -- Limpia todos los registros R0..R7
            RegF <= (others => '0');                  -- Flags en cero; I=0 → IRQ inhibida
            MDR  <= (others => '0');                  -- MDR limpio
        elsif rising_edge(clk) then

            -- ================================================================
            -- Escritura en Acumulador (A / R0)
            -- ================================================================
            -- Write_A es el puerto dedicado para R0. Se activa en operaciones
            -- ALU que producen resultado en A (ADD, SUB, AND, LD A,...).
            -- La independencia de Write_A y Write_B permite, en teoría, doble
            -- escritura en el mismo ciclo (aunque normalmente se usan por separado).
            if Write_A = '1' then
                RegA <= Bus_Int; -- Carga Bus_Int en R0 (Acumulador)
            end if;

            -- ================================================================
            -- Escritura en Registro General (R0..R7 seleccionado por Reg_Sel)
            -- ================================================================
            -- Write_B activa la escritura en el registro apuntado por Reg_Sel.
            -- Permite mover resultados a cualquier Rn: usado por LD B,#n,
            -- instrucciones de intercambio, ADD16 (byte bajo → R1), etc.
            -- Si Reg_Sel=0 y Write_B='1', se sobreescribe R0 (mismo que Write_A).
            if Write_B = '1' then
                Registers(to_register_index(Reg_Sel)) <= Bus_Int; -- Escribe en Rn
            end if;

            -- ================================================================
            -- Gestión de Flags (Registro F)
            -- ================================================================
            -- Dos modos de escritura en RegF, con prioridad a Load_F_Direct:
            --
            -- Load_F_Direct='1': bypass de la máscara — carga directa del byte
            --   presente en Bus_Int sobre todos los bits de RegF. Usado por la
            --   instrucción POP F, que restaura el estado completo del procesador
            --   (incluyendo el flag I) tal como fue guardado por PUSH F o por
            --   la rutina de interrupción.
            --
            -- Write_F='1' (con Load_F_Direct='0'): actualización enmascarada.
            --   Primero se selecciona la fuente de nuevos flags (ALU o AddressPath),
            --   luego se aplica apply_flag_mask para actualizar sólo los bits en '1'
            --   de Flag_Mask, preservando el resto. Esto permite instrucciones que
            --   sólo afectan a Z (p.ej. LD A,B) sin tocar C u otros flags.
            if Load_F_Direct = '1' then
                -- Carga directa (POP F): Sobrescribe todo el registro desde el bus.
                -- Bus_Int contiene el byte leído de la pila (MDR → Bus_Int vía MEM_MDR_elected).
                RegF <= Bus_Int(status_vector'range);
            elsif Write_F = '1' then
                -- Actualización con máscara: (Old and NOT Mask) OR (New and Mask)
                -- Seleccionar fuente de flags:
                -- F_Src_Sel='0' → flags de la ALU (operaciones de 8 bits).
                -- F_Src_Sel='1' → flags del AddressPath (operaciones de 16 bits ADD16/SUB16).
                if F_Src_Sel = '1' then v_new_flags := EA_Flags_In; else v_new_flags := ALU_Stat; end if;

                -- apply_flag_mask(Old, New, Mask): preserva en RegF los bits donde Mask='0'
                -- y actualiza con v_new_flags los bits donde Mask='1'.
                RegF <= apply_flag_mask(RegF, v_new_flags, Flag_Mask);
            end if;

            -- ================================================================
            -- Escritura MDR (Captura de dato de memoria)
            -- ================================================================
            -- MDR_WE='1': captura síncrona de MemDataIn en el flanco de subida.
            -- El MDR actúa como buffer de entrada: retiene el dato un ciclo completo,
            -- garantizando que sea estable cuando la UC lo lea en el ciclo siguiente
            -- (p.ej. en ESS_LD_WB, que lee MDR→Bus_Int→RegA). Sin el MDR, el dato
            -- de memoria debería mantenerse válido durante el ciclo entero de escritura,
            -- lo que impondría requisitos más estrictos a la interfaz de memoria.
            if MDR_WE = '1' then
                MDR <= MemDataIn; -- Captura el dato del bus de memoria
            end if;
        end if;
    end process;

    -- =========================================================================
    -- 3. Salidas del DataPath
    -- =========================================================================

    -- =====================================================================
    -- MUX de Salida hacia el Bus de Datos de Memoria (MemDataOut)
    -- =====================================================================
    -- Out_Sel selecciona qué dato se expone en el bus de salida de datos.
    -- Este valor se escribe en memoria cuando la UC aserta Mem_WE='1'.
    --
    -- OUT_SEL_A    : salida del Acumulador (A/R0).
    --               Usado por ST A,[nn], ST A,[n+B], OUT #n,A, PUSH A.
    -- OUT_SEL_B    : salida de RegB (R1).
    --               Usado por ST B,[nn], PUSH B.
    -- OUT_SEL_ZERO : salida de cero (0x00).
    --               Usado como byte de relleno en PUSH (byte alto de par A:B cuando
    --               sólo se empuja un registro de 8 bits en una pila de 16 bits).
    -- OUT_SEL_PCL  : byte bajo del PC (bits 7..0 de PC_In).
    --               Usado por CALL y rutina de interrupción para guardar PCL en pila.
    -- OUT_SEL_PCH  : byte alto del PC (bits 15..8 de PC_In).
    --               Usado por CALL y rutina de interrupción para guardar PCH en pila.
    -- OUT_SEL_F    : registro de flags completo.
    --               Usado por PUSH F y por la rutina de interrupción (ESS_INT)
    --               para preservar el estado del procesador en la pila.
    with Out_Sel select MemDataOut <=
        RegA            when OUT_SEL_A,    -- ST A / PUSH A / OUT A
        RegB            when OUT_SEL_B,    -- ST B / PUSH B
        (others => '0') when OUT_SEL_ZERO, -- Byte de relleno (padding en PUSH)
        PC_In(7 downto 0)   when OUT_SEL_PCL, -- Byte bajo PC → pila (CALL/INT)
        PC_In(15 downto 8)  when OUT_SEL_PCH, -- Byte alto PC → pila (CALL/INT)
        RegF                when OUT_SEL_F,   -- Flags → pila (PUSH F / INT save)
        (others => '0') when others;          -- Valor seguro por defecto

    -- =====================================================================
    -- Salidas Directas hacia la Unidad de Control y el AddressPath
    -- =====================================================================

    -- FlagsOut: estado actual de RegF expuesto a la UC en cada ciclo.
    -- La UC lo usa en el proceso combinacional para evaluar condiciones de salto
    -- (BEQ, BNE, BCS, etc.) en el mismo ciclo en que los flags son necesarios.
    FlagsOut   <= RegF;

    -- IndexB_Out: valor actual de R1 (RegB) enviado al AddressPath.
    -- El AddressPath lo usa como desplazamiento en modos [n+B], [B] (LD/ST indexados).
    IndexB_Out <= RegB;

    -- RegA_Out: valor actual de R0 (RegA/Acumulador) enviado al AddressPath.
    -- Usado por JP A:B (donde A es el byte alto de la dirección destino) y por
    -- LD SP,A:B (donde A:B forman el valor de 16 bits a cargar en SP).
    RegA_Out   <= RegA;

end architecture unique;
