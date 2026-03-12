library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use work.CONSTANTS_pkg.ALL;
use work.ALU_pkg.ALL;

-- =========================================================================
-- Paquete: AddressPath_pkg
-- Descripción:
--   Define las constantes de control del AddressPath: operaciones del PC y SP,
--   selección del bus de direcciones (ABUS), fuentes del sumador EA (Effective
--   Address) y vectores de interrupción hardcoded.
--
--   El AddressPath es el camino de direcciones de 16 bits que contiene:
--     - PC (Program Counter): apunta a la próxima instrucción a buscar.
--     - SP (Stack Pointer): apunta al tope de la pila; siempre alineado a par.
--     - EAR (Effective Address Register): dirección efectiva estabilizada para LD/ST.
--     - TMP (registro temporal de 16 bits): ensambla direcciones byte a byte desde el bus de datos.
--     - LR (Link Register): guarda la dirección de retorno en CALL/BSR.
--     - Sumador EA de 16 bits: calcula direcciones efectivas en modos indexados y relativos.
-- =========================================================================

package AddressPath_pkg is

    -- =========================================================================
    -- Selección de operación para el PC (Program Counter)
    -- =========================================================================
    -- PC_Op controla cómo se actualiza el PC al flanco de subida del reloj.

    -- PC se mantiene sin cambios (NOP).
    -- Usado en instrucciones multi-ciclo donde el fetch debe detenerse mientras
    -- se accede a memoria (ciclos de lectura/escritura de datos, vectores de interrupción).
    constant PC_OP_NOP  : std_logic_vector(1 downto 0) := "00"; -- Hold

    -- PC = PC + 1 (incremento secuencial).
    -- Avanza al byte siguiente durante el fetch normal de instrucciones de un byte,
    -- o para consumir bytes de operando en instrucciones de 2 o 3 bytes.
    constant PC_OP_INC  : std_logic_vector(1 downto 0) := "01"; -- PC + 1

    -- PC = valor de 16 bits desde Load_Src_Sel (salto absoluto o retorno).
    -- Usado en: JMP abs, CALL abs (carga dirección destino), RET (restaura desde pila),
    -- y en la atención a interrupciones (carga vector NMI o IRQ).
    constant PC_OP_LOAD : std_logic_vector(1 downto 0) := "10"; -- Cargar valor (saltos)

    -- PC[7:0] = byte bajo nuevo, PC[15:8] = PC[15:8] actual (salto dentro de la misma página).
    -- Usado en JPN (Jump in Page): solo reemplaza el byte bajo del PC, preservando
    -- el byte alto. Permite saltos de ±127 dentro del bloque de 256 bytes actual.
    constant PC_OP_LOAD_L : std_logic_vector(1 downto 0) := "11"; -- Cargar solo byte bajo (JPN)

    -- =========================================================================
    -- Selección de operación para el SP (Stack Pointer)
    -- =========================================================================
    -- El SP siempre se mueve de 2 en 2 según la ISA (alineado a par).
    -- La pila almacena palabras de 16 bits (dirección de retorno, par de registros),
    -- por lo que cada PUSH/POP desplaza el SP en ±2, no en ±1.

    -- SP se mantiene sin cambios.
    -- Usado en instrucciones que no acceden a la pila.
    constant SP_OP_NOP  : std_logic_vector(1 downto 0) := "00"; -- Hold

    -- SP = SP + 2 (POP: libera los 2 bytes recién leídos de la pila).
    -- Después de un POP se recuperan 2 bytes y el SP avanza 2 posiciones.
    constant SP_OP_INC  : std_logic_vector(1 downto 0) := "01"; -- SP + 2 (POP)

    -- SP = SP - 2 (PUSH: reserva espacio para los 2 bytes a escribir).
    -- Antes de un PUSH se decrementa el SP para apuntar al nuevo tope de la pila.
    constant SP_OP_DEC  : std_logic_vector(1 downto 0) := "10"; -- SP - 2 (PUSH)

    -- SP = valor de 16 bits desde Load_Src_Sel.
    -- Usado en la instrucción LD SP, #nnnn para inicializar el stack pointer.
    constant SP_OP_LOAD : std_logic_vector(1 downto 0) := "11"; -- Cargar valor

    -- =========================================================================
    -- Selección de la fuente para el Bus de Direcciones (ABUS)
    -- =========================================================================
    -- ABUS_Sel controla el multiplexor que coloca una dirección de 16 bits en el
    -- bus de direcciones de memoria. La selección determina qué registro interno
    -- se usa como puntero de memoria en cada ciclo.

    -- Bus de direcciones = PC (Program Counter).
    -- Seleccionado durante el ciclo de fetch de instrucción: el PC apunta al opcode.
    -- También usado al avanzar el PC para consumir bytes de operando.
    constant ABUS_SRC_PC  : std_logic_vector(2 downto 0) := "000"; -- Fetch instrucciones

    -- Bus de direcciones = SP (Stack Pointer), posiblemente ajustado por SP_Offset.
    -- Seleccionado en PUSH/POP para leer o escribir en la pila.
    -- SP_Offset='1' accede a SP+1 (byte alto de la palabra, orden Little-Endian).
    constant ABUS_SRC_SP  : std_logic_vector(2 downto 0) := "001"; -- Stack Ops

    -- Bus de direcciones = EAR (Effective Address Register, dirección pre-calculada y latched).
    -- Seleccionado en instrucciones LD/ST cuando la dirección efectiva ya fue calculada
    -- en el ciclo anterior y guardada en EAR para estabilizar el bus durante el acceso.
    constant ABUS_SRC_EAR : std_logic_vector(2 downto 0) := "010"; -- Effective Address (LD/ST)

    -- Bus de direcciones = salida directa del sumador EA (sin pasar por EAR).
    -- Seleccionado en el modo indexado [nn+B] cuando la dirección se usa inmediatamente
    -- sin necesidad de latcharla, por ejemplo en accesos de un solo ciclo.
    constant ABUS_SRC_EA_RES : std_logic_vector(2 downto 0) := "011"; -- Salida directa del sumador EA

    -- =========================================================================
    -- Vectores de interrupción (Hardcoded en hardware)
    -- =========================================================================
    -- Las direcciones de los vectores están fijadas en el hardware del AddressPath.
    -- Al seleccionar uno de estos valores, el AddressPath genera la dirección constante
    -- correspondiente en el bus, sin necesidad de leer desde memoria.

    -- Vector NMI byte bajo: dirección fija 0xFFFA.
    -- La ISA reserva 0xFFFA/0xFFFB para el vector de la interrupción no enmascarable (NMI).
    -- Se lee el byte bajo primero (Little-Endian: LSB en dirección menor).
    constant ABUS_SRC_VEC_NMI_L : std_logic_vector(2 downto 0) := "100"; -- 0xFFFA

    -- Vector NMI byte alto: dirección fija 0xFFFB.
    -- Contiene el byte alto (MSB) de la dirección de la rutina NMI.
    constant ABUS_SRC_VEC_NMI_H : std_logic_vector(2 downto 0) := "101"; -- 0xFFFB

    -- Vector IRQ byte bajo: dirección fija 0xFFFE.
    -- La ISA reserva 0xFFFE/0xFFFF para el vector de la interrupción enmascarable (IRQ).
    constant ABUS_SRC_VEC_IRQ_L : std_logic_vector(2 downto 0) := "110"; -- 0xFFFE

    -- Vector IRQ byte alto: dirección fija 0xFFFF.
    -- Contiene el byte alto (MSB) de la dirección de la rutina de servicio IRQ.
    constant ABUS_SRC_VEC_IRQ_H : std_logic_vector(2 downto 0) := "111"; -- 0xFFFF

    -- =========================================================================
    -- Selección de la fuente de datos para cargar PC o SP (Load_Src_Sel)
    -- =========================================================================
    -- Load_Src_Sel determina de dónde proviene el valor de 16 bits que se carga
    -- en el PC (con PC_OP_LOAD) o en el SP (con SP_OP_LOAD).

    -- Fuente = resultado del sumador EA (para saltos relativos PC+rel8).
    -- El sumador calcula PC + desplazamiento con signo de 8 bits extendido a 16.
    -- Usado en instrucciones de salto relativo (BEQ, BNE, BCC, BCS, etc.).
    constant LOAD_SRC_ALU_RES : std_logic := '0'; -- Resultado calculado (saltos relativos, EA)

    -- Fuente = registro TMP (dirección de 16 bits ensamblada byte a byte desde DataIn).
    -- El TMP se carga en dos ciclos: primero Load_TMP_L (byte bajo), luego Load_TMP_H (byte alto).
    -- Usado en instrucciones de carga directa de 16 bits (JMP abs, CALL abs, LD SP,#nn).
    constant LOAD_SRC_DATA_IN : std_logic := '1'; -- Dato directo (LD SP, #nnnn)

    -- =========================================================================
    -- Selección de fuentes para el sumador EA (Effective Address Adder)
    -- Entrada A: operando base (dirección base o registro par)
    -- =========================================================================
    -- EA_A_Sel selecciona el operando "base" (sumando A) del sumador de 16 bits.

    -- Base del sumador = registro TMP (dirección base de 16 bits ensamblada).
    -- Usado cuando la instrucción especifica una dirección absoluta de 16 bits
    -- como base del modo indexado ([TMP + B]).
    constant EA_A_SRC_TMP    : std_logic_vector(1 downto 0) := "00"; -- Base = TMP

    -- Base del sumador = PC actual.
    -- Usado en saltos relativos donde la dirección destino se calcula como PC + rel8.
    -- El desplazamiento (rel8 con signo) se extiende a 16 bits antes de la suma.
    constant EA_A_SRC_PC     : std_logic_vector(1 downto 0) := "01"; -- Base = PC

    -- Base del sumador = par de registros A:B (A=byte alto, B=byte bajo, 16 bits total).
    -- Usado en instrucciones ADD16/SUB16 que operan sobre el par A:B como entero de 16 bits.
    -- A proporciona los bits [15:8] y B los bits [7:0] de la dirección base.
    constant EA_A_SRC_REG_AB : std_logic_vector(1 downto 0) := "10"; -- Base = A:B

    -- Base del sumador = SP (Stack Pointer).
    -- Usado para calcular direcciones relativas al SP (modo de acceso a frame de pila).
    constant EA_A_SRC_SP     : std_logic_vector(1 downto 0) := "11"; -- Base = SP

    -- =========================================================================
    -- Selección de fuentes para el sumador EA
    -- Entrada B: operando índice o desplazamiento
    -- =========================================================================
    -- EA_B_Sel selecciona el operando "índice" (sumando B) del sumador de 16 bits.

    -- Índice = Registro B (R1, 8 bits extendidos a 16 sin signo).
    -- Modo indexado estándar: dirección efectiva = base + B.
    -- B actúa como índice de array o desplazamiento de estructura.
    constant EA_B_SRC_REG_B   : std_logic_vector(1 downto 0) := "00"; -- Índice = Registro B

    -- Índice = dato desde memoria (rel8, desplazamiento de 8 bits con signo extendido a 16).
    -- Modo relativo: el byte de desplazamiento se lee de la siguiente posición de memoria.
    -- Se extiende con signo para permitir saltos hacia adelante y hacia atrás.
    constant EA_B_SRC_DATA_IN : std_logic_vector(1 downto 0) := "01"; -- Índice = Dato de Memoria (rel8)

    -- Índice = 0 (desplazamiento cero, dirección directa sin offset).
    -- Permite usar el sumador EA con un desplazamiento nulo para acceso directo a TMP o SP.
    -- Útil cuando la dirección efectiva es exactamente la base sin ningún índice.
    constant EA_B_SRC_ZERO    : std_logic_vector(1 downto 0) := "10"; -- Índice = 0

    -- Índice = TMP completo (16 bits).
    -- Permite usar TMP como segundo operando de 16 bits en operaciones ADD16/SUB16
    -- donde ambos operandos son direcciones completas de 16 bits.
    constant EA_B_SRC_TMP     : std_logic_vector(1 downto 0) := "11"; -- Índice = TMP (16 bits)

    -- =========================================================================
    -- Operación del sumador EA (EA_Op)
    -- =========================================================================
    -- EA_Op selecciona entre suma y resta en el sumador de 16 bits del AddressPath.

    -- Suma: EA_Result = EA_A + EA_B.
    -- Operación por defecto: cubre todos los modos de direccionamiento indexado,
    -- los saltos relativos hacia adelante y las instrucciones ADD16.
    constant EA_OP_ADD : std_logic := '0';

    -- Resta: EA_Result = EA_A - EA_B.
    -- Usado exclusivamente en instrucciones SUB16 donde el par A:B se decrementa
    -- en el valor de TMP (o de B). Genera flags de 16 bits (fC, fV, fZ).
    constant EA_OP_SUB : std_logic := '1';

    -- =========================================================================
    -- Declaración del componente AddressPath
    -- =========================================================================
    component AddressPath_comp is
        Port (
            clk       : in std_logic;                              -- Reloj del sistema
            reset     : in std_logic;                              -- Reset síncrono activo alto
            DataIn    : in  data_vector;                           -- Byte de datos desde memoria (para TMP y rel8)
            Index_B   : in  data_vector;                           -- Contenido de R1(B) para modo indexado [base+B]
            Index_A   : in  data_vector; -- Registro A para operaciones 16-bit
                                         -- Proporciona A[7:0] como byte alto del par A:B cuando EA_A_SRC_REG_AB
            AddressBus : out address_vector;                       -- Bus de 16 bits hacia el controlador de memoria
            PC_Out    : out address_vector; -- Salida del PC actual hacia DataPath
                                            -- Usada por Out_Sel=PCL/PCH para guardar la dirección de retorno
            EA_Out    : out address_vector; -- Resultado EA hacia DataPath
                                            -- Provee EA[15:0] para Bus_Op=EA_HIGH/EA_LOW (instrucciones 16-bit)
            EA_Flags  : out status_vector;  -- Flags de la operación EA (C, V, Z)
                                            -- Usados cuando F_Src_Sel='1' en instrucciones ADD16/SUB16
            PC_Op     : in  std_logic_vector(1 downto 0);          -- Control de actualización del PC
            SP_Op     : in  std_logic_vector(1 downto 0);          -- Control de actualización del SP (±2)
            ABUS_Sel  : in  std_logic_vector(2 downto 0);          -- Fuente del bus de direcciones
            Load_LR   : in  std_logic;                             -- '1' = capturar PC en el Link Register (CALL, BSR)
            Load_EAR  : in  std_logic;                             -- '1' = capturar resultado EA en EAR (estabiliza dirección LD/ST)
            Load_TMP_L: in  std_logic;                             -- '1' = cargar DataIn en TMP[7:0] (byte bajo de dirección de 16 bits)
            Load_TMP_H: in  std_logic;                             -- '1' = cargar DataIn en TMP[15:8] (byte alto de dirección de 16 bits)
            Load_Src_Sel : in std_logic;                           -- '0'=cargar desde sumador EA; '1'=cargar desde TMP
            Clear_TMP : in  std_logic;                             -- '1' = forzar TMP a 0x0000 (inicio de ensamblaje o página cero)
            SP_Offset : in  std_logic;                             -- '0'=acceder a SP; '1'=acceder a SP+1 (byte alto, Little-Endian)
            Force_ZP  : in  std_logic;                             -- '1' = forzar MSB de dirección EA a 0x00 (modo página cero, wrap 8 bits)
            EA_A_Sel  : in  std_logic_vector(1 downto 0);          -- Selección del operando base del sumador EA
            EA_B_Sel  : in  std_logic_vector(1 downto 0);          -- Selección del operando índice/desplazamiento del sumador EA
            EA_Op     : in  std_logic                              -- '0'=sumar; '1'=restar (para SUB16)
        );
    end component AddressPath_comp;

end package AddressPath_pkg;
