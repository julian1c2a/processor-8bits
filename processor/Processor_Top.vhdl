--------------------------------------------------------------------------------
-- Copyright (c) 2026 MICROELECTRÓNICA26.UMA.EII
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Entidad: Processor_Top
-- Descripción:
--   Nivel superior (Top Level) del procesador de 8 bits.
--   Integra y conecta los tres subsistemas principales:
--     1. Control Unit (Cerebro)
--     2. Data Path (Ejecución 8-bit)
--     3. Address Path (Direccionamiento 16-bit)
--
--   Expone la interfaz de memoria y E/S hacia el exterior (FPGA/Testbench).
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use work.CONSTANTS_pkg.ALL;
use work.ALU_pkg.ALL;
use work.DataPath_pkg.ALL;
use work.AddressPath_pkg.ALL;
use work.ControlUnit_pkg.ALL;

entity Processor_Top is
    Port (
        clk         : in  std_logic;                        -- Reloj del sistema compartido por los tres subsistemas
        reset       : in  std_logic;                        -- Reset síncrono activo alto; inicializa PC, SP, registros y la UC

        -- External Memory Interface
        -- Bus Von Neumann: una única interfaz de memoria compartida por instrucciones y datos.
        -- La UC determina en cada ciclo si el acceso es a instrucción (fetch) o a dato (LD/ST).
        MemAddress  : out address_vector;                   -- Dirección de 16 bits hacia la memoria; generada por AddressPath
        MemData_In  : in  data_vector;                      -- Datos entrantes de 8 bits desde memoria; se distribuye a tres consumidores (ver abajo)
        MemData_Out : out data_vector;                      -- Datos salientes de 8 bits hacia memoria; provienen de DataPath (ST, PUSH, CALL)
        Mem_WE      : out std_logic;                        -- Write Enable de memoria; activo alto; controlado por la UC
        Mem_RE      : out std_logic;                        -- Read Enable de memoria; activo alto; controlado por la UC
        Mem_Ready   : in  std_logic;                        -- Handshake: '1' = memoria lista; '0' = insertar wait states (la UC detiene el pipeline)

        -- External IO Interface (simplificado, comparte buses)
        -- El bus de datos y de direcciones es compartido con el espacio de memoria
        -- (arquitectura Von Neumann con decodificación de espacio I/O por dirección).
        IO_WE       : out std_logic;                        -- Write Enable de I/O; activo alto; controlado por la UC
        IO_RE       : out std_logic;                        -- Read Enable de I/O; activo alto; controlado por la UC
        IRQ         : in  std_logic := '0';                 -- Solicitud de interrupción enmascarable; '0' si no conectada
        NMI         : in  std_logic := '0'                  -- Interrupción no enmascarable; '0' si no conectada
    );
end entity Processor_Top;

