--------------------------------------------------------------------------------
-- Paquete: ControlUnit_pkg
-- Descripción:
--   Define los tipos de datos y registros para la Unidad de Control.
--   Contiene el registro 'control_bus_t' que agrupa TODAS las señales de control
--   físicas que van hacia el DataPath, AddressPath y Memoria.
--
--   La Unidad de Control decodifica las instrucciones y genera la secuencia de
--   palabras de control (microinstrucciones) necesarias para ejecutar cada opcode.
--   Todas las señales de control se agrupan en control_bus_t para simplificar la
--   interconexión y facilitar la depuración (un único registro observable).
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use work.CONSTANTS_pkg.ALL;
use work.ALU_pkg.ALL;
use work.DataPath_pkg.ALL;
use work.AddressPath_pkg.ALL;

package ControlUnit_pkg is

    -- =========================================================================
    -- Type: control_bus_t (Palabra de Control)
    -- =========================================================================
    -- Record que agrupa todas las señales de control del procesador.
    -- La UC genera un valor de este tipo en cada ciclo de reloj.
    -- Los campos están organizados por subsistema destino para facilitar la lectura.
    type control_bus_t is record

        -- =====================================================================
        -- === DATA PATH ===
        -- Señales de control que van hacia el componente DataPath_comp.
        -- =====================================================================

        -- Código de operación de la ALU (ver ALU_pkg: OP_ADD, OP_SUB, OP_AND, etc.).
        -- Válido y significativo siempre que Write_A='1' o Write_F='1'.
        -- Durante ciclos sin operación ALU se mantiene en OP_NOP para evitar glitches.
        ALU_Op      : opcode_vector;

        -- Selecciona qué fuente se conecta al bus interno de escritura del DataPath.
        -- Determina el dato que se almacenará en el banco de registros al activar Write_A o Write_B.
        -- Ver constantes: ACC_ALU_elected, MEM_MDR_elected, EA_LOW_elected, EA_HIGH_elected.
        Bus_Op      : std_logic_vector(1 downto 0);

        -- Habilita escritura en R0 (Acumulador A) al flanco de subida del reloj.
        -- '1' activo en instrucciones aritméticas/lógicas que modifican A, y en LD A.
        -- '0' en instrucciones que no afectan A (CMP, ST, saltos, etc.).
        Write_A     : std_logic;

        -- Habilita escritura en el registro indicado por Reg_Sel al flanco de subida.
        -- '1' en instrucciones LD Rn, MOV, POP y en INB/DEB cuando el resultado va a B.
        -- El registro destino se selecciona con Reg_Sel; si Reg_Sel="001" escribe en R1(B).
        Write_B     : std_logic;

        -- Índice de 3 bits del registro fuente/destino B en el banco de registros.
        -- Rango: "000"=R0(A), "001"=R1(B), "010"=R2, ..., "111"=R7.
        -- Controla tanto la lectura del operando B de la ALU como el destino de Write_B.
        Reg_Sel     : std_logic_vector(MSB_REG_SEL downto 0);

        -- Habilita actualización del registro de flags F al flanco de subida.
        -- '1' en instrucciones que modifican flags: aritméticas, lógicas, CMP, desplazamientos.
        -- '0' en instrucciones de transferencia (LD, ST, MOV) que no afectan flags.
        Write_F     : std_logic;

        -- Máscara de actualización de flags: bit(i)='1' permite actualizar el flag i.
        -- Permite que cada instrucción actualice solo sus flags relevantes sin modificar los demás.
        -- Ejemplo: ADD actualiza C,H,V,Z (mask=b"11110000"); LSL actualiza C,Z,L (mask=b"10010001").
        -- Ver función apply_flag_mask en DataPath_pkg para la semántica exacta.
        Flag_Mask   : status_vector;

        -- Write Enable del MDR (Memory Data Register): captura MemDataIn en el MDR.
        -- '1' durante el ciclo en que el dato de memoria está válido en el bus de entrada.
        -- El MDR retiene el dato hasta el siguiente ciclo para que la ALU lo use como inmediato
        -- (ALU_Bin_Sel='1') o para que se escriba en un registro (Bus_Op=MEM_MDR_elected).
        MDR_WE      : std_logic;

        -- Selección de la entrada B de la ALU.
        -- '0' = entrada B proviene del banco de registros (operando registro-registro).
        -- '1' = entrada B proviene del MDR (modo inmediato: el operando está en el MDR).
        ALU_Bin_Sel : std_logic;

        -- Selección de la fuente de los flags que se escriben en el registro F.
        -- '0' = flags provienen de la ALU de 8 bits (instrucciones aritméticas/lógicas normales).
        -- '1' = flags provienen del AddressPath (instrucciones ADD16/SUB16 que operan sobre A:B).
        F_Src_Sel   : std_logic;

        -- Carga directa del registro F desde el bus interno del DataPath (Bus_Int).
        -- '1' en la instrucción POP F: carga los flags directamente sin aplicar Flag_Mask.
        -- Permite restaurar el estado completo del procesador tras una interrupción o subrutina.
        -- Cuando es '1', Flag_Mask y Write_F son ignorados; F se sobreescribe completamente.
        Load_F_Direct : std_logic;

        -- Selecciona el dato que DataPath coloca en MemDataOut (bus de datos hacia memoria).
        -- Solo relevante cuando Mem_WE='1' (ciclo de escritura en memoria).
        -- Ver constantes: OUT_SEL_A, OUT_SEL_B, OUT_SEL_ZERO, OUT_SEL_PCL, OUT_SEL_PCH, OUT_SEL_F.
        Out_Sel     : std_logic_vector(2 downto 0);

        -- =====================================================================
        -- === ADDRESS PATH ===
        -- Señales de control que van hacia el componente AddressPath_comp.
        -- =====================================================================

        -- Operación del PC (Program Counter) en este ciclo de reloj.
        -- Ver constantes: PC_OP_NOP (mantener), PC_OP_INC (fetch secuencial),
        -- PC_OP_LOAD (salto absoluto/RET), PC_OP_LOAD_L (salto en página JPN).
        PC_Op       : std_logic_vector(1 downto 0);

        -- Operación del SP (Stack Pointer) en este ciclo de reloj.
        -- El SP siempre se mueve en ±2 (palabras de 16 bits alineadas a par).
        -- Ver constantes: SP_OP_NOP, SP_OP_INC (POP: +2), SP_OP_DEC (PUSH: -2), SP_OP_LOAD.
        SP_Op       : std_logic_vector(1 downto 0);

        -- Selecciona la fuente del bus de 16 bits de direcciones (AddressBus).
        -- Determina qué registro interno se usa como puntero en el ciclo actual.
        -- Ver constantes: ABUS_SRC_PC, ABUS_SRC_SP, ABUS_SRC_EAR, ABUS_SRC_EA_RES,
        -- ABUS_SRC_VEC_NMI_L/H, ABUS_SRC_VEC_IRQ_L/H.
        ABUS_Sel    : std_logic_vector(2 downto 0);

        -- Captura el PC actual en el Link Register (LR) al flanco de subida.
        -- '1' al inicio de CALL o BSR para guardar la dirección de retorno antes de saltar.
        -- El LR es el origen del valor que OUT_SEL_PCL/PCH retorna al stack en los ciclos siguientes.
        Load_LR     : std_logic;

        -- Captura el resultado del sumador EA en el EAR (Effective Address Register).
        -- '1' en el ciclo donde se calcula la dirección efectiva de un LD/ST indexado,
        -- para estabilizar la dirección en el bus durante el ciclo de acceso a memoria.
        -- Evita que el sumador EA siga cambiando mientras se realiza el acceso.
        Load_EAR    : std_logic;

        -- Carga DataIn (byte desde memoria) en TMP[7:0] (byte bajo del registro temporal).
        -- '1' en el primer ciclo de fetch de una dirección de 16 bits (primero llega el LSB).
        -- TMP acumula los bytes de la dirección para luego cargarla en PC o SP con Load_Src_Sel='1'.
        Load_TMP_L  : std_logic;

        -- Carga DataIn (byte desde memoria) en TMP[15:8] (byte alto del registro temporal).
        -- '1' en el segundo ciclo de fetch de una dirección de 16 bits (luego llega el MSB).
        -- Tras activar Load_TMP_H el registro TMP contiene la dirección de 16 bits completa.
        Load_TMP_H  : std_logic;

        -- Selecciona si PC o SP se cargan desde el sumador EA o desde el registro TMP.
        -- '0' = LOAD_SRC_ALU_RES: carga desde el resultado del sumador EA (saltos relativos).
        -- '1' = LOAD_SRC_DATA_IN: carga desde TMP ensamblado byte a byte (saltos absolutos, LD SP).
        Load_Src_Sel: std_logic;

        -- Offset para el acceso al Stack Pointer en modo Little-Endian.
        -- '0' = accede a la dirección SP (byte bajo de la palabra en pila).
        -- '1' = accede a la dirección SP+1 (byte alto de la palabra en pila).
        -- Necesario porque el SP apunta a la base de la palabra de 2 bytes y
        -- los dos bytes se acceden en ciclos consecutivos con SP_Offset alternante.
        SP_Offset   : std_logic;

        -- Pone a cero el registro TMP del AddressPath en este ciclo.
        -- '1' al inicio del ensamblaje de una dirección (para instrucciones de modo cero-página
        -- donde TMP[15:8] debe ser 0x00 implícitamente) o para resetear TMP entre instrucciones.
        Clear_TMP   : std_logic;

        -- Fuerza el byte alto de la dirección efectiva EA a 0x00 (modo página cero).
        -- '1' en instrucciones de modo [n+B] donde la dirección se limita a la página 0 (0x0000..0x00FF).
        -- Equivale a un wrapping de 8 bits: si n+B > 0xFF, la dirección sigue dentro de la página 0.
        Force_ZP    : std_logic;

        -- Selecciona el operando base (entrada A) del sumador EA de 16 bits.
        -- Ver constantes: EA_A_SRC_TMP, EA_A_SRC_PC, EA_A_SRC_REG_AB, EA_A_SRC_SP.
        EA_A_Sel    : std_logic_vector(1 downto 0);

        -- Selecciona el operando índice/desplazamiento (entrada B) del sumador EA de 16 bits.
        -- Ver constantes: EA_B_SRC_REG_B, EA_B_SRC_DATA_IN, EA_B_SRC_ZERO, EA_B_SRC_TMP.
        EA_B_Sel    : std_logic_vector(1 downto 0);

        -- Operación del sumador EA de 16 bits.
        -- '0' = EA_OP_ADD: EA_Result = EA_A + EA_B (modos indexados, saltos relativos, ADD16).
        -- '1' = EA_OP_SUB: EA_Result = EA_A - EA_B (instrucción SUB16).
        EA_Op       : std_logic;

        -- =====================================================================
        -- === MEMORIA / IO ===
        -- Señales de habilitación del bus Von Neumann compartido de memoria e IO.
        -- =====================================================================

        -- Write Enable de memoria: autoriza la escritura del dato en MemDataOut.
        -- '1' durante el ciclo activo de escritura en ST, PUSH, CALL (guardado en pila).
        -- La memoria usa este enable junto con el bus de direcciones para completar la escritura.
        Mem_WE      : std_logic;

        -- Read Enable de memoria: autoriza la lectura del dato desde MemDataIn.
        -- '1' durante el ciclo activo de lectura en LD, POP, RET (lectura de pila), fetch.
        -- El dato válido aparece en MemDataIn en el siguiente ciclo (latencia de 1 ciclo).
        Mem_RE      : std_logic;

        -- Write Enable del espacio de I/O: escribe en el periférico direccionado.
        -- '1' exclusivamente en la instrucción OUT; el bus de direcciones contiene el puerto.
        -- El espacio de I/O es independiente del espacio de memoria (Harvard parcial para IO).
        IO_WE       : std_logic;

        -- Read Enable del espacio de I/O: lee desde el periférico direccionado.
        -- '1' exclusivamente en la instrucción IN; el dato del periférico llega por MemDataIn.
        -- La UC debe activar MDR_WE en el ciclo siguiente para capturar el dato del periférico.
        IO_RE       : std_logic;

        -- =====================================================================
        -- === PIPELINE OPERAND DATA ===
        -- Datos de operando pre-decodificados en el pipeline (instrucciones de 3 bytes).
        -- Cuando Op_Sel='1' y Load_TMP_L/H='1', el AddressPath carga TMP desde
        -- Op_Data en lugar de desde el bus externo DataIn (MemData_In).
        -- Esto permite al pipeline cargar TMP con operandos pre-fetched sin un
        -- ciclo adicional de lectura de memoria.
        -- =====================================================================

        -- Byte de datos de operando desde los registros internos del pipeline (r_exec_op1/op2).
        -- Solo válido cuando Op_Sel='1'. Se usa para cargar TMP en instrucciones 3-byte.
        Op_Data     : data_vector;

        -- Selector de fuente para la carga de TMP:
        -- '0' = carga TMP desde DataIn (MemData_In) — modo normal.
        -- '1' = carga TMP desde Op_Data (operando pre-fetched del pipeline).
        Op_Sel      : std_logic;

    end record;

    -- =========================================================================
    -- Constante: INIT_CTRL_BUS
    -- =========================================================================
    -- Define un estado "seguro" o NOP por defecto para todas las señales de control.
    -- Se usa en dos contextos:
    --   1. Reset: garantiza que ningún subsistema realice operaciones no deseadas.
    --   2. Base para microinstrucciones: la UC parte de INIT_CTRL_BUS y solo cambia
    --      los campos necesarios para cada paso de la instrucción en curso,
    --      reduciendo el código de la UC y evitando señales en estado indefinido.
    constant INIT_CTRL_BUS : control_bus_t := (
        -- Data Path
        -- OP_NOP: la ALU no realiza ninguna operación; ACC=0 y flags no cambian.
        -- Seguro porque Write_A='0' y Write_F='0' evitan que el resultado se almacene.
        ALU_Op      => OP_NOP,

        -- ACC_ALU_elected: fuente por defecto del bus de escritura = salida de la ALU.
        -- Inofensivo porque Write_A y Write_B están a '0'; el mux no escribe nada.
        Bus_Op      => ACC_ALU_elected,

        -- Write_A='0': el acumulador A no se modifica; protege R0 durante ciclos de fetch.
        Write_A     => '0',

        -- Write_B='0': ningún registro del banco se modifica; protege el banco durante fetch.
        Write_B     => '0',

        -- Reg_Sel="000": apunta a R0(A) por defecto; no importa porque Write_B='0',
        -- pero se define a un valor conocido para evitar 'U' en simulación.
        Reg_Sel     => (others => '0'), -- R0 por defecto

        -- Write_F='0': el registro de flags F no se modifica durante ciclos sin operación.
        Write_F     => '0',

        -- Flag_Mask=0x00: ningún flag habilitado para escritura; refuerza Write_F='0'.
        Flag_Mask   => (others => '0'),

        -- MDR_WE='0': el MDR no captura datos del bus; evita sobrescribir el dato anterior.
        MDR_WE      => '0',

        -- ALU_Bin_Sel='0': operando B de la ALU desde registros (no desde MDR/inmediato).
        -- Por defecto usa operandos de registro; el inmediato solo se activa cuando corresponde.
        ALU_Bin_Sel => '0', -- Por defecto usa operandos de registro

        -- F_Src_Sel='0': los flags provienen de la ALU de 8 bits por defecto.
        -- Solo se cambia a '1' en instrucciones ADD16/SUB16 que generan flags de 16 bits.
        F_Src_Sel   => '0',

        -- Load_F_Direct='0': no se carga F directamente; solo activo en POP F.
        Load_F_Direct => '0',

        -- Out_Sel="000": selecciona R0(A) como dato de salida por defecto.
        -- Inofensivo porque Mem_WE='0'; la memoria no recibe datos en ciclos de fetch.
        Out_Sel     => "000", -- Por defecto A

        -- Address Path
        -- PC_OP_NOP: el PC no avanza ni se carga; permanece apuntando a la instrucción actual.
        -- La UC activa PC_OP_INC cuando confirma que el fetch es válido (Mem_Ready='1').
        PC_Op       => PC_OP_NOP,

        -- SP_OP_NOP: el SP no se modifica; solo cambia en instrucciones PUSH/POP/CALL/RET.
        SP_Op       => SP_OP_NOP,

        -- ABUS_SRC_PC: el bus de direcciones apunta al PC por defecto (ciclo de fetch).
        -- En ciclos de acceso a datos la UC cambia a ABUS_SRC_EAR, ABUS_SRC_SP, etc.
        ABUS_Sel    => ABUS_SRC_PC, -- Por defecto fetch (PC al bus)

        -- Load_LR='0': el Link Register no captura el PC; solo activo en CALL/BSR.
        Load_LR     => '0',

        -- Load_EAR='0': el EAR no captura el resultado EA; solo activo cuando se calcula EA.
        Load_EAR    => '0',

        -- Load_TMP_L='0': el byte bajo de TMP no se carga; solo activo al consumir el LSB de una dirección.
        Load_TMP_L  => '0',

        -- Load_TMP_H='0': el byte alto de TMP no se carga; solo activo al consumir el MSB de una dirección.
        Load_TMP_H  => '0',

        -- LOAD_SRC_ALU_RES: la fuente de carga para PC/SP es el sumador EA por defecto.
        -- Se cambia a LOAD_SRC_DATA_IN cuando la instrucción usa una dirección de 16 bits literal.
        Load_Src_Sel=> LOAD_SRC_ALU_RES,

        -- Clear_TMP='0': TMP conserva su valor entre ciclos; solo se limpia cuando es necesario.
        Clear_TMP   => '0',

        -- SP_Offset='0': accede al SP directo (byte bajo de la palabra en pila) por defecto.
        -- Se activa a '1' en el segundo ciclo de acceso a pila (byte alto, Little-Endian).
        SP_Offset   => '0',

        -- Force_ZP='0': no se fuerza la página cero; solo activo en modos de direccionamiento ZP.
        Force_ZP    => '0',

        -- EA_A_Sel="00" = EA_A_SRC_TMP: el operando base del sumador EA es TMP por defecto.
        -- Se cambia a PC, REG_AB o SP según el modo de direccionamiento de la instrucción.
        EA_A_Sel    => "00", -- Por defecto EA_A_SRC_TMP

        -- EA_B_Sel=EA_B_SRC_REG_B: el índice del sumador EA es el registro B por defecto.
        -- Cubre el caso más común de modo indexado [base+B].
        EA_B_Sel    => EA_B_SRC_REG_B, -- Por defecto, EA usa RegB

        -- EA_OP_ADD: el sumador EA suma por defecto.
        -- Solo se cambia a EA_OP_SUB en instrucciones SUB16.
        EA_Op       => EA_OP_ADD,

        -- Mem/IO
        -- Mem_WE='0': la memoria no recibe escrituras durante ciclos de fetch/decode.
        -- Mem_RE='0': la memoria no envía datos (excepto el fetch de instrucción, que
        --   se gestiona mediante ABUS_SRC_PC + Mem_RE que la UC activa en fetch).
        Mem_WE      => '0', Mem_RE => '0',

        -- IO_WE='0': el bus de I/O no recibe escrituras.
        -- IO_RE='0': el bus de I/O no envía datos.
        -- Ambos permanecen a '0' excepto en instrucciones IN/OUT específicas.
        IO_WE       => '0', IO_RE  => '0',

        -- Op_Data=0x00: sin dato de operando disponible (no relevante cuando Op_Sel='0').
        Op_Data     => x"00",

        -- Op_Sel='0': carga TMP desde el bus externo DataIn (modo normal de operación).
        Op_Sel      => '0'
    );

    -- =========================================================================
    -- Declaración del componente ControlUnit
    -- =========================================================================
    component ControlUnit_comp is
        Port (
            clk      : in  std_logic;          -- Reloj del sistema
            reset    : in  std_logic;          -- Reset síncrono activo alto
            FlagsIn  : in  status_vector;      -- Estado actual del registro F (para ramificaciones condicionales)
            InstrIn  : in  data_vector;        -- Byte de instrucción leído de memoria (opcode o operando)
            Mem_Ready: in  std_logic; -- Handshake memoria (1=Dato válido/Escritura OK)
                                      -- Permite insertar estados de espera para memorias lentas
            IRQ      : in  std_logic; -- Interrupt Request (Maskable)
                                      -- La UC puede ignorarlo si el flag de habilitación de interrupciones está a '0'
            NMI      : in  std_logic; -- Non-Maskable Interrupt
                                      -- La UC siempre atiende NMI independientemente del flag de interrupciones
            CtrlBus  : out control_bus_t       -- Palabra de control generada para el ciclo actual
        );
    end component ControlUnit_comp;

end package ControlUnit_pkg;
