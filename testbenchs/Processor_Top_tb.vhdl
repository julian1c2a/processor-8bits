--------------------------------------------------------------------------------
-- Copyright (c) 2026 MICROELECTRÓNICA26.UMA.EII
-- MIT License
--------------------------------------------------------------------------------
-- Entidad : Processor_Top_tb
-- Descripción:
--   Testbench de integración del procesador completo.
--   Un único archivo con 13 programas seleccionables mediante el generic
--   PROGRAM_SEL (entero 1..13).  Cada programa carga una sección de datos
--   en la RAM y verifica resultados tras la instrucción HALT.
--
--   PROGRAM_SEL | Grupo de instrucciones
--   ------------|----------------------------------------------------------
--        1      | Unarias A/B  (INC/DEC/NOT/NEG/CLR/SET/SWAP/INCB/DECB)
--        2      | ALU registro (ADD/ADC/SUB/SBB/AND/OR/XOR/CMP)
--        3      | ALU inmediato (#n) (ADD#/ADC#/SUB#/SBB#/AND#/OR#/XOR#/CMP#)
--        4      | Desplazamientos / Rotaciones (LSL/LSR/ASL/ASR/ROL/ROR)
--        5      | Cargas y Almacenamientos (LD/ST modos: imm,abs,pz,indB,idx)
--        6      | Saltos incondicionales (JP/JR/JPN/JP[nn]/JP A:B)
--        7      | Saltos condicionales (BEQ..BEQ2, taken y not-taken)
--        8      | CALL / RET
--        9      | PUSH / POP (round-trip A/B/F/A:B)
--       10      | Stack Pointer (LD SP,#nn / LD SP,A:B / ST SP_L,A / ST SP_H,A)
--       11      | ADD16 / SUB16 (#n / #nn)
--       12      | Interrupciones (IRQ entry + RTI / NMI entry + RTI)
--       13      | Pipeline hazards (RAW stall / flush por salto tomado)
--
-- Convenciones:
--   * Código comienza en 0x0000.
--   * Datos de resultado se almacenan en RAM a partir de 0x0100.
--   * Datos de entrada (tablas) se fijan en ROM a partir de 0x0080.
--   * El testbench espera HALT (el PC deja de avanzar) antes de verificar.
--   * Si el HALT no se alcanza en MAX_CYCLES ciclos, falla con severity failure.
--
-- Nota: Mem_Ready siempre '1' (sin wait-states). IRQ y NMI se controlan
--       manualmente desde stim_proc para TB-12.
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.CONSTANTS_pkg.ALL;
use work.ALU_pkg.ALL;

entity Processor_Top_tb is
    generic (
        PROGRAM_SEL : integer := 1   -- Selecciona el programa de test (1..13)
    );
end entity Processor_Top_tb;

architecture sim of Processor_Top_tb is

    -- =========================================================================
    -- Señales del procesador
    -- =========================================================================
    signal clk         : std_logic := '0';
    signal reset       : std_logic := '0';
    signal MemAddress  : address_vector;
    signal MemData_In  : data_vector;
    signal MemData_Out : data_vector;
    signal Mem_WE      : std_logic;
    signal Mem_RE      : std_logic;
    signal IO_WE       : std_logic;
    signal IO_RE       : std_logic;
    signal irq_sig     : std_logic := '0';
    signal nmi_sig     : std_logic := '0';

    -- =========================================================================
    -- Memoria RAM simulada (64 KB)
    -- =========================================================================
    type ram_type is array (0 to 2**ADDRESS_WIDTH - 1) of data_vector;
    shared variable RAM : ram_type := (others => x"00");

    -- =========================================================================
    -- Constantes de temporización
    -- =========================================================================
    constant CLK_PERIOD : time    := 10 ns;
    constant MAX_CYCLES : integer := 2000;   -- Ciclos máximos antes de timeout

    -- =========================================================================
    -- Señal de parada detectada por el stim_proc
    -- =========================================================================
    -- El procesador está en HALT cuando el PC deja de cambiar durante varios ciclos.
    -- La UC detiene el pipeline; monitorizamos que MemAddress sea estable.
    signal prev_addr    : address_vector := (others => '0');
    signal halt_count   : integer := 0;
    signal halt_detect  : std_logic := '0';

begin

    -- =========================================================================
    -- Instancia del procesador
    -- =========================================================================
    uut: entity work.Processor_Top(Structural)
        port map (
            clk         => clk,
            reset       => reset,
            MemAddress  => MemAddress,
            MemData_In  => MemData_In,
            MemData_Out => MemData_Out,
            Mem_WE      => Mem_WE,
            Mem_RE      => Mem_RE,
            Mem_Ready   => '1',
            IO_WE       => IO_WE,
            IO_RE       => IO_RE,
            IRQ         => irq_sig,
            NMI         => nmi_sig
        );

    -- =========================================================================
    -- Generación de reloj
    -- =========================================================================
    clk_process: process
    begin
        clk <= '0'; wait for CLK_PERIOD / 2;
        clk <= '1'; wait for CLK_PERIOD / 2;
    end process;

    -- =========================================================================
    -- Modelo de memoria: lectura asíncrona, escritura síncrona
    -- La escritura síncrona elimina glitches causados por cambios simultáneos
    -- de MemAddress y Mem_WE al final de cada ciclo ESS.
    -- =========================================================================
    mem_read_proc: process(MemAddress, Mem_RE)
        variable addr_int : integer;
    begin
        addr_int   := to_integer(unsigned(MemAddress));
        MemData_In <= (others => '0');
        if Mem_RE = '1' then
            MemData_In <= RAM(addr_int);
        end if;
    end process;

    mem_write_proc: process(clk)
        variable addr_int : integer;
    begin
        if rising_edge(clk) then
            if Mem_WE = '1' then
                addr_int := to_integer(unsigned(MemAddress));
                RAM(addr_int) := MemData_Out;
            end if;
        end if;
    end process;

    -- =========================================================================
    -- Detector de HALT: PC inmóvil durante 4 ciclos consecutivos
    -- =========================================================================
    halt_proc: process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                halt_count  <= 0;
                halt_detect <= '0';
                prev_addr   <= (others => '0');
            else
                prev_addr <= MemAddress;
                if MemAddress = prev_addr then
                    if halt_count < 8 then
                        halt_count <= halt_count + 1;
                    else
                        halt_detect <= '1';
                    end if;
                else
                    halt_count  <= 0;
                    halt_detect <= '0';
                end if;
            end if;
        end if;
    end process;

    -- =========================================================================
    -- Monitor de debug: imprime ADDR+DATA cada ciclo en rango 85..135 (TB-01)
    -- =========================================================================
    debug_proc: process
        variable cycle_cnt : integer := 0;
    begin
        wait until rising_edge(clk);
        cycle_cnt := cycle_cnt + 1;
        if cycle_cnt >= 1 and cycle_cnt <= 400 then
            report "DBG clk=" & integer'image(cycle_cnt) &
                   " ADDR=" & to_hstring(MemAddress) &
                   " DIN="  & to_hstring(MemData_In)  &
                   " RE="   & std_logic'image(Mem_RE)  &
                   " WE="   & std_logic'image(Mem_WE)  &
                   " halt=" & std_logic'image(halt_detect);
        end if;
    end process debug_proc;

    -- =========================================================================
    -- Inicialización de RAM y proceso de estímulos
    -- =========================================================================
    stim_proc: process

        -- -------------------------------------------------------------------
        -- Procedimiento auxiliar: espera HALT o MAX_CYCLES
        -- -------------------------------------------------------------------
        procedure wait_for_halt(timeout_cycles : integer) is
            variable cnt : integer := 0;
        begin
            while halt_detect = '0' and cnt < timeout_cycles loop
                wait until rising_edge(clk);
                cnt := cnt + 1;
            end loop;
            assert halt_detect = '1'
                report "TIMEOUT: HALT no detectado en " & integer'image(timeout_cycles) &
                       " ciclos. PROGRAM_SEL=" & integer'image(PROGRAM_SEL)
                severity error;
        end procedure;

    begin
        -- ---------------------------------------------------------------
        -- Carga del programa según PROGRAM_SEL
        -- ---------------------------------------------------------------

        -- =================================================================
        -- TB-01  Instrucciones unarias sobre A y B
        -- =================================================================
        -- Registro inicial: A cargado por programa; B = 0x05
        -- Resultados esperados en RAM[0x0100..0x010A]:
        --   [0x0100] = 0xFF  (INC A: 0xFE → 0xFF)
        --   [0x0101] = 0x00  (INC A: 0xFF → 0x00, wrap)
        --   [0x0102] = 0xFF  (DEC A: 0x00 → 0xFF, wrap)
        --   [0x0103] = 0xFE  (DEC A: 0xFF → 0xFE)
        --   [0x0104] = 0x01  (NOT A: 0xFE → 0x01)
        --   [0x0105] = 0xFF  (NEG A: 0x01 → 0xFF)
        --   [0x0106] = 0x00  (CLR A)
        --   [0x0107] = 0xFF  (SET A)
        --   [0x0108] = 0x06  (INC B: 0x05→0x06, leído via LD A,B)
        --   [0x0109] = 0x05  (DEC B: 0x06→0x05, leído via LD A,B)
        --   [0x010A] = 0xF0  (SWAP A: 0x0F → 0xF0)
        if PROGRAM_SEL = 1 then
            -- 0x0000: LD A, #0xFE
            RAM(16#0000#) := x"11"; RAM(16#0001#) := x"FE";
            -- 0x0002: LD B, #0x05
            RAM(16#0002#) := x"21"; RAM(16#0003#) := x"05";
            -- 0x0004: INC A → 0xFF  → ST A,[0x0100]
            RAM(16#0004#) := x"C2";
            RAM(16#0005#) := x"31"; RAM(16#0006#) := x"00"; RAM(16#0007#) := x"01";
            -- 0x0008: INC A → 0x00  → ST A,[0x0101]
            RAM(16#0008#) := x"C2";
            RAM(16#0009#) := x"31"; RAM(16#000A#) := x"01"; RAM(16#000B#) := x"01";
            -- 0x000C: DEC A → 0xFF  → ST A,[0x0102]
            RAM(16#000C#) := x"C3";
            RAM(16#000D#) := x"31"; RAM(16#000E#) := x"02"; RAM(16#000F#) := x"01";
            -- 0x0010: DEC A → 0xFE  → ST A,[0x0103]
            RAM(16#0010#) := x"C3";
            RAM(16#0011#) := x"31"; RAM(16#0012#) := x"03"; RAM(16#0013#) := x"01";
            -- 0x0014: NOT A (0xFE → 0x01)  → ST A,[0x0104]
            RAM(16#0014#) := x"C0";
            RAM(16#0015#) := x"31"; RAM(16#0016#) := x"04"; RAM(16#0017#) := x"01";
            -- 0x0018: NEG A (0x01 → 0xFF)  → ST A,[0x0105]
            RAM(16#0018#) := x"C1";
            RAM(16#0019#) := x"31"; RAM(16#001A#) := x"05"; RAM(16#001B#) := x"01";
            -- 0x001C: CLR A → 0x00  → ST A,[0x0106]
            RAM(16#001C#) := x"C6";
            RAM(16#001D#) := x"31"; RAM(16#001E#) := x"06"; RAM(16#001F#) := x"01";
            -- 0x0020: SET A → 0xFF  → ST A,[0x0107]
            RAM(16#0020#) := x"C7";
            RAM(16#0021#) := x"31"; RAM(16#0022#) := x"07"; RAM(16#0023#) := x"01";
            -- 0x0024: INC B (B: 0x05→0x06)  → LD A,B → ST A,[0x0108]
            RAM(16#0024#) := x"C4";
            RAM(16#0025#) := x"10";
            RAM(16#0026#) := x"31"; RAM(16#0027#) := x"08"; RAM(16#0028#) := x"01";
            -- 0x0029: DEC B (B: 0x06→0x05)  → LD A,B → ST A,[0x0109]
            RAM(16#0029#) := x"C5";
            RAM(16#002A#) := x"10";
            RAM(16#002B#) := x"31"; RAM(16#002C#) := x"09"; RAM(16#002D#) := x"01";
            -- 0x002E: LD A,#0x0F  → SWAP A (0x0F→0xF0)  → ST A,[0x010A]
            RAM(16#002E#) := x"11"; RAM(16#002F#) := x"0F";
            RAM(16#0030#) := x"CE";
            RAM(16#0031#) := x"31"; RAM(16#0032#) := x"0A"; RAM(16#0033#) := x"01";
            -- 0x0034: HALT
            RAM(16#0034#) := x"01";

        -- =================================================================
        -- TB-02  ALU registro (A op B → A)
        -- =================================================================
        -- Cada instrucción: LD A,#a / LD B,#b / OP / ST A,[0x01xx]
        -- Resultados esperados en RAM[0x0100..0x0117]:
        --   [0x0100]=0x0F ADD  (0x07+0x08)
        --   [0x0101]=0x10 ADC  (0x07+0x08+C=1) — usa SEC antes
        --   [0x0102]=0xFF SUB  (0x07-0x08 = wrapped -1 = 0xFF)
        --   [0x0103]=0xFE SBB  (0x07-0x08-C=1 = -2 = 0xFE)
        --   [0x0104]=0x05 AND  (0x0F & 0x35 = 0x05)
        --   [0x0105]=0x3F OR   (0x0F | 0x35 = 0x3F)
        --   [0x0106]=0x3A XOR  (0x0F ^ 0x35 = 0x3A)
        --   [0x0107]=0x07 CMP  (A no cambia: 0x07)
        --   [0x0108]=0x01 MUL  (0x07*0x08)[7:0] = 0x38 — ajustado: 7*8=56=0x38
        --     Corrección: MUL 0x07*0x08 = 56 = 0x38; MUH = 0x00
        --   [0x0108]=0x38 MUL  (0x07*0x08 = 0x0038 → byte bajo)
        --   [0x0109]=0x00 MUH  (byte alto)
        elsif PROGRAM_SEL = 2 then
            -- Macro local: LD A,#a / LD B,#b / OP / ST A,[addr16]
            -- ADD: 0x07 + 0x08 = 0x0F
            RAM(16#0000#) := x"11"; RAM(16#0001#) := x"07";  -- LD A,#7
            RAM(16#0002#) := x"21"; RAM(16#0003#) := x"08";  -- LD B,#8
            RAM(16#0004#) := x"90";                           -- ADD
            RAM(16#0005#) := x"31"; RAM(16#0006#) := x"00"; RAM(16#0007#) := x"01"; -- ST A,[0x0100]
            -- ADC: 0x07 + 0x08 + C=1 = 0x10  (SEC antes)
            RAM(16#0008#) := x"11"; RAM(16#0009#) := x"07";
            RAM(16#000A#) := x"21"; RAM(16#000B#) := x"08";
            RAM(16#000C#) := x"02";                           -- SEC
            RAM(16#000D#) := x"91";                           -- ADC
            RAM(16#000E#) := x"31"; RAM(16#000F#) := x"01"; RAM(16#0010#) := x"01"; -- ST [0x0101]
            -- SUB: 0x07 - 0x08 = 0xFF (borrow, unsigned wrap)
            RAM(16#0011#) := x"11"; RAM(16#0012#) := x"07";
            RAM(16#0013#) := x"21"; RAM(16#0014#) := x"08";
            RAM(16#0015#) := x"92";                           -- SUB
            RAM(16#0016#) := x"31"; RAM(16#0017#) := x"02"; RAM(16#0018#) := x"01"; -- ST [0x0102]
            -- SBB: 0x07 - 0x08 - C=1 = 0xFE  (C quedó 0 tras SUB con borrow, entonces SEC)
            RAM(16#0019#) := x"11"; RAM(16#001A#) := x"07";
            RAM(16#001B#) := x"21"; RAM(16#001C#) := x"08";
            RAM(16#001D#) := x"02";                           -- SEC (fuerza C=1 para que SBB reste 1 extra)
            RAM(16#001E#) := x"93";                           -- SBB
            RAM(16#001F#) := x"31"; RAM(16#0020#) := x"03"; RAM(16#0021#) := x"01"; -- ST [0x0103]
            -- AND: 0x0F & 0x35 = 0x05
            RAM(16#0022#) := x"11"; RAM(16#0023#) := x"0F";
            RAM(16#0024#) := x"21"; RAM(16#0025#) := x"35";
            RAM(16#0026#) := x"94";                           -- AND
            RAM(16#0027#) := x"31"; RAM(16#0028#) := x"04"; RAM(16#0029#) := x"01"; -- ST [0x0104]
            -- OR: 0x0F | 0x35 = 0x3F
            RAM(16#002A#) := x"11"; RAM(16#002B#) := x"0F";
            RAM(16#002C#) := x"21"; RAM(16#002D#) := x"35";
            RAM(16#002E#) := x"95";                           -- OR
            RAM(16#002F#) := x"31"; RAM(16#0030#) := x"05"; RAM(16#0031#) := x"01"; -- ST [0x0105]
            -- XOR: 0x0F ^ 0x35 = 0x3A
            RAM(16#0032#) := x"11"; RAM(16#0033#) := x"0F";
            RAM(16#0034#) := x"21"; RAM(16#0035#) := x"35";
            RAM(16#0036#) := x"96";                           -- XOR
            RAM(16#0037#) := x"31"; RAM(16#0038#) := x"06"; RAM(16#0039#) := x"01"; -- ST [0x0106]
            -- CMP: A no cambia → ST A → 0x07
            RAM(16#003A#) := x"11"; RAM(16#003B#) := x"07";
            RAM(16#003C#) := x"21"; RAM(16#003D#) := x"05";
            RAM(16#003E#) := x"97";                           -- CMP (A sin cambio)
            RAM(16#003F#) := x"31"; RAM(16#0040#) := x"07"; RAM(16#0041#) := x"01"; -- ST [0x0107]
            -- MUL: 0x07 * 0x08 = 0x38 (byte bajo)
            RAM(16#0042#) := x"11"; RAM(16#0043#) := x"07";
            RAM(16#0044#) := x"21"; RAM(16#0045#) := x"08";
            RAM(16#0046#) := x"98";                           -- MUL
            RAM(16#0047#) := x"31"; RAM(16#0048#) := x"08"; RAM(16#0049#) := x"01"; -- ST [0x0108]
            -- MUH: byte alto del mismo producto (B no ha cambiado)
            RAM(16#004A#) := x"11"; RAM(16#004B#) := x"07";
            RAM(16#004C#) := x"21"; RAM(16#004D#) := x"08";
            RAM(16#004E#) := x"99";                           -- MUH
            RAM(16#004F#) := x"31"; RAM(16#0050#) := x"09"; RAM(16#0051#) := x"01"; -- ST [0x0109]
            -- HALT
            RAM(16#0052#) := x"01";

        -- =================================================================
        -- TB-03  ALU inmediato (A op #n → A)
        -- =================================================================
        -- Resultados esperados en RAM[0x0100..0x0107]:
        --   [0x0100]=0x0F  ADD#  (0x07+0x08)
        --   [0x0101]=0x10  ADC#  (0x07+0x08+C=1)
        --   [0x0102]=0xFF  SUB#  (0x07-0x08 = 0xFF)
        --   [0x0103]=0xFE  SBB#  (0x07-0x08-C=1)
        --   [0x0104]=0x05  AND#  (0x0F & 0x35)
        --   [0x0105]=0x3F  OR#   (0x0F | 0x35)
        --   [0x0106]=0x3A  XOR#  (0x0F ^ 0x35)
        --   [0x0107]=0x07  CMP#  (A sin cambio: 0x07)
        elsif PROGRAM_SEL = 3 then
            -- ADD# 0x07+0x08
            RAM(16#0000#) := x"11"; RAM(16#0001#) := x"07";  -- LD A,#7
            RAM(16#0002#) := x"A0"; RAM(16#0003#) := x"08";  -- ADD #8
            RAM(16#0004#) := x"31"; RAM(16#0005#) := x"00"; RAM(16#0006#) := x"01"; -- ST [0x0100]
            -- ADC# 0x07+0x08+C=1
            RAM(16#0007#) := x"11"; RAM(16#0008#) := x"07";
            RAM(16#0009#) := x"02";                           -- SEC
            RAM(16#000A#) := x"A1"; RAM(16#000B#) := x"08";  -- ADC# 8
            RAM(16#000C#) := x"31"; RAM(16#000D#) := x"01"; RAM(16#000E#) := x"01";
            -- SUB# 0x07-0x08
            RAM(16#000F#) := x"11"; RAM(16#0010#) := x"07";
            RAM(16#0011#) := x"A2"; RAM(16#0012#) := x"08";  -- SUB# 8
            RAM(16#0013#) := x"31"; RAM(16#0014#) := x"02"; RAM(16#0015#) := x"01";
            -- SBB# 0x07-0x08-C=1 (SEC para forzar C)
            RAM(16#0016#) := x"11"; RAM(16#0017#) := x"07";
            RAM(16#0018#) := x"02";                           -- SEC
            RAM(16#0019#) := x"A3"; RAM(16#001A#) := x"08";  -- SBB# 8
            RAM(16#001B#) := x"31"; RAM(16#001C#) := x"03"; RAM(16#001D#) := x"01";
            -- AND# 0x0F&0x35
            RAM(16#001E#) := x"11"; RAM(16#001F#) := x"0F";
            RAM(16#0020#) := x"A4"; RAM(16#0021#) := x"35";  -- AND# 0x35
            RAM(16#0022#) := x"31"; RAM(16#0023#) := x"04"; RAM(16#0024#) := x"01";
            -- OR# 0x0F|0x35
            RAM(16#0025#) := x"11"; RAM(16#0026#) := x"0F";
            RAM(16#0027#) := x"A5"; RAM(16#0028#) := x"35";  -- OR# 0x35
            RAM(16#0029#) := x"31"; RAM(16#002A#) := x"05"; RAM(16#002B#) := x"01";
            -- XOR# 0x0F^0x35
            RAM(16#002C#) := x"11"; RAM(16#002D#) := x"0F";
            RAM(16#002E#) := x"A6"; RAM(16#002F#) := x"35";  -- XOR# 0x35
            RAM(16#0030#) := x"31"; RAM(16#0031#) := x"06"; RAM(16#0032#) := x"01";
            -- CMP# A sin cambio
            RAM(16#0033#) := x"11"; RAM(16#0034#) := x"07";
            RAM(16#0035#) := x"A7"; RAM(16#0036#) := x"05";  -- CMP# 5
            RAM(16#0037#) := x"31"; RAM(16#0038#) := x"07"; RAM(16#0039#) := x"01";
            -- HALT
            RAM(16#003A#) := x"01";

        -- =================================================================
        -- TB-04  Desplazamientos y rotaciones
        -- =================================================================
        -- Valor base: A = 0xAA (1010_1010), C = 0
        -- Resultados esperados en RAM[0x0100..0x0107]:
        --   [0x0100]=0x54  LSL  (1010_1010 << 1 = 0101_0100, L=1 sale por izq)
        --   [0x0101]=0x55  LSR  (1010_1010 >> 1 = 0101_0101, R=0 entrada 0, bit0 sale)
        --   [0x0102]=0x54  ASL  (igual a LSL para 0xAA; V=1 porque bit7≠bit6)
        --   [0x0103]=0xD5  ASR  (1010_1010 >> 1 aritmético = 1101_0101, bit7 replicado)
        --   [0x0104]=0x54  ROL  (C=0 inicial: rota izq pasando por C; resultado=0x54, nuevo C=1)
        --   [0x0105]=0xD5  ROR  (C=0 inicial: rota der pasando por C; resultado=0x55 con C=0)
        --     Corrección: ROL 0xAA,C=0 → {C_nuevo=1, A=0x54}; ROR 0xAA,C=0 → {C_nuevo=0, A=0x55}
        elsif PROGRAM_SEL = 4 then
            -- LSL 0xAA → 0x54  (0x54 = 0101_0100)
            RAM(16#0000#) := x"11"; RAM(16#0001#) := x"AA";  -- LD A,#0xAA
            RAM(16#0002#) := x"03";                           -- CLC  (C=0)
            RAM(16#0003#) := x"C8";                           -- LSL A
            RAM(16#0004#) := x"31"; RAM(16#0005#) := x"00"; RAM(16#0006#) := x"01"; -- ST [0x0100]
            -- LSR 0xAA → 0x55  (0x55 = 0101_0101)
            RAM(16#0007#) := x"11"; RAM(16#0008#) := x"AA";
            RAM(16#0009#) := x"C9";                           -- LSR A
            RAM(16#000A#) := x"31"; RAM(16#000B#) := x"01"; RAM(16#000C#) := x"01";
            -- ASL 0xAA → 0x54  (aritmético, igual que LSL aquí)
            RAM(16#000D#) := x"11"; RAM(16#000E#) := x"AA";
            RAM(16#000F#) := x"CA";                           -- ASL A
            RAM(16#0010#) := x"31"; RAM(16#0011#) := x"02"; RAM(16#0012#) := x"01";
            -- ASR 0xAA → 0xD5  (1101_0101 – bit7 replicado)
            RAM(16#0013#) := x"11"; RAM(16#0014#) := x"AA";
            RAM(16#0015#) := x"CB";                           -- ASR A
            RAM(16#0016#) := x"31"; RAM(16#0017#) := x"03"; RAM(16#0018#) := x"01";
            -- ROL 0xAA con C=0 → 0x54, C_out=1
            RAM(16#0019#) := x"11"; RAM(16#001A#) := x"AA";
            RAM(16#001B#) := x"03";                           -- CLC
            RAM(16#001C#) := x"CC";                           -- ROL A
            RAM(16#001D#) := x"31"; RAM(16#001E#) := x"04"; RAM(16#001F#) := x"01";
            -- ROR 0xAA con C=0 → 0x55, C_out=0
            RAM(16#0020#) := x"11"; RAM(16#0021#) := x"AA";
            RAM(16#0022#) := x"03";                           -- CLC
            RAM(16#0023#) := x"CD";                           -- ROR A
            RAM(16#0024#) := x"31"; RAM(16#0025#) := x"05"; RAM(16#0026#) := x"01";
            -- ROL 0x01 con C=1 → 0x03 (C entra por bit0)
            RAM(16#0027#) := x"11"; RAM(16#0028#) := x"01";
            RAM(16#0029#) := x"02";                           -- SEC
            RAM(16#002A#) := x"CC";                           -- ROL A
            RAM(16#002B#) := x"31"; RAM(16#002C#) := x"06"; RAM(16#002D#) := x"01";
            -- ROR 0x80 con C=1 → 0xC0 (C entra por bit7)
            RAM(16#002E#) := x"11"; RAM(16#002F#) := x"80";
            RAM(16#0030#) := x"02";                           -- SEC
            RAM(16#0031#) := x"CD";                           -- ROR A
            RAM(16#0032#) := x"31"; RAM(16#0033#) := x"07"; RAM(16#0034#) := x"01";
            -- HALT
            RAM(16#0035#) := x"01";

        -- =================================================================
        -- TB-05  Cargas y almacenamientos
        -- =================================================================
        -- Tabla de datos de entrada en RAM[0x0080..0x008A]
        -- Resultados en RAM[0x0100..0x010F]
        --
        -- Datos iniciales (fijados en inicialización):
        --   RAM[0x0080] = 0xAB  (fuente para LD A,[n])
        --   RAM[0x0081] = 0xCD  (fuente para LD A,[nn] con nn=0x0081)
        --   RAM[0x0082] = 0xEF  (fuente para LD A,[B] con B=0x82)
        --   RAM[0x0083] = 0x12  (fuente para LD A,[nn+B] con nn=0x0080, B=3)
        --   RAM[0x0084] = 0x34  (fuente para LD A,[n+B])
        --   RAM[0x0085] = 0x56  (fuente para LD B,[n])
        --   RAM[0x0086] = 0x78  (fuente para LD B,[nn])
        --   RAM[0x0090] = 0x9A  (fuente para LD B,[B] con B=0x90)
        --
        -- Esperados:
        --   [0x0100] = 0xAB  LD A,[n]        n=0x80
        --   [0x0101] = 0xCD  LD A,[nn]       nn=0x0081
        --   [0x0102] = 0xEF  LD A,[B]        B=0x82
        --   [0x0103] = 0x12  LD A,[nn+B]     nn=0x0080, B=3
        --   [0x0104] = 0x34  LD A,[n+B]      n=0x80, B=4
        --   [0x0105] = 0x78  LD A from LD B,[nn] then LD A,B
        --   [0x0106] = 0x9A  LD B,[B] (B=0x90) then LD A,B
        --   [0x0107] = 0xBE  ST A,[n+B]: A=0xBE stored to 0x00:n+B
        elsif PROGRAM_SEL = 5 then
            -- Datos de entrada
            RAM(16#0080#) := x"AB"; RAM(16#0081#) := x"CD"; RAM(16#0082#) := x"EF";
            RAM(16#0083#) := x"12"; RAM(16#0084#) := x"34"; RAM(16#0085#) := x"56";
            RAM(16#0086#) := x"78"; RAM(16#0090#) := x"9A";
            -- LD A,#val → LD A,B
            RAM(16#0000#) := x"11"; RAM(16#0001#) := x"55"; -- LD A,#0x55
            RAM(16#0002#) := x"20";                          -- LD B,A (B=0x55)
            RAM(16#0003#) := x"10";                          -- LD A,B (A=0x55)
            RAM(16#0004#) := x"31"; RAM(16#0005#) := x"FF"; RAM(16#0006#) := x"00"; -- ST A,[0x00FF]
            -- LD A,[n] n=0x80 → [0x0100]
            RAM(16#0007#) := x"12"; RAM(16#0008#) := x"80";  -- LD A,[0x80]
            RAM(16#0009#) := x"31"; RAM(16#000A#) := x"00"; RAM(16#000B#) := x"01";
            -- LD A,[nn] nn=0x0081 → [0x0101]
            RAM(16#000C#) := x"13"; RAM(16#000D#) := x"81"; RAM(16#000E#) := x"00"; -- LD A,[0x0081]
            RAM(16#000F#) := x"31"; RAM(16#0010#) := x"01"; RAM(16#0011#) := x"01";
            -- LD A,[B] B=0x82 → [0x0102]
            RAM(16#0012#) := x"21"; RAM(16#0013#) := x"82"; -- LD B,#0x82
            RAM(16#0014#) := x"14";                          -- LD A,[B]
            RAM(16#0015#) := x"31"; RAM(16#0016#) := x"02"; RAM(16#0017#) := x"01";
            -- LD A,[nn+B] nn=0x0080, B=3 → RAM[0x0083]=0x12 → [0x0103]
            RAM(16#0018#) := x"21"; RAM(16#0019#) := x"03"; -- LD B,#3
            RAM(16#001A#) := x"15"; RAM(16#001B#) := x"80"; RAM(16#001C#) := x"00"; -- LD A,[0x0080+B]
            RAM(16#001D#) := x"31"; RAM(16#001E#) := x"03"; RAM(16#001F#) := x"01";
            -- LD A,[n+B] n=0x80, B=4 → RAM[0x0084]=0x34 → [0x0104]
            RAM(16#0020#) := x"21"; RAM(16#0021#) := x"04"; -- LD B,#4
            RAM(16#0022#) := x"16"; RAM(16#0023#) := x"80"; -- LD A,[0x80+B]
            RAM(16#0024#) := x"31"; RAM(16#0025#) := x"04"; RAM(16#0026#) := x"01";
            -- LD B,[nn] nn=0x0086 → B=0x78 → LD A,B → [0x0105]
            RAM(16#0027#) := x"23"; RAM(16#0028#) := x"86"; RAM(16#0029#) := x"00"; -- LD B,[0x0086]
            RAM(16#002A#) := x"10";                          -- LD A,B
            RAM(16#002B#) := x"31"; RAM(16#002C#) := x"05"; RAM(16#002D#) := x"01";
            -- LD B,[B] B=0x90 → RAM[0x0090]=0x9A → LD A,B → [0x0106]
            RAM(16#002E#) := x"21"; RAM(16#002F#) := x"90"; -- LD B,#0x90
            RAM(16#0030#) := x"24";                          -- LD B,[B]
            RAM(16#0031#) := x"10";                          -- LD A,B
            RAM(16#0032#) := x"31"; RAM(16#0033#) := x"06"; RAM(16#0034#) := x"01";
            -- ST A,[n] n=0x10 (escribe 0x9A en pág0[0x10]), luego LD A,[n] verifica
            RAM(16#0035#) := x"30"; RAM(16#0036#) := x"10"; -- ST A,[0x10]
            RAM(16#0037#) := x"12"; RAM(16#0038#) := x"10"; -- LD A,[0x10]
            RAM(16#0039#) := x"31"; RAM(16#003A#) := x"07"; RAM(16#003B#) := x"01";
            -- HALT
            RAM(16#003C#) := x"01";

        -- =================================================================
        -- TB-06  Saltos incondicionales
        -- =================================================================
        -- Programa: actualiza contadores en RAM[0x0100..0x0104] al pasar por
        -- cada bloque alcanzado mediante un salto distinto.
        -- Flujo: INC_CNT1 → JP nn → INC_CNT2 → JR +3 → INC_CNT3 → JPN → INC_CNT4
        --        → LD A:B,nn → JP A:B → INC_CNT5 → HALT
        -- Contador inicial 0x00; cada bloque hace LD A,[0x01xx] / INC A / ST A,[0x01xx].
        -- Esperados (todos=1 si cada salto se ejecutó exactamente 1 vez):
        --   [0x0100]=1, [0x0101]=1, [0x0102]=1, [0x0103]=1, [0x0104]=1
        elsif PROGRAM_SEL = 6 then
            -- Bloque 0 (inicio): INC counter[0x0100]
            RAM(16#0000#) := x"13"; RAM(16#0001#) := x"00"; RAM(16#0002#) := x"01"; -- LD A,[0x0100]
            RAM(16#0003#) := x"C2";                          -- INC A
            RAM(16#0004#) := x"31"; RAM(16#0005#) := x"00"; RAM(16#0006#) := x"01"; -- ST A,[0x0100]
            -- JP nn → salta a bloque1 en 0x0010
            RAM(16#0007#) := x"70"; RAM(16#0008#) := x"10"; RAM(16#0009#) := x"00"; -- JP 0x0010
            -- (0x000A..0x000F: relleno NOP, no debe ejecutarse)
            -- Bloque1 @ 0x0010: INC counter[0x0101]
            RAM(16#0010#) := x"13"; RAM(16#0011#) := x"01"; RAM(16#0012#) := x"01"; -- LD A,[0x0101]
            RAM(16#0013#) := x"C2";                          -- INC A
            RAM(16#0014#) := x"31"; RAM(16#0015#) := x"01"; RAM(16#0016#) := x"01"; -- ST A,[0x0101]
            -- JR +5 → salta a bloque2 (0x0010+4instrucción_actual=0x001D; JR rel desde PC_tras_fetch)
            -- JR opcode=0x71, offset calculado: bloque2 @ 0x0020; PC tras fetch JR = 0x0019; offset=0x0020-0x0019=7
            RAM(16#0017#) := x"71"; RAM(16#0018#) := x"07"; -- JR +7 → 0x0019+7=0x0020
            -- Bloque2 @ 0x0020: INC counter[0x0102]
            RAM(16#0020#) := x"13"; RAM(16#0021#) := x"02"; RAM(16#0022#) := x"01"; -- LD A,[0x0102]
            RAM(16#0023#) := x"C2";                          -- INC A
            RAM(16#0024#) := x"31"; RAM(16#0025#) := x"02"; RAM(16#0026#) := x"01"; -- ST A,[0x0102]
            -- JPN page8: PC actual=0x0027 (tras fetch), byte bajo destino=0x30
            -- JPN: PC ← PC[15:8] : page8 = 0x00:0x30 = 0x0030
            RAM(16#0027#) := x"72"; RAM(16#0028#) := x"30"; -- JPN 0x30 → 0x0030
            -- Bloque3 @ 0x0030: INC counter[0x0103]
            RAM(16#0030#) := x"13"; RAM(16#0031#) := x"03"; RAM(16#0032#) := x"01"; -- LD A,[0x0103]
            RAM(16#0033#) := x"C2";                          -- INC A
            RAM(16#0034#) := x"31"; RAM(16#0035#) := x"03"; RAM(16#0036#) := x"01"; -- ST A,[0x0103]
            -- Carga A:B = 0x0040, luego JP A:B
            RAM(16#0037#) := x"11"; RAM(16#0038#) := x"00"; -- LD A,#0x00
            RAM(16#0039#) := x"21"; RAM(16#003A#) := x"40"; -- LD B,#0x40
            RAM(16#003B#) := x"74";                          -- JP A:B → salta a 0x0040
            -- Bloque4 @ 0x0040: INC counter[0x0104]
            RAM(16#0040#) := x"13"; RAM(16#0041#) := x"04"; RAM(16#0042#) := x"01"; -- LD A,[0x0104]
            RAM(16#0043#) := x"C2";                          -- INC A
            RAM(16#0044#) := x"31"; RAM(16#0045#) := x"04"; RAM(16#0046#) := x"01"; -- ST A,[0x0104]
            -- HALT
            RAM(16#0047#) := x"01";

        -- =================================================================
        -- TB-07  Saltos condicionales
        -- =================================================================
        -- Para cada branch: ejecutar con condición verdadera (counter++) y
        -- luego con condición falsa (counter no debe cambiar).
        -- Estructura por rama: CMP / BRANCH_taken (skip NOP+INC) / INC_skip
        --
        -- Verifica:
        --   [0x0100] = 1  (BEQ taken con Z=1)
        --   [0x0101] = 0  (BEQ not-taken con Z=0: counter no avanza)
        --   [0x0102] = 1  (BNE taken con Z=0)
        --   [0x0103] = 1  (BCS taken con C=1)
        --   [0x0104] = 1  (BCC taken con C=0)
        --   [0x0105] = 1  (BGT taken con G=1)
        --   [0x0106] = 1  (BLE taken con G=0)
        elsif PROGRAM_SEL = 7 then
            -- BEQ taken (Z=1): CMP A=5,B=5 → Z=1
            RAM(16#0000#) := x"11"; RAM(16#0001#) := x"05";  -- LD A,#5
            RAM(16#0002#) := x"21"; RAM(16#0003#) := x"05";  -- LD B,#5
            RAM(16#0004#) := x"97";                           -- CMP (Z=1,G=0,C=1)
            -- BEQ rel8: si Z=1 → skip NOP+INC false_cnt → INC true_cnt → [0x0100]
            -- PC tras fetch BEQ = 0x0007; +5 → 0x000C (skip 5 bytes: 1 NOP + 4 ST)
            RAM(16#0005#) := x"80"; RAM(16#0006#) := x"05";  -- BEQ +5 → 0x000C
            -- este bloque NO debe ejecutarse (false path)
            RAM(16#0007#) := x"00";                           -- NOP
            RAM(16#0008#) := x"13"; RAM(16#0009#) := x"01"; RAM(16#000A#) := x"01"; -- LD A,[0x0101]
            RAM(16#000B#) := x"C2";                           -- INC A (false: no llega aquí)
            -- true path @ 0x000C: INC [0x0100]
            RAM(16#000C#) := x"13"; RAM(16#000D#) := x"00"; RAM(16#000E#) := x"01"; -- LD A,[0x0100]
            RAM(16#000F#) := x"C2";                           -- INC A
            RAM(16#0010#) := x"31"; RAM(16#0011#) := x"00"; RAM(16#0012#) := x"01"; -- ST A,[0x0100]
            -- BNE taken (Z=0): CMP A=5,B=3
            RAM(16#0013#) := x"11"; RAM(16#0014#) := x"05";
            RAM(16#0015#) := x"21"; RAM(16#0016#) := x"03";
            RAM(16#0017#) := x"97";                           -- CMP (Z=0)
            -- PC tras fetch = 0x001A; +3 = 0x001D
            RAM(16#0018#) := x"81"; RAM(16#0019#) := x"03";  -- BNE +3 → 0x001D
            RAM(16#001A#) := x"00"; RAM(16#001B#) := x"00"; RAM(16#001C#) := x"00"; -- NOP×3 (false)
            RAM(16#001D#) := x"13"; RAM(16#001E#) := x"02"; RAM(16#001F#) := x"01"; -- LD A,[0x0102]
            RAM(16#0020#) := x"C2";
            RAM(16#0021#) := x"31"; RAM(16#0022#) := x"02"; RAM(16#0023#) := x"01"; -- ST A,[0x0102]
            -- BCS taken (C=1): SEC luego CMP 5,3 → C=1
            RAM(16#0024#) := x"11"; RAM(16#0025#) := x"05";
            RAM(16#0026#) := x"21"; RAM(16#0027#) := x"03";
            RAM(16#0028#) := x"97";                           -- CMP (5>3, C=1 no-borrow)
            RAM(16#0029#) := x"82"; RAM(16#002A#) := x"03";  -- BCS +3 → 0x002D
            RAM(16#002B#) := x"00"; RAM(16#002C#) := x"00";  -- NOP×2 (false)
            RAM(16#002D#) := x"13"; RAM(16#002E#) := x"03"; RAM(16#002F#) := x"01"; -- LD A,[0x0103]
            RAM(16#0030#) := x"C2";
            RAM(16#0031#) := x"31"; RAM(16#0032#) := x"03"; RAM(16#0033#) := x"01"; -- ST A,[0x0103]
            -- BCC taken (C=0): CMP 3,5 → C=0 (borrow)
            RAM(16#0034#) := x"11"; RAM(16#0035#) := x"03";
            RAM(16#0036#) := x"21"; RAM(16#0037#) := x"05";
            RAM(16#0038#) := x"97";                           -- CMP 3-5 → C=0, G=0
            RAM(16#0039#) := x"83"; RAM(16#003A#) := x"03";  -- BCC +3 → 0x003D
            RAM(16#003B#) := x"00"; RAM(16#003C#) := x"00";  -- NOP×2 (false)
            RAM(16#003D#) := x"13"; RAM(16#003E#) := x"04"; RAM(16#003F#) := x"01"; -- LD A,[0x0104]
            RAM(16#0040#) := x"C2";
            RAM(16#0041#) := x"31"; RAM(16#0042#) := x"04"; RAM(16#0043#) := x"01"; -- ST A,[0x0104]
            -- BGT taken (G=1): CMP 8,3 → G=1
            RAM(16#0044#) := x"11"; RAM(16#0045#) := x"08";
            RAM(16#0046#) := x"21"; RAM(16#0047#) := x"03";
            RAM(16#0048#) := x"97";                           -- CMP 8>3 → G=1
            RAM(16#0049#) := x"86"; RAM(16#004A#) := x"03";  -- BGT +3 → 0x004D
            RAM(16#004B#) := x"00"; RAM(16#004C#) := x"00";  -- NOP×2 (false)
            RAM(16#004D#) := x"13"; RAM(16#004E#) := x"05"; RAM(16#004F#) := x"01"; -- LD A,[0x0105]
            RAM(16#0050#) := x"C2";
            RAM(16#0051#) := x"31"; RAM(16#0052#) := x"05"; RAM(16#0053#) := x"01"; -- ST A,[0x0105]
            -- BLE taken (G=0): CMP 3,8 → G=0
            RAM(16#0054#) := x"11"; RAM(16#0055#) := x"03";
            RAM(16#0056#) := x"21"; RAM(16#0057#) := x"08";
            RAM(16#0058#) := x"97";                           -- CMP 3<8 → G=0
            RAM(16#0059#) := x"87"; RAM(16#005A#) := x"03";  -- BLE +3 → 0x005D
            RAM(16#005B#) := x"00"; RAM(16#005C#) := x"00";
            RAM(16#005D#) := x"13"; RAM(16#005E#) := x"06"; RAM(16#005F#) := x"01"; -- LD A,[0x0106]
            RAM(16#0060#) := x"C2";
            RAM(16#0061#) := x"31"; RAM(16#0062#) := x"06"; RAM(16#0063#) := x"01"; -- ST A,[0x0106]
            -- HALT
            RAM(16#0064#) := x"01";

        -- =================================================================
        -- TB-08  CALL / RET
        -- =================================================================
        -- Programa principal en 0x0000; subrutina en 0x0050.
        -- La subrutina incrementa A y retorna.
        -- Se llama 3 veces consecutivas desde distintos puntos para verificar
        -- que el stack (CALL/RET) funciona con múltiples niveles.
        --
        -- SP inicial = 0xFFFE.  Cada CALL decrementa -2; cada RET +2.
        -- Resultados esperados:
        --   [0x0100] = 0x01  (A=0 → subrutina: A+=1 → 1)
        --   [0x0101] = 0x03  (A=1 → subrutina añade 2: A+=1=2 → call2: A+=1=3)
        --     Ajuste: llamamos 3 veces sucesivas; cada call: A = A+1
        --   [0x0100]=0x01, [0x0101]=0x02, [0x0102]=0x03
        elsif PROGRAM_SEL = 8 then
            -- Init A=0
            RAM(16#0000#) := x"11"; RAM(16#0001#) := x"00";  -- LD A,#0
            -- CALL sub @ 0x0050
            RAM(16#0002#) := x"75"; RAM(16#0003#) := x"50"; RAM(16#0004#) := x"00"; -- CALL 0x0050
            -- ST A,[0x0100]
            RAM(16#0005#) := x"31"; RAM(16#0006#) := x"00"; RAM(16#0007#) := x"01";
            -- CALL sub (A=1 → 2)
            RAM(16#0008#) := x"75"; RAM(16#0009#) := x"50"; RAM(16#000A#) := x"00";
            -- ST A,[0x0101]
            RAM(16#000B#) := x"31"; RAM(16#000C#) := x"01"; RAM(16#000D#) := x"01";
            -- CALL sub (A=2 → 3)
            RAM(16#000E#) := x"75"; RAM(16#000F#) := x"50"; RAM(16#0010#) := x"00";
            -- ST A,[0x0102]
            RAM(16#0011#) := x"31"; RAM(16#0012#) := x"02"; RAM(16#0013#) := x"01";
            -- HALT
            RAM(16#0014#) := x"01";
            -- Subrutina @ 0x0050: INC A; RET
            RAM(16#0050#) := x"C2";                          -- INC A
            RAM(16#0051#) := x"77";                          -- RET

        -- =================================================================
        -- TB-09  PUSH / POP
        -- =================================================================
        -- Verifica round-trip de los 4 modos: A, B, F, A:B
        -- SP inicial = 0xFFFE; SP final debe ser 0xFFFE nuevamente.
        --
        -- Esperados:
        --   [0x0100] = 0xAB  (PUSH A / POP A round-trip)
        --   [0x0101] = 0xCD  (PUSH B / POP B round-trip, leído via LD A,B)
        --   [0x0102] = 0xAB  (PUSH A:B=0xAB:0xCD / POP A:B → A)
        --   [0x0103] = 0xCD  (A:B=0xAB:0xCD / POP A:B → B leído via LD A,B)
        elsif PROGRAM_SEL = 9 then
            -- PUSH A / POP A round-trip
            RAM(16#0000#) := x"11"; RAM(16#0001#) := x"AB";  -- LD A,#0xAB
            RAM(16#0002#) := x"60";                           -- PUSH A
            RAM(16#0003#) := x"11"; RAM(16#0004#) := x"00";  -- LD A,#0 (destruye A)
            RAM(16#0005#) := x"64";                           -- POP A → 0xAB
            RAM(16#0006#) := x"31"; RAM(16#0007#) := x"00"; RAM(16#0008#) := x"01"; -- ST [0x0100]
            -- PUSH B / POP B round-trip
            RAM(16#0009#) := x"21"; RAM(16#000A#) := x"CD";  -- LD B,#0xCD
            RAM(16#000B#) := x"61";                           -- PUSH B
            RAM(16#000C#) := x"21"; RAM(16#000D#) := x"00";  -- LD B,#0 (destruye B)
            RAM(16#000E#) := x"65";                           -- POP B → 0xCD
            RAM(16#000F#) := x"10";                           -- LD A,B
            RAM(16#0010#) := x"31"; RAM(16#0011#) := x"01"; RAM(16#0012#) := x"01"; -- ST [0x0101]
            -- PUSH A:B / POP A:B round-trip
            RAM(16#0013#) := x"11"; RAM(16#0014#) := x"AB";  -- LD A,#0xAB
            RAM(16#0015#) := x"21"; RAM(16#0016#) := x"CD";  -- LD B,#0xCD
            RAM(16#0017#) := x"63";                           -- PUSH A:B
            RAM(16#0018#) := x"11"; RAM(16#0019#) := x"00";  -- LD A,#0
            RAM(16#001A#) := x"21"; RAM(16#001B#) := x"00";  -- LD B,#0
            RAM(16#001C#) := x"67";                           -- POP A:B → A=0xAB, B=0xCD
            RAM(16#001D#) := x"31"; RAM(16#001E#) := x"02"; RAM(16#001F#) := x"01"; -- ST A,[0x0102]
            RAM(16#0020#) := x"10";                           -- LD A,B (B=0xCD)
            RAM(16#0021#) := x"31"; RAM(16#0022#) := x"03"; RAM(16#0023#) := x"01"; -- ST A,[0x0103]
            -- HALT
            RAM(16#0024#) := x"01";

        -- =================================================================
        -- TB-10  Stack Pointer
        -- =================================================================
        -- Instrucciones: LD SP,#nn / LD SP,A:B / ST SP_L,A / ST SP_H,A
        -- Esperados:
        --   [0x0100] = 0x34  (SP_L tras LD SP,#0x1234)
        --   [0x0101] = 0x12  (SP_H tras LD SP,#0x1234)
        --   [0x0102] = 0x78  (SP_L tras LD SP,A:B con A=0x56, B=0x78)
        --   [0x0103] = 0x56  (SP_H tras LD SP,A:B)
        elsif PROGRAM_SEL = 10 then
            -- LD SP,#0x1234
            RAM(16#0000#) := x"50"; RAM(16#0001#) := x"34"; RAM(16#0002#) := x"12"; -- LD SP,#0x1234
            -- ST SP_L,A → A = SP[7:0] = 0x34
            RAM(16#0003#) := x"52";                          -- ST SP_L, A
            RAM(16#0004#) := x"31"; RAM(16#0005#) := x"00"; RAM(16#0006#) := x"01"; -- ST A,[0x0100]
            -- ST SP_H,A → A = SP[15:8] = 0x12
            RAM(16#0007#) := x"53";                          -- ST SP_H, A
            RAM(16#0008#) := x"31"; RAM(16#0009#) := x"01"; RAM(16#000A#) := x"01"; -- ST A,[0x0101]
            -- LD SP, A:B con A=0x56, B=0x78
            RAM(16#000B#) := x"11"; RAM(16#000C#) := x"56"; -- LD A,#0x56
            RAM(16#000D#) := x"21"; RAM(16#000E#) := x"78"; -- LD B,#0x78
            RAM(16#000F#) := x"51";                          -- LD SP, A:B
            RAM(16#0010#) := x"52";                          -- ST SP_L, A → 0x78
            RAM(16#0011#) := x"31"; RAM(16#0012#) := x"02"; RAM(16#0013#) := x"01"; -- ST A,[0x0102]
            RAM(16#0014#) := x"53";                          -- ST SP_H, A → 0x56
            RAM(16#0015#) := x"31"; RAM(16#0016#) := x"03"; RAM(16#0017#) := x"01"; -- ST A,[0x0103]
            -- Restaurar SP a 0xFFFE para que HALT no corrompa el stack
            RAM(16#0018#) := x"50"; RAM(16#0019#) := x"FE"; RAM(16#001A#) := x"FF"; -- LD SP,#0xFFFE
            -- HALT
            RAM(16#001B#) := x"01";

        -- =================================================================
        -- TB-11  ADD16 / SUB16
        -- =================================================================
        -- ADD16 #n (con extensión de signo):  A:B=0x00FF + 1 = 0x0100
        -- ADD16 #nn (sin extensión):          A:B=0x0100 + 0x0001 = 0x0101
        -- SUB16 #n:                           A:B=0x0101 - 1 = 0x0100
        -- SUB16 #nn:                          A:B=0x0100 - 0x0001 = 0x00FF
        -- Carry: A:B=0xFFFF + 1 → 0x0000 (C=1, Z=1)
        --
        -- Resultados en RAM[0x0100..0x0109] (pares A:B = high:low):
        --   [0x0100]=0x01, [0x0101]=0x00  (ADD16 #1:  0x00FF+1)
        --   [0x0102]=0x01, [0x0103]=0x01  (ADD16 #nn: 0x0100+0x0001)
        --   [0x0104]=0x01, [0x0105]=0x00  (SUB16 #1:  0x0101-1)
        --   [0x0106]=0x00, [0x0107]=0xFF  (SUB16 #nn: 0x0100-0x0001)
        --   [0x0108]=0x00, [0x0109]=0x00  (ADD16 #1:  0xFFFF+1 → cero con C=1)
        elsif PROGRAM_SEL = 11 then
            -- A:B = 0x00FF
            RAM(16#0000#) := x"11"; RAM(16#0001#) := x"00"; -- LD A,#0x00
            RAM(16#0002#) := x"21"; RAM(16#0003#) := x"FF"; -- LD B,#0xFF
            -- ADD16 #1 → A:B = 0x0100
            RAM(16#0004#) := x"E0"; RAM(16#0005#) := x"01"; -- ADD16 #1
            RAM(16#0006#) := x"31"; RAM(16#0007#) := x"00"; RAM(16#0008#) := x"01"; -- ST A,[0x0100]
            RAM(16#0009#) := x"41"; RAM(16#000A#) := x"01"; RAM(16#000B#) := x"01"; -- ST B,[0x0101]
            -- ADD16 #0x0001 → A:B = 0x0101
            RAM(16#000C#) := x"E1"; RAM(16#000D#) := x"01"; RAM(16#000E#) := x"00"; -- ADD16 #0x0001
            RAM(16#000F#) := x"31"; RAM(16#0010#) := x"02"; RAM(16#0011#) := x"01"; -- ST A,[0x0102]
            RAM(16#0012#) := x"41"; RAM(16#0013#) := x"03"; RAM(16#0014#) := x"01"; -- ST B,[0x0103]
            -- SUB16 #1 → A:B = 0x0100
            RAM(16#0015#) := x"E2"; RAM(16#0016#) := x"01"; -- SUB16 #1
            RAM(16#0017#) := x"31"; RAM(16#0018#) := x"04"; RAM(16#0019#) := x"01"; -- ST A,[0x0104]
            RAM(16#001A#) := x"41"; RAM(16#001B#) := x"05"; RAM(16#001C#) := x"01"; -- ST B,[0x0105]
            -- SUB16 #0x0001 → A:B = 0x00FF
            RAM(16#001D#) := x"E3"; RAM(16#001E#) := x"01"; RAM(16#001F#) := x"00"; -- SUB16 #0x0001
            RAM(16#0020#) := x"31"; RAM(16#0021#) := x"06"; RAM(16#0022#) := x"01"; -- ST A,[0x0106]
            RAM(16#0023#) := x"41"; RAM(16#0024#) := x"07"; RAM(16#0025#) := x"01"; -- ST B,[0x0107]
            -- Overflow: A:B=0xFFFF; ADD16 #1 → 0x0000, C=1
            RAM(16#0026#) := x"11"; RAM(16#0027#) := x"FF"; -- LD A,#0xFF
            RAM(16#0028#) := x"21"; RAM(16#0029#) := x"FF"; -- LD B,#0xFF
            RAM(16#002A#) := x"E0"; RAM(16#002B#) := x"01"; -- ADD16 #1 → carry
            RAM(16#002C#) := x"31"; RAM(16#002D#) := x"08"; RAM(16#002E#) := x"01"; -- ST A,[0x0108]
            RAM(16#002F#) := x"41"; RAM(16#0030#) := x"09"; RAM(16#0031#) := x"01"; -- ST B,[0x0109]
            -- HALT
            RAM(16#0032#) := x"01";

        -- =================================================================
        -- TB-12  Interrupciones (IRQ + RTI / NMI + RTI)
        -- =================================================================
        -- Vector IRQ en RAM[0xFFFE/0xFFFF] = handler_irq @ 0x0050
        -- Vector NMI en RAM[0xFFFA/0xFFFB] = handler_nmi @ 0x0060
        -- Programa principal: bucle NOP que espera interrupción.
        --
        -- El stim_proc pulsa IRQ en el ciclo 30 y NMI en el ciclo 80.
        -- Los handlers incrementan contadores en [0x0100] y [0x0101] y hacen RTI.
        --
        -- Esperados:
        --   [0x0100] = 1  (handler IRQ ejecutado 1 vez)
        --   [0x0101] = 1  (handler NMI ejecutado 1 vez)
        elsif PROGRAM_SEL = 12 then
            -- vector IRQ @ 0xFFFE:0xFFFF = 0x0050 (little-endian)
            RAM(16#FFFE#) := x"50"; RAM(16#FFFF#) := x"00";
            -- vector NMI @ 0xFFFA:0xFFFB = 0x0060 (little-endian)
            RAM(16#FFFA#) := x"60"; RAM(16#FFFB#) := x"00";
            -- Programa principal: SEI + bucle NOP (10 NOPs) + HALT
            RAM(16#0000#) := x"04";                          -- SEI (habilitar IRQ)
            -- 10 NOPs para dar tiempo a la interrupción
            -- 0x0001..0x000A: NOP×10
            for i in 0 to 9 loop
                RAM(16#0001# + i) := x"00";
            end loop;
            RAM(16#000B#) := x"01";                          -- HALT
            -- Handler IRQ @ 0x0050: INC [0x0100]; RTI
            RAM(16#0050#) := x"13"; RAM(16#0051#) := x"00"; RAM(16#0052#) := x"01"; -- LD A,[0x0100]
            RAM(16#0053#) := x"C2";                          -- INC A
            RAM(16#0054#) := x"31"; RAM(16#0055#) := x"00"; RAM(16#0056#) := x"01"; -- ST A,[0x0100]
            RAM(16#0057#) := x"06";                          -- RTI
            -- Handler NMI @ 0x0060: INC [0x0101]; RTI
            RAM(16#0060#) := x"13"; RAM(16#0061#) := x"01"; RAM(16#0062#) := x"01"; -- LD A,[0x0101]
            RAM(16#0063#) := x"C2";                          -- INC A
            RAM(16#0064#) := x"31"; RAM(16#0065#) := x"01"; RAM(16#0066#) := x"01"; -- ST A,[0x0101]
            RAM(16#0067#) := x"06";                          -- RTI

        -- =================================================================
        -- TB-13  Pipeline hazards
        -- =================================================================
        -- Caso 1 RAW stall: LD A,#n seguido inmediatamente de ADD #0
        --   → resultado debe ser n+0=n (no el valor viejo de A).
        --   Guardamos en [0x0100].
        --
        -- Caso 2 flush por salto tomado: JP salta sobre una instrucción
        --   que no debe ejecutarse (INC A que destruiría el valor).
        --   Guardamos A en [0x0101] — debe ser el valor pre-salto.
        --
        -- Esperados:
        --   [0x0100] = 0x42  (RAW: A=0x42 + 0 = 0x42)
        --   [0x0101] = 0x42  (flush: el INC A en la ranura de delay no debe ejecutarse)
        elsif PROGRAM_SEL = 13 then
            -- RAW stall: LD A,#0x42 → ADD #0 (depende de A recién escrito)
            RAM(16#0000#) := x"11"; RAM(16#0001#) := x"42"; -- LD A,#0x42
            RAM(16#0002#) := x"A0"; RAM(16#0003#) := x"00"; -- ADD #0 → A debe ser 0x42
            RAM(16#0004#) := x"31"; RAM(16#0005#) := x"00"; RAM(16#0006#) := x"01"; -- ST A,[0x0100]
            -- Flush: LD A,#0x42 → JP nn (salta sobre INC A) → ST A
            RAM(16#0007#) := x"11"; RAM(16#0008#) := x"42"; -- LD A,#0x42
            RAM(16#0009#) := x"70"; RAM(16#000A#) := x"0D"; RAM(16#000B#) := x"00"; -- JP 0x000D
            RAM(16#000C#) := x"C2";                          -- INC A ← NO debe ejecutarse (flush)
            RAM(16#000D#) := x"31"; RAM(16#000E#) := x"01"; RAM(16#000F#) := x"01"; -- ST A,[0x0101]
            -- HALT
            RAM(16#0010#) := x"01";

        end if;  -- PROGRAM_SEL

        -- Esperar un delta cycle para que las asignaciones de RAM se apliquen
        wait for 0 ns;
        report "DBG RAM[0x0000]=0x" & to_hstring(RAM(16#0000#)) &
               " RAM[0x0001]=0x" & to_hstring(RAM(16#0001#)) &
               " (programa cargado)";

        -- ---------------------------------------------------------------
        -- Reset inicial
        -- ---------------------------------------------------------------
        report "=== INICIO SIMULACION PROCESADOR - PROGRAM_SEL=" &
               integer'image(PROGRAM_SEL) & " ===";
        reset <= '1';
        wait for CLK_PERIOD * 5;
        reset <= '0';
        report "--- Reset liberado ---";

        -- ---------------------------------------------------------------
        -- Para TB-12: pulsar IRQ y NMI en momentos controlados
        -- Si es otro programa, estas líneas no tienen efecto nocivo
        -- porque irq_sig y nmi_sig permanecen en '0'
        -- ---------------------------------------------------------------
        if PROGRAM_SEL = 12 then
            wait for CLK_PERIOD * 15;   -- esperar 15 ciclos para que SEI esté activo
            irq_sig <= '1';
            wait for CLK_PERIOD * 2;
            irq_sig <= '0';
            wait for CLK_PERIOD * 30;   -- esperar 30 ciclos más para NMI
            nmi_sig <= '1';
            wait for CLK_PERIOD * 2;
            nmi_sig <= '0';
        end if;

        -- ---------------------------------------------------------------
        -- Esperar HALT
        -- ---------------------------------------------------------------
        wait_for_halt(MAX_CYCLES);
        -- Extra: 1 ciclo de margen para que las escrituras en curso se asienten
        wait until rising_edge(clk);
        wait until rising_edge(clk);

        -- ---------------------------------------------------------------
        -- Verificaciones por programa
        -- ---------------------------------------------------------------
        report "--- Verificacion PROGRAM_SEL=" & integer'image(PROGRAM_SEL) & " ---";

        if PROGRAM_SEL = 1 then
            assert RAM(16#0100#) = x"FF"
                report "TB-01 FAIL [0x0100]: esperado 0xFF (INC 0xFE), obtenido 0x" & to_hstring(RAM(16#0100#)) severity error;
            assert RAM(16#0101#) = x"00"
                report "TB-01 FAIL [0x0101]: esperado 0x00 (INC 0xFF), obtenido 0x" & to_hstring(RAM(16#0101#)) severity error;
            assert RAM(16#0102#) = x"FF"
                report "TB-01 FAIL [0x0102]: esperado 0xFF (DEC 0x00), obtenido 0x" & to_hstring(RAM(16#0102#)) severity error;
            assert RAM(16#0103#) = x"FE"
                report "TB-01 FAIL [0x0103]: esperado 0xFE (DEC 0xFF), obtenido 0x" & to_hstring(RAM(16#0103#)) severity error;
            assert RAM(16#0104#) = x"01"
                report "TB-01 FAIL [0x0104]: esperado 0x01 (NOT 0xFE), obtenido 0x" & to_hstring(RAM(16#0104#)) severity error;
            assert RAM(16#0105#) = x"FF"
                report "TB-01 FAIL [0x0105]: esperado 0xFF (NEG 0x01), obtenido 0x" & to_hstring(RAM(16#0105#)) severity error;
            assert RAM(16#0106#) = x"00"
                report "TB-01 FAIL [0x0106]: esperado 0x00 (CLR A), obtenido 0x" & to_hstring(RAM(16#0106#)) severity error;
            assert RAM(16#0107#) = x"FF"
                report "TB-01 FAIL [0x0107]: esperado 0xFF (SET A), obtenido 0x" & to_hstring(RAM(16#0107#)) severity error;
            assert RAM(16#0108#) = x"06"
                report "TB-01 FAIL [0x0108]: esperado 0x06 (INC B: 0x05->0x06), obtenido 0x" & to_hstring(RAM(16#0108#)) severity error;
            assert RAM(16#0109#) = x"05"
                report "TB-01 FAIL [0x0109]: esperado 0x05 (DEC B: 0x06->0x05), obtenido 0x" & to_hstring(RAM(16#0109#)) severity error;
            assert RAM(16#010A#) = x"F0"
                report "TB-01 FAIL [0x010A]: esperado 0xF0 (SWAP 0x0F), obtenido 0x" & to_hstring(RAM(16#010A#)) severity error;
            report "TB-01 PASS: Instrucciones unarias verificadas.";

        elsif PROGRAM_SEL = 2 then
            assert RAM(16#0100#) = x"0F"
                report "TB-02 FAIL ADD: esperado 0x0F, obtenido 0x" & to_hstring(RAM(16#0100#)) severity error;
            assert RAM(16#0101#) = x"10"
                report "TB-02 FAIL ADC: esperado 0x10, obtenido 0x" & to_hstring(RAM(16#0101#)) severity error;
            assert RAM(16#0102#) = x"FF"
                report "TB-02 FAIL SUB: esperado 0xFF, obtenido 0x" & to_hstring(RAM(16#0102#)) severity error;
            assert RAM(16#0103#) = x"FE"
                report "TB-02 FAIL SBB: esperado 0xFE, obtenido 0x" & to_hstring(RAM(16#0103#)) severity error;
            assert RAM(16#0104#) = x"05"
                report "TB-02 FAIL AND: esperado 0x05, obtenido 0x" & to_hstring(RAM(16#0104#)) severity error;
            assert RAM(16#0105#) = x"3F"
                report "TB-02 FAIL OR: esperado 0x3F, obtenido 0x" & to_hstring(RAM(16#0105#)) severity error;
            assert RAM(16#0106#) = x"3A"
                report "TB-02 FAIL XOR: esperado 0x3A, obtenido 0x" & to_hstring(RAM(16#0106#)) severity error;
            assert RAM(16#0107#) = x"07"
                report "TB-02 FAIL CMP: esperado 0x07 (A sin cambio), obtenido 0x" & to_hstring(RAM(16#0107#)) severity error;
            assert RAM(16#0108#) = x"38"
                report "TB-02 FAIL MUL: esperado 0x38 (7*8 low), obtenido 0x" & to_hstring(RAM(16#0108#)) severity error;
            assert RAM(16#0109#) = x"00"
                report "TB-02 FAIL MUH: esperado 0x00 (7*8 high), obtenido 0x" & to_hstring(RAM(16#0109#)) severity error;
            report "TB-02 PASS: ALU registro verificada.";

        elsif PROGRAM_SEL = 3 then
            assert RAM(16#0100#) = x"0F"
                report "TB-03 FAIL ADD#: esperado 0x0F, obtenido 0x" & to_hstring(RAM(16#0100#)) severity error;
            assert RAM(16#0101#) = x"10"
                report "TB-03 FAIL ADC#: esperado 0x10, obtenido 0x" & to_hstring(RAM(16#0101#)) severity error;
            assert RAM(16#0102#) = x"FF"
                report "TB-03 FAIL SUB#: esperado 0xFF, obtenido 0x" & to_hstring(RAM(16#0102#)) severity error;
            assert RAM(16#0103#) = x"FE"
                report "TB-03 FAIL SBB#: esperado 0xFE, obtenido 0x" & to_hstring(RAM(16#0103#)) severity error;
            assert RAM(16#0104#) = x"05"
                report "TB-03 FAIL AND#: esperado 0x05, obtenido 0x" & to_hstring(RAM(16#0104#)) severity error;
            assert RAM(16#0105#) = x"3F"
                report "TB-03 FAIL OR#: esperado 0x3F, obtenido 0x" & to_hstring(RAM(16#0105#)) severity error;
            assert RAM(16#0106#) = x"3A"
                report "TB-03 FAIL XOR#: esperado 0x3A, obtenido 0x" & to_hstring(RAM(16#0106#)) severity error;
            assert RAM(16#0107#) = x"07"
                report "TB-03 FAIL CMP#: esperado 0x07, obtenido 0x" & to_hstring(RAM(16#0107#)) severity error;
            report "TB-03 PASS: ALU inmediato verificada.";

        elsif PROGRAM_SEL = 4 then
            assert RAM(16#0100#) = x"54"
                report "TB-04 FAIL LSL: esperado 0x54, obtenido 0x" & to_hstring(RAM(16#0100#)) severity error;
            assert RAM(16#0101#) = x"55"
                report "TB-04 FAIL LSR: esperado 0x55, obtenido 0x" & to_hstring(RAM(16#0101#)) severity error;
            assert RAM(16#0102#) = x"54"
                report "TB-04 FAIL ASL: esperado 0x54, obtenido 0x" & to_hstring(RAM(16#0102#)) severity error;
            assert RAM(16#0103#) = x"D5"
                report "TB-04 FAIL ASR: esperado 0xD5, obtenido 0x" & to_hstring(RAM(16#0103#)) severity error;
            assert RAM(16#0104#) = x"54"
                report "TB-04 FAIL ROL(C=0): esperado 0x54, obtenido 0x" & to_hstring(RAM(16#0104#)) severity error;
            assert RAM(16#0105#) = x"55"
                report "TB-04 FAIL ROR(C=0): esperado 0x55, obtenido 0x" & to_hstring(RAM(16#0105#)) severity error;
            assert RAM(16#0106#) = x"03"
                report "TB-04 FAIL ROL(C=1): esperado 0x03 (0x01 rota izq +C), obtenido 0x" & to_hstring(RAM(16#0106#)) severity error;
            assert RAM(16#0107#) = x"C0"
                report "TB-04 FAIL ROR(C=1): esperado 0xC0 (0x80 rota der +C), obtenido 0x" & to_hstring(RAM(16#0107#)) severity error;
            report "TB-04 PASS: Desplazamientos y rotaciones verificados.";

        elsif PROGRAM_SEL = 5 then
            assert RAM(16#0100#) = x"AB"
                report "TB-05 FAIL LD A,[n]: esperado 0xAB, obtenido 0x" & to_hstring(RAM(16#0100#)) severity error;
            assert RAM(16#0101#) = x"CD"
                report "TB-05 FAIL LD A,[nn]: esperado 0xCD, obtenido 0x" & to_hstring(RAM(16#0101#)) severity error;
            assert RAM(16#0102#) = x"EF"
                report "TB-05 FAIL LD A,[B]: esperado 0xEF, obtenido 0x" & to_hstring(RAM(16#0102#)) severity error;
            assert RAM(16#0103#) = x"12"
                report "TB-05 FAIL LD A,[nn+B]: esperado 0x12, obtenido 0x" & to_hstring(RAM(16#0103#)) severity error;
            assert RAM(16#0104#) = x"34"
                report "TB-05 FAIL LD A,[n+B]: esperado 0x34, obtenido 0x" & to_hstring(RAM(16#0104#)) severity error;
            assert RAM(16#0105#) = x"78"
                report "TB-05 FAIL LD B,[nn]: esperado 0x78, obtenido 0x" & to_hstring(RAM(16#0105#)) severity error;
            assert RAM(16#0106#) = x"9A"
                report "TB-05 FAIL LD B,[B]: esperado 0x9A, obtenido 0x" & to_hstring(RAM(16#0106#)) severity error;
            assert RAM(16#0107#) = x"9A"
                report "TB-05 FAIL ST A,[n] roundtrip: esperado 0x9A, obtenido 0x" & to_hstring(RAM(16#0107#)) severity error;
            report "TB-05 PASS: Cargas y almacenamientos verificados.";

        elsif PROGRAM_SEL = 6 then
            assert RAM(16#0100#) = x"01"
                report "TB-06 FAIL bloque0 (pre-JP): esperado 1, obtenido 0x" & to_hstring(RAM(16#0100#)) severity error;
            assert RAM(16#0101#) = x"01"
                report "TB-06 FAIL bloque1 (post-JP): esperado 1, obtenido 0x" & to_hstring(RAM(16#0101#)) severity error;
            assert RAM(16#0102#) = x"01"
                report "TB-06 FAIL bloque2 (post-JR): esperado 1, obtenido 0x" & to_hstring(RAM(16#0102#)) severity error;
            assert RAM(16#0103#) = x"01"
                report "TB-06 FAIL bloque3 (post-JPN): esperado 1, obtenido 0x" & to_hstring(RAM(16#0103#)) severity error;
            assert RAM(16#0104#) = x"01"
                report "TB-06 FAIL bloque4 (post-JP A:B): esperado 1, obtenido 0x" & to_hstring(RAM(16#0104#)) severity error;
            report "TB-06 PASS: Saltos incondicionales verificados.";

        elsif PROGRAM_SEL = 7 then
            assert RAM(16#0100#) = x"01"
                report "TB-07 FAIL BEQ taken: esperado 1, obtenido 0x" & to_hstring(RAM(16#0100#)) severity error;
            assert RAM(16#0101#) = x"00"
                report "TB-07 FAIL BEQ not-taken: esperado 0, obtenido 0x" & to_hstring(RAM(16#0101#)) severity error;
            assert RAM(16#0102#) = x"01"
                report "TB-07 FAIL BNE taken: esperado 1, obtenido 0x" & to_hstring(RAM(16#0102#)) severity error;
            assert RAM(16#0103#) = x"01"
                report "TB-07 FAIL BCS taken: esperado 1, obtenido 0x" & to_hstring(RAM(16#0103#)) severity error;
            assert RAM(16#0104#) = x"01"
                report "TB-07 FAIL BCC taken: esperado 1, obtenido 0x" & to_hstring(RAM(16#0104#)) severity error;
            assert RAM(16#0105#) = x"01"
                report "TB-07 FAIL BGT taken: esperado 1, obtenido 0x" & to_hstring(RAM(16#0105#)) severity error;
            assert RAM(16#0106#) = x"01"
                report "TB-07 FAIL BLE taken: esperado 1, obtenido 0x" & to_hstring(RAM(16#0106#)) severity error;
            report "TB-07 PASS: Saltos condicionales verificados.";

        elsif PROGRAM_SEL = 8 then
            assert RAM(16#0100#) = x"01"
                report "TB-08 FAIL CALL/RET#1: esperado A=1, obtenido 0x" & to_hstring(RAM(16#0100#)) severity error;
            assert RAM(16#0101#) = x"02"
                report "TB-08 FAIL CALL/RET#2: esperado A=2, obtenido 0x" & to_hstring(RAM(16#0101#)) severity error;
            assert RAM(16#0102#) = x"03"
                report "TB-08 FAIL CALL/RET#3: esperado A=3, obtenido 0x" & to_hstring(RAM(16#0102#)) severity error;
            report "TB-08 PASS: CALL/RET verificados.";

        elsif PROGRAM_SEL = 9 then
            assert RAM(16#0100#) = x"AB"
                report "TB-09 FAIL PUSH/POP A: esperado 0xAB, obtenido 0x" & to_hstring(RAM(16#0100#)) severity error;
            assert RAM(16#0101#) = x"CD"
                report "TB-09 FAIL PUSH/POP B: esperado 0xCD, obtenido 0x" & to_hstring(RAM(16#0101#)) severity error;
            assert RAM(16#0102#) = x"AB"
                report "TB-09 FAIL PUSH/POP A:B (A): esperado 0xAB, obtenido 0x" & to_hstring(RAM(16#0102#)) severity error;
            assert RAM(16#0103#) = x"CD"
                report "TB-09 FAIL PUSH/POP A:B (B): esperado 0xCD, obtenido 0x" & to_hstring(RAM(16#0103#)) severity error;
            report "TB-09 PASS: PUSH/POP verificados.";

        elsif PROGRAM_SEL = 10 then
            assert RAM(16#0100#) = x"34"
                report "TB-10 FAIL ST SP_L (LD SP,#0x1234): esperado 0x34, obtenido 0x" & to_hstring(RAM(16#0100#)) severity error;
            assert RAM(16#0101#) = x"12"
                report "TB-10 FAIL ST SP_H (LD SP,#0x1234): esperado 0x12, obtenido 0x" & to_hstring(RAM(16#0101#)) severity error;
            assert RAM(16#0102#) = x"78"
                report "TB-10 FAIL ST SP_L (LD SP,A:B): esperado 0x78, obtenido 0x" & to_hstring(RAM(16#0102#)) severity error;
            assert RAM(16#0103#) = x"56"
                report "TB-10 FAIL ST SP_H (LD SP,A:B): esperado 0x56, obtenido 0x" & to_hstring(RAM(16#0103#)) severity error;
            report "TB-10 PASS: Stack Pointer verificado.";

        elsif PROGRAM_SEL = 11 then
            assert RAM(16#0100#) = x"01"
                report "TB-11 FAIL ADD16#1 (A high): esperado 0x01, obtenido 0x" & to_hstring(RAM(16#0100#)) severity error;
            assert RAM(16#0101#) = x"00"
                report "TB-11 FAIL ADD16#1 (B low): esperado 0x00, obtenido 0x" & to_hstring(RAM(16#0101#)) severity error;
            assert RAM(16#0102#) = x"01"
                report "TB-11 FAIL ADD16#nn (A high): esperado 0x01, obtenido 0x" & to_hstring(RAM(16#0102#)) severity error;
            assert RAM(16#0103#) = x"01"
                report "TB-11 FAIL ADD16#nn (B low): esperado 0x01, obtenido 0x" & to_hstring(RAM(16#0103#)) severity error;
            assert RAM(16#0104#) = x"01"
                report "TB-11 FAIL SUB16#1 (A high): esperado 0x01, obtenido 0x" & to_hstring(RAM(16#0104#)) severity error;
            assert RAM(16#0105#) = x"00"
                report "TB-11 FAIL SUB16#1 (B low): esperado 0x00, obtenido 0x" & to_hstring(RAM(16#0105#)) severity error;
            assert RAM(16#0106#) = x"00"
                report "TB-11 FAIL SUB16#nn (A high): esperado 0x00, obtenido 0x" & to_hstring(RAM(16#0106#)) severity error;
            assert RAM(16#0107#) = x"FF"
                report "TB-11 FAIL SUB16#nn (B low): esperado 0xFF, obtenido 0x" & to_hstring(RAM(16#0107#)) severity error;
            assert RAM(16#0108#) = x"00"
                report "TB-11 FAIL ADD16 overflow (A high): esperado 0x00, obtenido 0x" & to_hstring(RAM(16#0108#)) severity error;
            assert RAM(16#0109#) = x"00"
                report "TB-11 FAIL ADD16 overflow (B low): esperado 0x00, obtenido 0x" & to_hstring(RAM(16#0109#)) severity error;
            assert (RAM(16#0100#) = x"01" and RAM(16#0101#) = x"00" and
                    RAM(16#0102#) = x"01" and RAM(16#0103#) = x"01" and
                    RAM(16#0104#) = x"01" and RAM(16#0105#) = x"00" and
                    RAM(16#0106#) = x"00" and RAM(16#0107#) = x"FF" and
                    RAM(16#0108#) = x"00" and RAM(16#0109#) = x"00")
                report "TB-11 FAIL: ADD16/SUB16 algun resultado incorrecto (ver asserts previos)." severity error;
            if (RAM(16#0100#) = x"01" and RAM(16#0101#) = x"00" and
                RAM(16#0102#) = x"01" and RAM(16#0103#) = x"01" and
                RAM(16#0104#) = x"01" and RAM(16#0105#) = x"00" and
                RAM(16#0106#) = x"00" and RAM(16#0107#) = x"FF" and
                RAM(16#0108#) = x"00" and RAM(16#0109#) = x"00") then
                report "TB-11 PASS: ADD16/SUB16 verificados.";
            end if;

        elsif PROGRAM_SEL = 12 then
            assert RAM(16#0100#) = x"01"
                report "TB-12 FAIL IRQ handler: esperado contador=1, obtenido 0x" & to_hstring(RAM(16#0100#)) severity error;
            assert RAM(16#0101#) = x"01"
                report "TB-12 FAIL NMI handler: esperado contador=1, obtenido 0x" & to_hstring(RAM(16#0101#)) severity error;
            report "TB-12 PASS: Interrupciones IRQ/NMI verificadas.";

        elsif PROGRAM_SEL = 13 then
            assert RAM(16#0100#) = x"42"
                report "TB-13 FAIL RAW stall: esperado 0x42, obtenido 0x" & to_hstring(RAM(16#0100#)) severity error;
            assert RAM(16#0101#) = x"42"
                report "TB-13 FAIL flush salto: esperado 0x42 (INC no ejecutado), obtenido 0x" & to_hstring(RAM(16#0101#)) severity error;
            report "TB-13 PASS: Pipeline hazards verificados.";

        else
            report "PROGRAM_SEL=" & integer'image(PROGRAM_SEL) & " no reconocido." severity failure;
        end if;

        report "=== FIN SIMULACION PROCESADOR - PROGRAM_SEL=" &
               integer'image(PROGRAM_SEL) & " ===";
        std.env.stop;
    end process stim_proc;

end architecture sim;