architecture Structural of Processor_Top is

    -- =========================================================================
    -- Component Configurations
    -- =========================================================================
    -- La directiva "for all : <comp> use entity work.<ent>(<arch>)" vincula
    -- explícitamente cada componente con la entidad y arquitectura correspondientes.
    -- Esto evita ambigüedad cuando existen múltiples arquitecturas para la misma
    -- entidad (p.ej. "unique" vs "behavioral" vs "rtl"): el sintetizador/simulador
    -- elige exactamente la arquitectura indicada sin heurísticas.
    -- Sin esta configuración, VHDL-93 tomaría la última arquitectura compilada,
    -- lo que puede causar comportamientos distintos según el orden de compilación.
    for all : DataPath_comp    use entity work.DataPath(unique);     -- Vincula DataPath_comp a la arquitectura 'unique' de DataPath
    for all : AddressPath_comp use entity work.AddressPath(unique);  -- Vincula AddressPath_comp a la arquitectura 'unique' de AddressPath
    for all : ControlUnit_comp use entity work.ControlUnit(pipeline);  -- Vincula ControlUnit_comp a la arquitectura 'pipeline' de ControlUnit

    -- =========================================================================
    -- Señales de Interconexión Interna
    -- =========================================================================

    -- s_CtrlBus: palabra de control única que la UC emite cada ciclo.
    --   Contiene todos los campos de control (ALU_Op, PC_Op, SP_Op, Write_A,
    --   Write_B, Mem_WE, etc.) agrupados en un record definido en ControlUnit_pkg.
    --   Tanto DataPath como AddressPath reciben s_CtrlBus simultáneamente
    --   (campos ortogonales): la UC genera un único control word que maneja
    --   en paralelo el camino de datos de 8 bits y el camino de direcciones de 16 bits.
    signal s_CtrlBus    : control_bus_t;

    -- s_Flags: vector de flags del registro de estado del DataPath hacia la UC.
    --   Cierra el bucle de retroalimentación: DataPath → UC.
    --   La UC evalúa s_Flags para resolver saltos condicionales (JZ, JC, JG, etc.)
    --   y para decidir si ejecutar o saltar la instrucción condicional.
    signal s_Flags      : status_vector;

    -- s_AddressBus: bus de direcciones de 16 bits generado por AddressPath.
    --   Sale directamente al pin MemAddress del top level (bus Von Neumann).
    --   En cada ciclo, AddressPath selecciona la fuente (PC, SP, EAR, EA_RES,
    --   vectores de interrupción) mediante ABUS_Sel de la UC.
    signal s_AddressBus : address_vector;

    -- s_DataPath_DataOut: byte de datos que DataPath quiere ESCRIBIR en memoria.
    --   Activo en instrucciones ST (store), PUSH y CALL (escritura de dirección de retorno).
    --   Sale al pin MemData_Out del top level.
    signal s_DataPath_DataOut : data_vector;

    -- s_DataPath_IndexB: valor actual del registro B exportado por DataPath.
    --   AddressPath lo usa como índice en el modo de direccionamiento [nn+B]:
    --   EA = TMP + B (sin signo extendido a 16 bits).
    --   También se usa en el par A:B para operaciones de 16 bits (ADD16/SUB16).
    signal s_DataPath_IndexB  : data_vector;

    -- s_DataPath_RegA: valor actual del registro A exportado por DataPath.
    --   AddressPath lo combina con B para formar el par A:B como entero de 16 bits
    --   (A es el byte alto, B el byte bajo) en el modo EA_A_SRC_REG_AB.
    --   Esto permite ADD16/SUB16 donde A:B actúa como acumulador de 16 bits.
    signal s_DataPath_RegA    : data_vector; -- Nuevo: Salida A

    -- s_fwd_a_data: dato de forwarding EX→EX para la entrada A de la ALU en DataPath.
    --   Actualmente conectado a s_DataPath_RegA (RegA), lo que hace el bypass transparente
    --   cuando Fwd_A_En='0' (comportamiento por defecto: no forwarding activo).
    --   En v0.8, cuando la UC implemente solapamiento DECODE+EX, este bus se
    --   conectará al resultado de write-back del ciclo anterior para completar el bypass.
    signal s_fwd_a_data       : data_vector;

    -- s_AddressPath_PC: valor actual del PC exportado por AddressPath hacia DataPath.
    --   DataPath necesita el PC para la instrucción CALL: debe hacer PUSH del
    --   PC actual (dirección de retorno) en la pila antes de saltar a la subrutina.
    --   La señal es combinacional en AddressPath (PC_Out <= r_PC) para que esté
    --   disponible en el mismo ciclo que se ejecuta CALL.
    signal s_AddressPath_PC   : address_vector; -- PC del AddressPath al DataPath

    -- s_AddressPath_EA: resultado actual del sumador EA de AddressPath hacia DataPath.
    --   DataPath lo recibe para:
    --     a) ADD16/SUB16: el resultado de 16 bits se divide en byte alto (bits 15..8)
    --        y byte bajo (bits 7..0) que se escriben de vuelta en A y B respectivamente.
    --     b) ST SP_L/ST SP_H: el valor del SP (expuesto via EA_Adder_Res con
    --        EA_A=SP, EA_B=0) se almacena en memoria a través del DataPath.
    signal s_AddressPath_EA   : address_vector; -- Nuevo: Resultado EA

    -- s_AddressPath_Flags: flags C y Z resultantes de la operación del sumador EA de 16 bits.
    --   Se alimentan al registro de estado del DataPath cuando la UC activa
    --   Write_F con la máscara de flags adecuada, tras instrucciones ADD16/SUB16.
    signal s_AddressPath_Flags: status_vector;  -- Nuevo: Flags EA

    -- s_addr_data_in: MUX de datos hacia AddressPath.DataIn.
    --   Normalmente = MemData_In (carga TMP desde el bus de datos de memoria).
    --   Cuando s_CtrlBus.Op_Sel='1' = s_CtrlBus.Op_Data (carga TMP desde operando
    --   pre-fetched del pipeline para instrucciones de 3 bytes sin ciclo adicional de lectura).
    signal s_addr_data_in : data_vector;

begin

    -- ========================================================================
    -- 1. Instantiation of the Control Unit (The Brain)
    -- ========================================================================
    -- La UC recibe el byte de instrucción y los flags, y emite todas las señales de control.
    Inst_UC: ControlUnit_comp
        Port map (
            clk      => clk,
            reset    => reset,
            FlagsIn  => s_Flags,      -- Retroalimentación: flags del DataPath para saltos condicionales
            InstrIn  => MemData_In,   -- El byte de instrucción viene del bus de datos de memoria; MemData_In se fan-out a tres consumidores: UC (opcode), AddressPath (bytes de TMP), DataPath (MDR)
            Mem_Ready => Mem_Ready,   -- Handshake de memoria: la UC detiene el pipeline si Mem_Ready='0' (wait states)
            IRQ      => IRQ,          -- Señal de interrupción enmascarable hacia la UC
            NMI      => NMI,          -- Señal de interrupción no enmascarable hacia la UC
            CtrlBus  => s_CtrlBus     -- Palabra de control completa emitida por la UC cada ciclo
        );

    -- ========================================================================
    -- 2. Instantiation of the Address Path (16-bit operations)
    -- ========================================================================
    -- Gestiona PC, SP, LR, y calcula direcciones efectivas.

    -- MUX de datos para AddressPath.DataIn:
    --   Modo normal   (Op_Sel='0'): usa MemData_In (cargar TMP desde memoria externa).
    --   Modo pipeline (Op_Sel='1'): usa Op_Data del CtrlBus (operando pre-fetched del pipeline
    --     para instrucciones de 3 bytes, evitando un ciclo extra de lectura de memoria).
    s_addr_data_in <= s_CtrlBus.Op_Data when s_CtrlBus.Op_Sel = '1' else MemData_In;

    -- Routing del dato de forwarding: actualmente se usa RegA_Out (valor registrado).
    -- Garantiza que Fwd_A_En='1' con este conexionado reproduce el mismo valor que RegA,
    -- manteniendo compatibilidad con todos los testbenches existentes hasta que el
    -- paso [2] (solapamiento DECODE+EX) requiera un valor de WB diferente.
    s_fwd_a_data <= s_DataPath_RegA;

    Inst_AddrPath: AddressPath_comp
        Port map (
            clk          => clk,
            reset        => reset,
            DataIn       => s_addr_data_in,          -- MUX: MemData_In normal / Op_Data del pipeline para ESS_TMP_FROM_OP*
            Index_B      => s_DataPath_IndexB,   -- Registro B desde DataPath: índice para modo [nn+B] y byte bajo del par A:B
            Index_A      => s_DataPath_RegA,     -- Registro A desde DataPath: byte alto del par A:B para ADD16/SUB16
            AddressBus   => s_AddressBus,         -- Bus de direcciones de 16 bits generado (sale al exterior vía MemAddress)
            PC_Out       => s_AddressPath_PC,     -- PC actual (combinacional) hacia DataPath: CALL necesita el PC para hacer PUSH de la dirección de retorno
            EA_Out       => s_AddressPath_EA,     -- Resultado EA de 16 bits hacia DataPath: para ADD16/SUB16 y ST SP_L/H
            EA_Flags     => s_AddressPath_Flags,  -- Flags C/Z de la operación EA: se propagan al registro de estado tras ADD16/SUB16
            -- Señales de control desde la UC (campos del control word s_CtrlBus)
            PC_Op        => s_CtrlBus.PC_Op,      -- Operación del PC: NOP / INC / LOAD / LOAD_L
            SP_Op        => s_CtrlBus.SP_Op,      -- Operación del SP: NOP / INC(POP) / DEC(PUSH) / LOAD
            ABUS_Sel     => s_CtrlBus.ABUS_Sel,   -- Fuente del bus de direcciones: PC / SP / EAR / EA_RES / vectores IRQ/NMI
            Load_LR      => s_CtrlBus.Load_LR,    -- '1' = capturar PC en LR (dirección de retorno para CALL/BSR)
            Load_EAR     => s_CtrlBus.Load_EAR,   -- '1' = registrar resultado EA en EAR (para accesos indirectos en pipeline)
            Load_TMP_L   => s_CtrlBus.Load_TMP_L, -- '1' = cargar byte bajo de TMP desde MemData_In (primer byte del operando de 16 bits)
            Load_TMP_H   => s_CtrlBus.Load_TMP_H, -- '1' = cargar byte alto de TMP desde MemData_In (segundo byte del operando de 16 bits)
            Load_Src_Sel => s_CtrlBus.Load_Src_Sel, -- Fuente de carga para PC/SP/LR: 0=EA_Adder_Res (relativo), 1=TMP (absoluto)
            Clear_TMP    => s_CtrlBus.Clear_TMP,   -- '1' = limpiar TMP (prioridad; necesario antes de cargar operandos de página cero)
            SP_Offset    => s_CtrlBus.SP_Offset,   -- '1' = AddressBus = SP+1 (acceso al byte alto de la palabra en pila, little-endian)
            Force_ZP     => s_CtrlBus.Force_ZP,    -- '1' = forzar MSB del AddressBus a 0x00 (wrapping a página cero)
            EA_A_Sel     => s_CtrlBus.EA_A_Sel,    -- Selecciona operando base del sumador EA: TMP / PC / A:B / SP
            EA_B_Sel     => s_CtrlBus.EA_B_Sel,    -- Selecciona operando índice del sumador EA: B / DataIn(signed) / TMP
            EA_Op        => s_CtrlBus.EA_Op         -- Operación del sumador EA: 0=ADD (EA=A+B), 1=SUB (EA=A-B)
        );

    -- ========================================================================
    -- 3. Instantiation of the Data Path (8-bit operations)
    -- ========================================================================
    -- Gestiona el banco de registros (A, B, R2-R7), la ALU, y el MDR.
    Inst_DataPath: DataPath_comp
        Port map (
            clk       => clk,
            reset     => reset,
            MemDataIn  => MemData_In,          -- MemData_In se distribuye aquí como entrada al MDR (Memory Data Register); para LD A,[nn], LD B,[nn], etc.
            MemDataOut => s_DataPath_DataOut,  -- Dato de 8 bits a escribir en memoria (ST, PUSH, CALL → retorna por MemData_Out al exterior)
            IndexB_Out => s_DataPath_IndexB,   -- Registro B exportado hacia AddressPath para indexado [nn+B] y par A:B
            RegA_Out   => s_DataPath_RegA,     -- Registro A exportado hacia AddressPath para el par A:B en ADD16/SUB16
            PC_In      => s_AddressPath_PC,    -- PC actual desde AddressPath: DataPath lo usa en CALL para hacer PUSH de la dirección de retorno
            FlagsOut   => s_Flags,             -- Registro de estado (flags) hacia la UC: cierra el bucle de retroalimentación para saltos condicionales
            -- Señales de control desde la UC (campos del control word s_CtrlBus)
            ALU_Op     => s_CtrlBus.ALU_Op,    -- Opcode de la ALU: selecciona la operación aritmética/lógica
            Bus_Op     => s_CtrlBus.Bus_Op,    -- Operación del bus interno del DataPath: selecciona fuente/destino del dato
            Write_A    => s_CtrlBus.Write_A,   -- '1' = escribir resultado de la ALU en el registro A
            Write_B    => s_CtrlBus.Write_B,   -- '1' = escribir resultado de la ALU en el registro B (usado por INB/DEB)
            Reg_Sel    => s_CtrlBus.Reg_Sel,   -- Selecciona el registro destino/fuente en el banco de registros
            Write_F    => s_CtrlBus.Write_F,   -- '1' = actualizar el registro de flags con el resultado de la operación
            Flag_Mask  => s_CtrlBus.Flag_Mask, -- Máscara de bits: indica qué flags se actualizan (evita sobreescribir flags no afectados)
            MDR_WE     => s_CtrlBus.MDR_WE,    -- '1' = cargar el MDR desde MemData_In (captura el dato leído de memoria)
            ALU_Bin_Sel => s_CtrlBus.ALU_Bin_Sel, -- Selecciona la fuente del operando B de la ALU: Reg_B / MDR / inmediato / EA
            Out_Sel    => s_CtrlBus.Out_Sel,   -- Selecciona qué dato sale por MemDataOut: ACC / PC_low / PC_high / SP_low / SP_high
            Load_F_Direct => s_CtrlBus.Load_F_Direct, -- '1'=carga F directamente desde bus interno (POP F, RTI)
            EA_In      => s_AddressPath_EA,    -- Resultado EA de 16 bits desde AddressPath (ADD16/SUB16, ST SP_L/H)
            EA_Flags_In => s_AddressPath_Flags, -- Flags C/Z del sumador EA (para Write_F tras ADD16/SUB16)
            F_Src_Sel  => s_CtrlBus.F_Src_Sel, -- Selección fuente flags: 0=ALU, 1=AddressPath EA
            -- Forwarding EX→EX: bypass de operando A
            Fwd_A_En   => s_CtrlBus.Fwd_A_En,  -- Habilita bypass (UC lo controla)
            Fwd_A_Data => s_fwd_a_data          -- Dato de forwarding (actualmente = RegA)
        );

    -- ========================================================================
    -- 4. Top-Level Connections
    -- ========================================================================

    -- Bus de Direcciones (Von Neumann): generado íntegramente por AddressPath.
    --   Un único bus de 16 bits comparte el espacio de instrucciones y de datos.
    --   La UC garantiza que solo un maestro (PC para fetch, SP para stack,
    --   EAR/EA_RES para datos) controle el bus en cada ciclo mediante ABUS_Sel.
    MemAddress <= s_AddressBus; -- Bus de direcciones de 16 bits: AddressPath → memoria externa

    -- Bus de Datos de Salida: generado por DataPath.
    --   Solo es válido cuando la UC activa Mem_WE o IO_WE.
    --   Fuentes posibles: ACC (ST), PC_low/PC_high (CALL/PUSH PC), SP_low/SP_high (ST SP).
    MemData_Out <= s_DataPath_DataOut; -- Datos a escribir en memoria: DataPath → memoria externa

    -- Señales de control de Memoria e I/O: provienen directamente de la UC.
    --   La UC las activa exactamente en el ciclo correcto según la fase del pipeline.
    Mem_WE <= s_CtrlBus.Mem_WE; -- Write Enable de memoria: UC activa en ciclos de escritura (ST, PUSH, CALL)
    Mem_RE <= s_CtrlBus.Mem_RE; -- Read Enable de memoria:  UC activa en ciclos de lectura (fetch, LD, POP, RET)
    IO_WE  <= s_CtrlBus.IO_WE;  -- Write Enable de I/O:     UC activa en instrucciones OUT
    IO_RE  <= s_CtrlBus.IO_RE;  -- Read Enable de I/O:      UC activa en instrucciones IN

end architecture Structural;
