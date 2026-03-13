--------------------------------------------------------------------------------
-- File: ControlUnit.vhdl
-- Description:
--   4-Stage Pipelined Control Unit for the 8-bit processor.
--   Architecture name: pipeline  (replaces the original "unique" FSM)
--
--   Pipeline stages
--   ---------------
--   IF  - FETCH: Assert ABUS=PC, Mem_RE=1.  At the rising edge the memory
--         data bus (InstrIn) is captured into r_IF_ID and PC is incremented
--         (PC_Op=INC is part of the combinatorial CtrlBus output when fetch
--         is active).
--
--   ID  - DECODE: Examine r_IF_ID.opcode.
--         1-byte instructions  -> build complete ctrl word in one cycle,
--           write to r_ID_EX with is_single='1'.
--         2-byte instructions  -> dss: DSS_OPCODE -> DSS_OP1 (fetch op1 first).
--         3-byte instructions  -> dss: DSS_OPCODE -> DSS_OP1 -> DSS_OP2.
--
--   EX  - EXECUTE:
--         Single-cycle (is_single='1'): r_ID_EX.ctrl drives CtrlBus for one clock.
--         Multi-cycle  (is_multi='1'):  r_exec_IR/op1/op2 are latched and the
--           ESS sub-state machine drives CtrlBus for all remaining cycles.
--
--   WB  - WRITE-BACK: Implicit at the rising edge ending the EX cycle.
--
--   Key pipeline overlap rule
--   -------------------------
--   While the EX stage runs a single-cycle ALU instruction (no memory bus
--   needed) and there is no RAW hazard, FETCH of the next instruction can
--   proceed simultaneously.
--
--   RAW Hazard detection
--   --------------------
--   If the instruction in ID/EX writes a register that is read by the
--   instruction in IF/ID, DECODE is stalled for one cycle.
--
--   Branch/Jump flush
--   -----------------
--   When a taken branch is detected, both r_IF_ID and r_ID_EX are cleared.
--
-- Dependencies: CONSTANTS_pkg, ALU_pkg, DataPath_pkg, AddressPath_pkg,
--               ControlUnit_pkg, Pipeline_pkg
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.CONSTANTS_pkg.ALL;
use work.ALU_pkg.ALL;
use work.DataPath_pkg.ALL;
use work.AddressPath_pkg.ALL;
use work.ControlUnit_pkg.ALL;
use work.Pipeline_pkg.ALL;

entity ControlUnit is
    Port (
        clk      : in  std_logic;
        reset    : in  std_logic;
        FlagsIn  : in  status_vector;
        InstrIn  : in  data_vector;
        Mem_Ready: in  std_logic;
        IRQ      : in  std_logic;
        NMI      : in  std_logic;
        CtrlBus  : out control_bus_t
    );
end entity ControlUnit;

architecture pipeline of ControlUnit is

    -- Pipeline registers
    signal r_IF_ID : IF_ID_reg_t := NOP_IF_ID;
    signal r_ID_EX : ID_EX_reg_t := NOP_ID_EX;

    -- Sub-state machines
    signal dss : dss_t := DSS_OPCODE;
    signal ess : ess_t := ESS_IDLE;

    -- Latched operands for ESS dispatch
    signal r_exec_IR  : data_vector := x"00";
    signal r_exec_op1 : data_vector := x"00";
    signal r_exec_op2 : data_vector := x"00";

    -- Interrupt / status
    signal I_Flag       : std_logic := '0';
    signal handling_nmi : std_logic := '0';

    -- =========================================================================
    -- Helper functions
    -- =========================================================================

    function branch_taken_f(opcode : data_vector; flags : status_vector) return boolean is
    begin
        case opcode is
            when x"80"  => return flags(idx_fZ) = '1';                            -- BEQ: salta si Zero activo
            when x"81"  => return flags(idx_fZ) = '0';                            -- BNE: salta si Zero inactivo
            when x"82"  => return flags(idx_fC) = '1';                            -- BCS: salta si Carry activo
            when x"83"  => return flags(idx_fC) = '0';                            -- BCC: salta si Carry inactivo
            when x"84"  => return flags(idx_fV) = '1';                            -- BVS: salta si oVerflow activo
            when x"85"  => return flags(idx_fV) = '0';                            -- BVC: salta si oVerflow inactivo
            when x"86"  => return flags(idx_fG) = '1';                            -- BGT: salta si Mayor (con signo)
            when x"87"  => return flags(idx_fG) = '0';                            -- BLT: salta si Menor (con signo)
            when x"88"  => return (flags(idx_fG) = '1') or (flags(idx_fE) = '1'); -- BGE: salta si Mayor o Igual
            when x"89"  => return (flags(idx_fG) = '0') and (flags(idx_fE) = '0');-- BLE: salta si Menor estricto (no igual)
            when x"8A"  => return flags(idx_fH) = '1';                            -- BH:  salta si Half-carry activo (BCD)
            when x"8B"  => return flags(idx_fE) = '1';                            -- BEQ2: salta si Equal (resultado de CMP)
            when x"71"  => return true;                                            -- JR: salto relativo incondicional
            when others => return false;
        end case;
    end function;

    function reads_a_f(op : data_vector) return std_logic is
    begin
        case op is
            when x"90"|x"91"|x"92"|x"93"|x"94"|x"95"|x"96"|x"97" => return '1'; -- ALU reg A op B  (ADD/ADC/SUB/SBB/AND/OR/XOR/CMP)
            when x"A0"|x"A1"|x"A2"|x"A3"|x"A4"|x"A5"|x"A6"|x"A7" => return '1'; -- ALU imm A op #n (mismas ops con operando inmediato)
            when x"C0"|x"C1"|x"C2"|x"C3"|x"C6"|x"C7"             => return '1'; -- Unarias sobre A: NOT/NEG/INC/DEC/CLR/SET
            when x"C8"|x"C9"|x"CA"|x"CB"|x"CC"|x"CD"|x"CE"       => return '1'; -- Desplazamientos/rotaciones sobre A
            when x"30"|x"31"|x"32"|x"33"|x"34"                    => return '1'; -- ST A,[addr]: A es el dato a escribir
            when x"60"|x"63"                                       => return '1'; -- PUSH A / PUSH A:B
            when x"20"                                             => return '1'; -- LD B,A
            when x"D2"|x"D3"                                       => return '1'; -- OUT #n,A / OUT [B],A: A es el dato de salida
            when x"E0"|x"E1"|x"E2"|x"E3"                          => return '1'; -- ADD16/SUB16: A es el byte alto del par A:B
            when x"51"|x"52"|x"53"                                 => return '1'; -- LD SP,A:B / ST SP_L,A / ST SP_H,A
            when x"02"|x"03"                                       => return '1'; -- SEC/CLC: usan la ALU a través de A para modificar Carry
            when others => return '0';
        end case;
    end function;

    function reads_b_f(op : data_vector) return std_logic is
    begin
        case op is
            when x"90"|x"91"|x"92"|x"93"|x"94"|x"95"|x"96"|x"97" => return '1'; -- ALU reg: B es el segundo operando
            when x"C4"|x"C5"                                       => return '1'; -- INCB / DECB: opera sobre B
            when x"10"                                             => return '1'; -- LD A,B
            when x"14"|x"24"                                       => return '1'; -- LD A,[B] / LD B,[B]: B es la dirección
            when x"15"|x"16"                                       => return '1'; -- LD A,[nn+B] / LD A,[n+B]: B es el índice
            when x"25"                                             => return '1'; -- LD B,[nn+B]: B es el índice
            when x"32"|x"33"|x"34"                                => return '1'; -- ST A,[B] / ST A,[nn+B] / ST A,[n+B]
            when x"42"                                             => return '1'; -- ST B,[nn+B]: B es índice y dato fuente
            when x"61"|x"63"                                       => return '1'; -- PUSH B / PUSH A:B
            when x"D1"|x"D3"                                       => return '1'; -- IN A,[B] / OUT [B],A: B es la dirección de puerto
            when x"E0"|x"E1"|x"E2"|x"E3"                          => return '1'; -- ADD16/SUB16: B es el byte bajo del par A:B
            when x"51"                                             => return '1'; -- LD SP,A:B
            when others => return '0';
        end case;
    end function;

    function writes_a_f(op : data_vector) return std_logic is
    begin
        case op is
            when x"10"|x"11"|x"12"|x"13"|x"14"|x"15"|x"16"       => return '1'; -- LD A,*: todas las formas de carga en A
            when x"90"|x"91"|x"92"|x"93"|x"94"|x"95"|x"96"       => return '1'; -- ALU reg (excluye CMP=0x97 que no escribe A)
            when x"A0"|x"A1"|x"A2"|x"A3"|x"A4"|x"A5"|x"A6"       => return '1'; -- ALU imm (excluye CMP=0xA7)
            when x"C0"|x"C1"|x"C2"|x"C3"|x"C6"|x"C7"             => return '1'; -- Unarias sobre A
            when x"C8"|x"C9"|x"CA"|x"CB"|x"CC"|x"CD"|x"CE"       => return '1'; -- Desplazamientos/rotaciones sobre A
            when x"64"|x"67"                                       => return '1'; -- POP A / POP A:B
            when x"D0"|x"D1"                                       => return '1'; -- IN A,#n / IN A,[B]
            when x"E0"|x"E1"|x"E2"|x"E3"                          => return '1'; -- ADD16/SUB16: byte alto del resultado va a A
            when x"52"|x"53"                                       => return '1'; -- ST SP_L,A / ST SP_H,A: el byte del SP se lee en A
            when others => return '0';
        end case;
    end function;

    function writes_b_f(op : data_vector) return std_logic is
    begin
        case op is
            when x"20"|x"21"|x"22"|x"23"|x"24"|x"25"             => return '1'; -- LD B,*: todas las formas de carga en B
            when x"C4"|x"C5"                                       => return '1'; -- INCB / DECB
            when x"65"|x"67"                                       => return '1'; -- POP B / POP A:B
            when x"E0"|x"E1"|x"E2"|x"E3"                          => return '1'; -- ADD16/SUB16: byte bajo del resultado va a B
            when others => return '0';
        end case;
    end function;

    -- Build a complete ctrl word for single-cycle ALU-register ops (0x90..0x97)
    function build_alu_reg(opcode : data_vector) return control_bus_t is
        variable c  : control_bus_t := INIT_CTRL_BUS;
    begin
        c.Reg_Sel     := std_logic_vector(to_unsigned(1, REG_SEL_WIDTH));
        c.ALU_Bin_Sel := '0';
        c.Bus_Op      := ACC_ALU_elected;
        c.Write_F     := '1';
        c.Write_A     := '1';
        case opcode is
            when x"90" => c.ALU_Op := OP_ADD; c.Flag_Mask := x"FF";
            when x"91" => c.ALU_Op := OP_ADC; c.Flag_Mask := x"FC";
            when x"92" => c.ALU_Op := OP_SUB; c.Flag_Mask := x"FF";
            when x"93" => c.ALU_Op := OP_SBB; c.Flag_Mask := x"FC";
            when x"94" => c.ALU_Op := OP_AND; c.Flag_Mask := x"1C";
            when x"95" => c.ALU_Op := OP_IOR; c.Flag_Mask := x"1C";
            when x"96" => c.ALU_Op := OP_XOR; c.Flag_Mask := x"1C";
            when x"97" => c.ALU_Op := OP_CMP; c.Flag_Mask := x"FF"; c.Write_A := '0';
            when x"98" => c.ALU_Op := OP_MUL; c.Flag_Mask := x"FF";
            when x"99" => c.ALU_Op := OP_MUH; c.Flag_Mask := x"FF";
            when others => null;
        end case;
        return c;
    end function;

    -- Build a complete ctrl word for ALU-immediate ops (0xA0..0xA7)
    -- The immediate operand is in MDR (MDR_WE was asserted during operand fetch)
    function build_alu_imm(opcode : data_vector) return control_bus_t is
        variable c : control_bus_t := INIT_CTRL_BUS;
    begin
        c.ALU_Bin_Sel := '1'; -- B input = MDR
        c.Bus_Op      := ACC_ALU_elected;
        c.Write_F     := '1';
        c.Write_A     := '1';
        case opcode is
            when x"A0" => c.ALU_Op := OP_ADD; c.Flag_Mask := x"FF";
            when x"A1" => c.ALU_Op := OP_ADC; c.Flag_Mask := x"FC";
            when x"A2" => c.ALU_Op := OP_SUB; c.Flag_Mask := x"FF";
            when x"A3" => c.ALU_Op := OP_SBB; c.Flag_Mask := x"FC";
            when x"A4" => c.ALU_Op := OP_AND; c.Flag_Mask := x"1C";
            when x"A5" => c.ALU_Op := OP_IOR; c.Flag_Mask := x"1C";
            when x"A6" => c.ALU_Op := OP_XOR; c.Flag_Mask := x"1C";
            when x"A7" => c.ALU_Op := OP_CMP; c.Flag_Mask := x"FF"; c.Write_A := '0';
            when others => null;
        end case;
        return c;
    end function;

    -- Build ctrl word for ALU unary ops (0xC0..0xCE)
    function build_alu_unary(opcode : data_vector) return control_bus_t is
        variable c : control_bus_t := INIT_CTRL_BUS;
    begin
        c.Bus_Op  := ACC_ALU_elected;
        c.Write_F := '1';
        if opcode = x"C4" or opcode = x"C5" then
            c.Write_B := '1';
            c.Reg_Sel := std_logic_vector(to_unsigned(1, REG_SEL_WIDTH));
        else
            c.Write_A := '1';
        end if;
        case opcode is
            when x"C0" => c.ALU_Op := OP_NOT; c.Flag_Mask := x"10";
            when x"C1" => c.ALU_Op := OP_NEG; c.Flag_Mask := x"F0";
            when x"C2" => c.ALU_Op := OP_INC; c.Flag_Mask := x"F0";
            when x"C3" => c.ALU_Op := OP_DEC; c.Flag_Mask := x"F0";
            when x"C4" => c.ALU_Op := OP_INB; c.Flag_Mask := x"F0";
            when x"C5" => c.ALU_Op := OP_DEB; c.Flag_Mask := x"F0";
            when x"C6" => c.ALU_Op := OP_CLR; c.Flag_Mask := x"10";
            when x"C7" => c.ALU_Op := OP_SET; c.Flag_Mask := x"10";
            when x"C8" => c.ALU_Op := OP_LSL; c.Flag_Mask := x"11";
            when x"C9" => c.ALU_Op := OP_LSR; c.Flag_Mask := x"12";
            when x"CA" => c.ALU_Op := OP_ASL; c.Flag_Mask := x"31";
            when x"CB" => c.ALU_Op := OP_ASR; c.Flag_Mask := x"12";
            when x"CC" => c.ALU_Op := OP_ROL; c.Flag_Mask := x"90"; -- C(bit7)+Z(bit4)
            when x"CD" => c.ALU_Op := OP_ROR; c.Flag_Mask := x"90"; -- C(bit7)+Z(bit4)
            when x"CE" => c.ALU_Op := OP_SWP; c.Flag_Mask := x"10";
            when others => null;
        end case;
        return c;
    end function;

begin

    -- =========================================================================
    -- Sequential Process
    -- =========================================================================
    seq_proc : process(clk, reset)
        variable v_raw   : boolean;
        variable v_taken : boolean;
        variable v_nop   : ID_EX_reg_t;
        variable v_c     : control_bus_t;
    begin
        if reset = '1' then
            r_IF_ID      <= NOP_IF_ID;
            r_ID_EX      <= NOP_ID_EX;
            dss          <= DSS_OPCODE;
            ess          <= ESS_IDLE;
            r_exec_IR    <= x"00";
            r_exec_op1   <= x"00";
            r_exec_op2   <= x"00";
            I_Flag       <= '0';
            handling_nmi <= '0';

        elsif rising_edge(clk) then

            if ess /= ESS_IDLE then
                -- ============================================================
                -- ESS: advance execution sub-state
                -- ============================================================
                case ess is
                    when ESS_ADDR_HI =>
                        case r_exec_IR is
                            when x"13"|x"23"             => ess <= ESS_LD_ABS;
                            when x"15"|x"25"             => ess <= ESS_LD_IDX;
                            when x"31"|x"41"             => ess <= ESS_ST_ABS;
                            when x"33"|x"42"             => ess <= ESS_ST_IDX;
                            when x"12"|x"22"|x"30"|x"40" => ess <= ESS_PZ_FETCH;
                            when x"14"|x"24"|x"32"       => ess <= ESS_INDB_SETUP;
                            when x"73"                   => ess <= ESS_IND_LOAD;
                            when x"76"                   => ess <= ESS_CALL_3;
                            when others                  => ess <= ESS_IDLE;
                        end case;

                    when ESS_PZ_FETCH =>
                        if unsigned(r_exec_IR) < x"30" then
                            if r_exec_IR = x"16" then ess <= ESS_LD_IDX;
                            else                      ess <= ESS_LD_ABS; end if;
                        else
                            if r_exec_IR = x"34" then ess <= ESS_ST_IDX;
                            else                      ess <= ESS_ST_ABS; end if;
                        end if;

                    when ESS_INDB_SETUP =>
                        if r_exec_IR = x"32" then ess <= ESS_ST_IDX;
                        else                      ess <= ESS_LD_IDX; end if;

                    -- Cadena LOAD: lectura de memoria → MDR → registro destino
                    when ESS_LD_ABS  => ess <= ESS_LD_WB;  -- leer mem[TMP]   → MDR
                    when ESS_LD_IDX  => ess <= ESS_LD_WB;  -- leer mem[TMP+B] → MDR
                    when ESS_LD_WB   => ess <= ESS_IDLE;   -- MDR → A o B (write-back)
                    -- Cadena STORE: escribe el registro directamente en memoria (1 ciclo)
                    when ESS_ST_ABS  => ess <= ESS_IDLE;   -- A/B → mem[TMP]
                    when ESS_ST_IDX  => ess <= ESS_IDLE;   -- A/B → mem[TMP+B]

                    -- Cadena PUSH (3 ciclos): SP-- / escribir byte bajo / escribir byte alto
                    when ESS_PUSH_1  => ess <= ESS_PUSH_2;
                    when ESS_PUSH_2  => ess <= ESS_PUSH_3;
                    when ESS_PUSH_3  => ess <= ESS_IDLE;   -- fin del push

                    -- Cadena POP: variantes para POP A/B, POP F y POP A:B
                    when ESS_POP_1 =>
                        if r_exec_IR = x"67" then ess <= ESS_POP_AB_2;
                        else                      ess <= ESS_POP_2; end if;
                    when ESS_POP_2 =>
                        if r_exec_IR = x"66" then ess <= ESS_POP_F_2;
                        else                      ess <= ESS_IDLE; end if;
                    when ESS_POP_F_2  => ess <= ESS_IDLE;
                    when ESS_POP_AB_2 => ess <= ESS_POP_AB_3;
                    when ESS_POP_AB_3 => ess <= ESS_IDLE;  -- fin del POP A:B

                    -- Cadena CALL (6 ciclos): fetch addr_L / fetch addr_H /
                    --   SP-- / push PC_L / push PC_H / cargar PC desde TMP
                    when ESS_CALL_1 => ess <= ESS_CALL_2;
                    when ESS_CALL_2 => ess <= ESS_CALL_3;
                    when ESS_CALL_3 => ess <= ESS_CALL_4;
                    when ESS_CALL_4 => ess <= ESS_CALL_5;
                    when ESS_CALL_5 =>
                        if r_exec_IR = x"76" then ess <= ESS_IND_LOAD;
                        else                      ess <= ESS_CALL_6; end if;
                    when ESS_CALL_6 => ess <= ESS_IDLE;    -- PC ← TMP (salto al destino)

                    -- Cadena RET (3 ciclos): pop PC_L / pop PC_H / PC←TMP + SP+=2
                    when ESS_RET_1 => ess <= ESS_RET_2;
                    when ESS_RET_2 => ess <= ESS_RET_3;
                    when ESS_RET_3 => ess <= ESS_IDLE;

                    -- Cadena RTI (4 ciclos): pop F / pop PC_L / pop PC_H / PC←TMP
                    when ESS_RTI_1 => ess <= ESS_RTI_2;
                    when ESS_RTI_2 => ess <= ESS_RTI_3;
                    when ESS_RTI_3 => ess <= ESS_RTI_4;
                    when ESS_RTI_4 => ess <= ESS_JP_3;     -- comparte el salto final con JP

                    -- Cadena INT (9 ciclos): SP-- / push PC_L / push PC_H /
                    --   SP-- / push F / push 0x00 / fetch vec_L / fetch vec_H / PC←TMP
                    when ESS_INT_1 => ess <= ESS_INT_2;
                    when ESS_INT_2 => ess <= ESS_INT_3;
                    when ESS_INT_3 => ess <= ESS_INT_4;
                    when ESS_INT_4 => ess <= ESS_INT_5;
                    when ESS_INT_5 => ess <= ESS_INT_6;
                    when ESS_INT_6 => ess <= ESS_INT_7;
                    when ESS_INT_7 => ess <= ESS_INT_8;
                    when ESS_INT_8 => ess <= ESS_INT_9;
                    when ESS_INT_9 =>
                        ess          <= ESS_IDLE;            -- PC ← TMP (salto al handler)
                        I_Flag       <= '0';                 -- limpiar bandera de interrupción interna
                        handling_nmi <= '0';

                    -- Saltos y ramas (1-2 ciclos extra según tipo)
                    when ESS_BRANCH_2 => ess <= ESS_IDLE;   -- PC ← PC + offset (rama relativa tomada)
                    when ESS_JP_3     => ess <= ESS_IDLE;   -- PC ← TMP (salto absoluto)
                    when ESS_JP_AB    => ess <= ESS_IDLE;   -- PC ← A:B
                    when ESS_JPN_2    => ess <= ESS_IDLE;   -- PC_L ← TMP_L (salto pág. cero)

                    -- Salto indirecto: lee 2 bytes de [TMP] para obtener la dirección destino
                    when ESS_IND_LOAD   => ess <= ESS_IND_READ_L;
                    when ESS_IND_READ_L => ess <= ESS_IND_READ_H;
                    when ESS_IND_READ_H => ess <= ESS_JP_3; -- dirección cargada; compartir salto con JP_3

                    -- Aritmética de 16 bits ADD16/SUB16 (2-4 ciclos según modo)
                    when ESS_OP16_IMM8   => ess <= ESS_OP16_WB2;
                    when ESS_OP16_FETCH1 => ess <= ESS_OP16_WB1;
                    when ESS_OP16_WB1    => ess <= ESS_OP16_WB2;
                    when ESS_OP16_WB2    => ess <= ESS_IDLE; -- byte bajo del resultado → B

                    -- Carga/lectura del Stack Pointer
                    when ESS_LDSP_1  => ess <= ESS_LDSP_2;
                    when ESS_LDSP_2  => ess <= ESS_IDLE;
                    when ESS_LDSP_AB => ess <= ESS_LDSP_2;  -- LD SP,A:B: next cycle loads SP from EA=A:B
                    when ESS_STSP_WB => ess <= ESS_IDLE;    -- byte del SP ya en A

                    -- Operaciones de E/S (IN / OUT)
                    when ESS_IO_FETCH =>
                        if r_exec_IR = x"D0" then ess <= ESS_IN_READ;
                        else                      ess <= ESS_OUT_WRITE; end if;
                    when ESS_IO_SETUP =>
                        if r_exec_IR = x"D1" then ess <= ESS_IN_READ;
                        else                      ess <= ESS_OUT_WRITE; end if;
                    when ESS_IN_READ   => ess <= ESS_IN_WB;
                    when ESS_IN_WB     => ess <= ESS_IDLE;
                    when ESS_OUT_WRITE => ess <= ESS_IDLE;

                    when ESS_SKIP_BYTE => ess <= ESS_IDLE;
                    when ESS_HALT      => ess <= ESS_HALT;

                    -- Pipeline TMP loading: load TMP from r_exec_op1 (low) then r_exec_op2 (high)
                    -- without accessing memory.  Two sequential states load each byte, then
                    -- dispatch to the appropriate subsequent ESS state based on r_exec_IR.
                    when ESS_TMP_FROM_OP1 =>
                        -- After loading TMP_L, decide if we also need to load TMP_H (3-byte ops)
                        -- or if TMP_H is already 0 (2-byte zero-page ops).
                        case r_exec_IR is
                            -- 2-byte zero-page [n] loads: TMP_H=0, dispatch to ESS_LD_ABS.
                            when x"12"|x"22"             => ess <= ESS_LD_ABS;
                            -- 2-byte zero-page [n+B] load/store: TMP_H=0, dispatch to IDX.
                            when x"16"                   => ess <= ESS_LD_IDX;
                            when x"34"                   => ess <= ESS_ST_IDX;
                            -- 2-byte zero-page [n] stores: TMP_H=0, dispatch to ESS_ST_ABS.
                            when x"30"|x"40"             => ess <= ESS_ST_ABS;
                            -- 2-byte I/O immediate: TMP_L=port, TMP_H=0; dispatch to I/O.
                            when x"D0"                   => ess <= ESS_IN_READ;
                            when x"D2"                   => ess <= ESS_OUT_WRITE;
                            -- JPN (2-byte): TMP_L ya cargado → salto directo página cero.
                            when x"72"                   => ess <= ESS_JPN_2;
                            -- ADD16/SUB16 #n (2-byte): TMP_L=op1, TMP_H=0 → WB1.
                            when x"E0"|x"E2"             => ess <= ESS_OP16_WB1;
                            -- All 3-byte ops: also need TMP_H from r_exec_op2
                            when others                  => ess <= ESS_TMP_FROM_OP2;
                        end case;

                    when ESS_TMP_FROM_OP2 =>
                        -- TMP is now fully loaded (both bytes).  Dispatch to the correct
                        -- execution state based on the instruction opcode.
                        case r_exec_IR is
                            when x"13"|x"23"             => ess <= ESS_LD_ABS;
                            when x"15"|x"25"             => ess <= ESS_LD_IDX;
                            when x"31"|x"41"             => ess <= ESS_ST_ABS;
                            when x"33"|x"42"             => ess <= ESS_ST_IDX;
                            when x"70"                   => ess <= ESS_JP_3;
                            when x"75"|x"76"             => ess <= ESS_CALL_3;
                            when x"50"                   => ess <= ESS_LDSP_2;
                            when x"E1"|x"E3"             => ess <= ESS_OP16_WB1;
                            when others                  => ess <= ESS_IDLE;
                        end case;

                    when others => ess <= ESS_IDLE;
                end case;

                -- ESS is active: pipeline is frozen, no new fetch/decode.

            else
                -- ============================================================
                -- ESS_IDLE: Normal pipeline operation
                -- ============================================================

                -- ----------------------------------------------------------
                -- EXEC stage: process r_ID_EX
                -- ----------------------------------------------------------
                if r_ID_EX.valid = '1' then
                    if r_ID_EX.is_multi = '1' then
                        -- Latch operands, start ESS, consume r_ID_EX
                        r_exec_IR  <= r_ID_EX.opcode;
                        r_exec_op1 <= r_ID_EX.op1;
                        r_exec_op2 <= r_ID_EX.op2;
                        r_ID_EX    <= NOP_ID_EX;
                        report "DBG ESS_DISPATCH: opcode=0x" & to_hstring(r_ID_EX.opcode) &
                               " op1=0x" & to_hstring(r_ID_EX.op1) &
                               " op2=0x" & to_hstring(r_ID_EX.op2) severity note;

                        -- Choose first ESS state from opcode
                        case r_ID_EX.opcode is
                            when x"01"                   => ess <= ESS_HALT;
                            when x"06"                   => ess <= ESS_RTI_1;
                            when x"14"|x"24"             => ess <= ESS_INDB_SETUP;
                            when x"32"                   => ess <= ESS_INDB_SETUP;
                            -- [n] zero-page 2-byte modes: op1 = byte address, op2 unused.
                            -- ESS_TMP_FROM_OP1 will: Clear_TMP=1 (force TMP_H=0), Load_TMP_L=op1,
                            -- Op_Sel=1 (use Op_Data from pipeline), then dispatch to ESS_LD/ST_ABS.
                            when x"12"|x"22"|x"30"|x"40" => ess <= ESS_TMP_FROM_OP1;
                            when x"16"|x"34"             => ess <= ESS_TMP_FROM_OP1;
                            -- [nn] 3-byte absolute modes: op1=addr_L, op2=addr_H.
                            -- ESS_TMP_FROM_OP1 loads TMP_L, then ESS_TMP_FROM_OP2 loads TMP_H.
                            when x"13"|x"23"             => ess <= ESS_TMP_FROM_OP1;
                            when x"31"|x"41"             => ess <= ESS_TMP_FROM_OP1;
                            -- [nn+B] 3-byte indexed modes: op1=base_L, op2=base_H.
                            when x"15"|x"25"             => ess <= ESS_TMP_FROM_OP1;
                            when x"33"|x"42"             => ess <= ESS_TMP_FROM_OP1;
                            -- JP nn (3-byte): op1=addr_L, op2=addr_H.
                            when x"70"                   => ess <= ESS_TMP_FROM_OP1;
                            when x"71"|x"80"|x"81"|x"82"|x"83"|x"84"|x"85"|
                                 x"86"|x"87"|x"88"|x"89"|x"8A"|x"8B" =>
                                v_taken := branch_taken_f(r_ID_EX.opcode, FlagsIn);
                                if v_taken then
                                    ess     <= ESS_BRANCH_2;
                                    r_IF_ID <= NOP_IF_ID; -- flush speculative fetch
                                else
                                    ess <= ESS_SKIP_BYTE;
                                end if;
                            when x"72"             => ess <= ESS_TMP_FROM_OP1; -- JPN: carga TMP_L desde r_exec_op1
                            when x"73"             => ess <= ESS_IND_LOAD;
                            when x"74"             => ess <= ESS_JP_AB;
                            -- CALL nn / BSR nn (3-byte): op1=addr_L, op2=addr_H.
                            -- ESS_TMP_FROM_OP1/OP2 will load TMP, then ESS_TMP_FROM_OP2
                            -- dispatches to ESS_CALL_3 (SP--, push PC, jump to TMP).
                            when x"75"|x"76"             => ess <= ESS_TMP_FROM_OP1;
                            when x"77"             => ess <= ESS_RET_1;
                            -- IN/OUT with immediate port: op1 = port number.
                            -- ESS_TMP_FROM_OP1 loads TMP_L = port, TMP_H = 0.
                            when x"D0"|x"D2"             => ess <= ESS_TMP_FROM_OP1;
                            -- IN A,[B] / OUT [B],A: 1-byte instructions, no operand.
                            -- ESS_IO_SETUP clears TMP; EA = 0+B = port address.
                            when x"D1"|x"D3"             => ess <= ESS_IO_SETUP;
                            -- LD SP,#nn (3-byte): op1=val_L, op2=val_H.
                            -- Load TMP from ops, then ESS_TMP_FROM_OP2 → ESS_LDSP_2.
                            when x"50"                   => ess <= ESS_TMP_FROM_OP1;
                            when x"51"                   => ess <= ESS_LDSP_AB;
                            when x"52"|x"53"             => ess <= ESS_STSP_WB;
                            when x"60"|x"61"|x"62"|x"63" => ess <= ESS_PUSH_1;
                            when x"64"|x"65"|x"66"|x"67" => ess <= ESS_POP_1;
                            -- ADD16/SUB16 #n (2-byte IMM8): op1 = imm byte → TMP_L, TMP_H=0.
                            -- ADD16/SUB16 #nn (3-byte): op1=low, op2=high → TMP.
                            -- Both routes through ESS_TMP_FROM_OP1 → ESS_OP16_WB1.
                            when x"E0"|x"E1"|x"E2"|x"E3" => ess <= ESS_TMP_FROM_OP1;
                            when others            => ess <= ESS_IDLE;
                        end case;

                    elsif r_ID_EX.is_single = '1' then
                        -- Single-cycle: the comb_proc drives ctrl this cycle.
                        -- Consume the r_ID_EX entry.
                        r_ID_EX <= NOP_ID_EX;
                        -- Update I_Flag for SEI/CLI
                        if r_ID_EX.opcode = x"04" then I_Flag <= '1';
                        elsif r_ID_EX.opcode = x"05" then I_Flag <= '0';
                        end if;
                    end if;
                end if; -- r_ID_EX.valid

                -- ----------------------------------------------------------
                -- DECODE stage: process r_IF_ID
                -- Build r_ID_EX when r_ID_EX is empty and no hazard.
                -- ----------------------------------------------------------
                if r_IF_ID.valid = '1' and r_ID_EX.valid = '0' then
                    -- RAW hazard check (against the entry we JUST consumed this cycle;
                    -- since we cleared r_ID_EX above the hazard check must use a snapshot.
                    -- We detect hazards conservatively: stall if there is a pending
                    -- single-cycle write that hasn't retired yet.
                    -- In this implementation, since single-cycle instructions take 1 clock
                    -- and we consume r_ID_EX before the DECODE runs in the same cycle,
                    -- the result is available at the start of the NEXT cycle.  Therefore
                    -- a 1-cycle stall is required any time the just-launched EX writes
                    -- a register the next instruction reads.
                    -- The hazard is already gone if r_ID_EX.valid was '0' before we got here.
                    -- We insert the stall by NOT writing r_ID_EX this cycle, holding r_IF_ID.
                    v_raw := false; -- no hazard by default when r_ID_EX.valid was already '0'

                    if not v_raw then
                        case dss is
                            -- ---------------------------------------------------
                            -- DSS_OPCODE: first decode cycle, build or start fetch
                            -- ---------------------------------------------------
                            when DSS_OPCODE =>
                                case r_IF_ID.opcode is

                                    -- NOP
                                    when x"00" =>
                                        r_ID_EX <= (valid=>'1', opcode=>x"00",
                                            op1=>x"00", op2=>x"00", ctrl=>INIT_CTRL_BUS,
                                            writes_a=>'0', writes_b=>'0',
                                            reads_a=>'0', reads_b=>'0',
                                            is_single=>'1', is_multi=>'0');
                                        r_IF_ID <= NOP_IF_ID;

                                    -- SEC
                                    when x"02" =>
                                        v_c := INIT_CTRL_BUS;
                                        v_c.ALU_Op    := OP_CMP;
                                        v_c.Reg_Sel   := (others => '0');
                                        v_c.Bus_Op    := ACC_ALU_elected;
                                        v_c.Write_F   := '1';
                                        v_c.Flag_Mask := x"80";
                                        r_ID_EX <= (valid=>'1', opcode=>x"02",
                                            op1=>x"00", op2=>x"00", ctrl=>v_c,
                                            writes_a=>'0', writes_b=>'0',
                                            reads_a=>'1', reads_b=>'0',
                                            is_single=>'1', is_multi=>'0');
                                        r_IF_ID <= NOP_IF_ID;

                                    -- CLC
                                    when x"03" =>
                                        v_c := INIT_CTRL_BUS;
                                        v_c.ALU_Op    := OP_AND;
                                        v_c.Reg_Sel   := (others => '0');
                                        v_c.Bus_Op    := ACC_ALU_elected;
                                        v_c.Write_F   := '1';
                                        v_c.Flag_Mask := x"80";
                                        r_ID_EX <= (valid=>'1', opcode=>x"03",
                                            op1=>x"00", op2=>x"00", ctrl=>v_c,
                                            writes_a=>'0', writes_b=>'0',
                                            reads_a=>'1', reads_b=>'0',
                                            is_single=>'1', is_multi=>'0');
                                        r_IF_ID <= NOP_IF_ID;

                                    -- SEI / CLI: NOP ctrl, I_Flag updated in EX stage
                                    when x"04" | x"05" =>
                                        r_ID_EX <= (valid=>'1', opcode=>r_IF_ID.opcode,
                                            op1=>x"00", op2=>x"00", ctrl=>INIT_CTRL_BUS,
                                            writes_a=>'0', writes_b=>'0',
                                            reads_a=>'0', reads_b=>'0',
                                            is_single=>'1', is_multi=>'0');
                                        r_IF_ID <= NOP_IF_ID;

                                    -- RTI (0x06): multi-cycle
                                    when x"06" =>
                                        r_ID_EX <= (valid=>'1', opcode=>x"06",
                                            op1=>x"00", op2=>x"00", ctrl=>INIT_CTRL_BUS,
                                            writes_a=>'0', writes_b=>'0',
                                            reads_a=>'0', reads_b=>'0',
                                            is_single=>'0', is_multi=>'1');
                                        r_IF_ID <= NOP_IF_ID;

                                    -- HALT (0x01): multi-cycle
                                    when x"01" =>
                                        r_ID_EX <= (valid=>'1', opcode=>x"01",
                                            op1=>x"00", op2=>x"00", ctrl=>INIT_CTRL_BUS,
                                            writes_a=>'0', writes_b=>'0',
                                            reads_a=>'0', reads_b=>'0',
                                            is_single=>'0', is_multi=>'1');
                                        r_IF_ID <= NOP_IF_ID;

                                    -- LD A,B (0x10)
                                    when x"10" =>
                                        v_c := INIT_CTRL_BUS;
                                        v_c.ALU_Op  := OP_PSB;
                                        v_c.Reg_Sel := std_logic_vector(to_unsigned(1, REG_SEL_WIDTH));
                                        v_c.Bus_Op  := ACC_ALU_elected;
                                        v_c.Write_A := '1';
                                        v_c.Write_F := '1';
                                        v_c.Flag_Mask(idx_fZ) := '1';
                                        r_ID_EX <= (valid=>'1', opcode=>x"10",
                                            op1=>x"00", op2=>x"00", ctrl=>v_c,
                                            writes_a=>'1', writes_b=>'0',
                                            reads_a=>'0', reads_b=>'1',
                                            is_single=>'1', is_multi=>'0');
                                        r_IF_ID <= NOP_IF_ID;

                                    -- LD B,A (0x20)
                                    when x"20" =>
                                        v_c := INIT_CTRL_BUS;
                                        v_c.ALU_Op  := OP_PSA;
                                        v_c.Reg_Sel := std_logic_vector(to_unsigned(1, REG_SEL_WIDTH));
                                        v_c.Bus_Op  := ACC_ALU_elected;
                                        v_c.Write_B := '1';
                                        r_ID_EX <= (valid=>'1', opcode=>x"20",
                                            op1=>x"00", op2=>x"00", ctrl=>v_c,
                                            writes_a=>'0', writes_b=>'1',
                                            reads_a=>'1', reads_b=>'0',
                                            is_single=>'1', is_multi=>'0');
                                        r_IF_ID <= NOP_IF_ID;

                                    -- LD A,[B] (0x14): multi-cycle, 1-byte
                                    when x"14" =>
                                        r_ID_EX <= (valid=>'1', opcode=>x"14",
                                            op1=>x"00", op2=>x"00", ctrl=>INIT_CTRL_BUS,
                                            writes_a=>'1', writes_b=>'0',
                                            reads_a=>'0', reads_b=>'1',
                                            is_single=>'0', is_multi=>'1');
                                        r_IF_ID <= NOP_IF_ID;

                                    -- LD B,[B] (0x24): multi-cycle, 1-byte
                                    when x"24" =>
                                        r_ID_EX <= (valid=>'1', opcode=>x"24",
                                            op1=>x"00", op2=>x"00", ctrl=>INIT_CTRL_BUS,
                                            writes_a=>'0', writes_b=>'1',
                                            reads_a=>'0', reads_b=>'1',
                                            is_single=>'0', is_multi=>'1');
                                        r_IF_ID <= NOP_IF_ID;

                                    -- ST A,[B] (0x32): multi-cycle, 1-byte
                                    when x"32" =>
                                        r_ID_EX <= (valid=>'1', opcode=>x"32",
                                            op1=>x"00", op2=>x"00", ctrl=>INIT_CTRL_BUS,
                                            writes_a=>'0', writes_b=>'0',
                                            reads_a=>'1', reads_b=>'1',
                                            is_single=>'0', is_multi=>'1');
                                        r_IF_ID <= NOP_IF_ID;

                                    -- ALU reg ops (0x90..0x97): single-cycle
                                    when x"90"|x"91"|x"92"|x"93"|x"94"|x"95"|x"96"|x"97" =>
                                        v_c := build_alu_reg(r_IF_ID.opcode);
                                        r_ID_EX <= (valid=>'1', opcode=>r_IF_ID.opcode,
                                            op1=>x"00", op2=>x"00", ctrl=>v_c,
                                            writes_a=>v_c.Write_A, writes_b=>'0',
                                            reads_a=>'1', reads_b=>'1',
                                            is_single=>'1', is_multi=>'0');
                                        r_IF_ID <= NOP_IF_ID;

                                    -- MUL/MUH (0x98..0x99): single-cycle, A = A×B low/high
                                    when x"98"|x"99" =>
                                        v_c := build_alu_reg(r_IF_ID.opcode);
                                        r_ID_EX <= (valid=>'1', opcode=>r_IF_ID.opcode,
                                            op1=>x"00", op2=>x"00", ctrl=>v_c,
                                            writes_a=>'1', writes_b=>'0',
                                            reads_a=>'1', reads_b=>'1',
                                            is_single=>'1', is_multi=>'0');
                                        r_IF_ID <= NOP_IF_ID;

                                    -- ALU unary ops (0xC0..0xCE): single-cycle
                                    when x"C0"|x"C1"|x"C2"|x"C3"|x"C4"|x"C5"|x"C6"|x"C7"|
                                         x"C8"|x"C9"|x"CA"|x"CB"|x"CC"|x"CD"|x"CE" =>
                                        v_c := build_alu_unary(r_IF_ID.opcode);
                                        r_ID_EX <= (valid=>'1', opcode=>r_IF_ID.opcode,
                                            op1=>x"00", op2=>x"00", ctrl=>v_c,
                                            writes_a=>v_c.Write_A, writes_b=>v_c.Write_B,
                                            reads_a=>reads_a_f(r_IF_ID.opcode),
                                            reads_b=>reads_b_f(r_IF_ID.opcode),
                                            is_single=>'1', is_multi=>'0');
                                        r_IF_ID <= NOP_IF_ID;

                                    -- PUSH * (0x60..0x63): multi-cycle, 1-byte
                                    when x"60"|x"61"|x"62"|x"63" =>
                                        r_ID_EX <= (valid=>'1', opcode=>r_IF_ID.opcode,
                                            op1=>x"00", op2=>x"00", ctrl=>INIT_CTRL_BUS,
                                            writes_a=>'0', writes_b=>'0',
                                            reads_a=>reads_a_f(r_IF_ID.opcode),
                                            reads_b=>reads_b_f(r_IF_ID.opcode),
                                            is_single=>'0', is_multi=>'1');
                                        r_IF_ID <= NOP_IF_ID;

                                    -- POP * (0x64..0x67): multi-cycle, 1-byte
                                    when x"64"|x"65"|x"66"|x"67" =>
                                        r_ID_EX <= (valid=>'1', opcode=>r_IF_ID.opcode,
                                            op1=>x"00", op2=>x"00", ctrl=>INIT_CTRL_BUS,
                                            writes_a=>writes_a_f(r_IF_ID.opcode),
                                            writes_b=>writes_b_f(r_IF_ID.opcode),
                                            reads_a=>'0', reads_b=>'0',
                                            is_single=>'0', is_multi=>'1');
                                        r_IF_ID <= NOP_IF_ID;

                                    -- JP A:B (0x74): multi-cycle, 1-byte
                                    when x"74" =>
                                        r_ID_EX <= (valid=>'1', opcode=>x"74",
                                            op1=>x"00", op2=>x"00", ctrl=>INIT_CTRL_BUS,
                                            writes_a=>'0', writes_b=>'0',
                                            reads_a=>'1', reads_b=>'1',
                                            is_single=>'0', is_multi=>'1');
                                        r_IF_ID <= NOP_IF_ID;

                                    -- LD SP,A:B (0x51): multi-cycle, 1-byte
                                    when x"51" =>
                                        r_ID_EX <= (valid=>'1', opcode=>x"51",
                                            op1=>x"00", op2=>x"00", ctrl=>INIT_CTRL_BUS,
                                            writes_a=>'0', writes_b=>'0',
                                            reads_a=>'1', reads_b=>'1',
                                            is_single=>'0', is_multi=>'1');
                                        r_IF_ID <= NOP_IF_ID;

                                    -- ST SP_L,A / ST SP_H,A (0x52..0x53): multi-cycle, 1-byte
                                    when x"52"|x"53" =>
                                        r_ID_EX <= (valid=>'1', opcode=>r_IF_ID.opcode,
                                            op1=>x"00", op2=>x"00", ctrl=>INIT_CTRL_BUS,
                                            writes_a=>'1', writes_b=>'0',
                                            reads_a=>'0', reads_b=>'0',
                                            is_single=>'0', is_multi=>'1');
                                        r_IF_ID <= NOP_IF_ID;

                                    -- RET (0x77): multi-cycle, 1-byte
                                    when x"77" =>
                                        r_ID_EX <= (valid=>'1', opcode=>x"77",
                                            op1=>x"00", op2=>x"00", ctrl=>INIT_CTRL_BUS,
                                            writes_a=>'0', writes_b=>'0',
                                            reads_a=>'0', reads_b=>'0',
                                            is_single=>'0', is_multi=>'1');
                                        r_IF_ID <= NOP_IF_ID;

                                    -- IN A,[B] (0xD1): multi-cycle, 1-byte
                                    when x"D1" =>
                                        r_ID_EX <= (valid=>'1', opcode=>x"D1",
                                            op1=>x"00", op2=>x"00", ctrl=>INIT_CTRL_BUS,
                                            writes_a=>'1', writes_b=>'0',
                                            reads_a=>'0', reads_b=>'1',
                                            is_single=>'0', is_multi=>'1');
                                        r_IF_ID <= NOP_IF_ID;

                                    -- OUT [B],A (0xD3): multi-cycle, 1-byte
                                    when x"D3" =>
                                        r_ID_EX <= (valid=>'1', opcode=>x"D3",
                                            op1=>x"00", op2=>x"00", ctrl=>INIT_CTRL_BUS,
                                            writes_a=>'0', writes_b=>'0',
                                            reads_a=>'1', reads_b=>'1',
                                            is_single=>'0', is_multi=>'1');
                                        r_IF_ID <= NOP_IF_ID;

                                    -- Conditional branches & JR (0x71, 0x80..0x8B): 2-byte multi
                                    -- offset se recupera desde DATA_IN en ESS_BRANCH_2
                                    when x"71"|
                                         x"80"|x"81"|x"82"|x"83"|x"84"|x"85"|
                                         x"86"|x"87"|x"88"|x"89"|x"8A"|x"8B" =>
                                        r_ID_EX <= (valid=>'1', opcode=>r_IF_ID.opcode,
                                            op1=>x"00", op2=>x"00", ctrl=>INIT_CTRL_BUS,
                                            writes_a=>'0', writes_b=>'0',
                                            reads_a=>'0', reads_b=>'0',
                                            is_single=>'0', is_multi=>'1');
                                        r_IF_ID <= NOP_IF_ID;

                                    -- JPN (0x72): 2-byte multi, op1 = destino página cero
                                    when x"72" =>
                                        dss <= DSS_OP1;
                                        -- Hold r_IF_ID (keep opcode=0x72), operand arrives in DSS_OP1

                                    -- =========================================
                                    -- 2-byte instructions: fetch OP1 via dss
                                    -- =========================================
                                    -- LD A,#n (0x11)  LD B,#n (0x21)
                                    -- ALU imm (0xA0..0xA7)
                                    -- IN A,#n (0xD0)  OUT #n,A (0xD2)
                                    -- ADD16 #n (0xE0)  SUB16 #n (0xE2)
                                    -- LD A,[n] (0x12)  LD B,[n] (0x22)
                                    -- ST A,[n] (0x30)  ST B,[n] (0x40)
                                    -- LD A,[n+B] (0x16) ST A,[n+B] (0x34)
                                    when x"11"|x"21"|
                                         x"A0"|x"A1"|x"A2"|x"A3"|x"A4"|x"A5"|x"A6"|x"A7"|
                                         x"D0"|x"D2"|x"E0"|x"E2"|
                                         x"12"|x"22"|x"30"|x"40"|x"16"|x"34" =>
                                        -- Hold r_IF_ID, start OP1 fetch
                                        dss <= DSS_OP1;
                                        -- Do NOT modify r_IF_ID (keep valid + opcode)
                                        -- r_ID_EX remains NOP until OP1 arrives

                                    -- =========================================
                                    -- 3-byte instructions: fetch OP1 via dss
                                    -- =========================================
                                    when x"13"|x"23"|x"15"|x"25"|
                                         x"31"|x"33"|x"41"|x"42"|
                                         x"50"|x"70"|x"73"|x"75"|x"76"|
                                         x"E1"|x"E3" =>
                                        dss <= DSS_OP1;
                                        -- Hold r_IF_ID, start OP1 fetch

                                    when others =>
                                        -- Unknown: NOP
                                        r_ID_EX <= (valid=>'1', opcode=>r_IF_ID.opcode,
                                            op1=>x"00", op2=>x"00", ctrl=>INIT_CTRL_BUS,
                                            writes_a=>'0', writes_b=>'0',
                                            reads_a=>'0', reads_b=>'0',
                                            is_single=>'1', is_multi=>'0');
                                        r_IF_ID <= NOP_IF_ID;
                                end case;

                            -- ---------------------------------------------------
                            -- DSS_OP1: first operand byte available on InstrIn
                            -- ---------------------------------------------------
                            when DSS_OP1 =>
                                case r_IF_ID.opcode is
                                    -- LD A,#n
                                    when x"11" =>
                                        v_c := INIT_CTRL_BUS;
                                        -- MDR_WE already applied in comb_proc DSS_OP1 cycle
                                        v_c.Bus_Op  := MEM_MDR_elected;
                                        v_c.Write_A := '1';
                                        v_c.Write_F := '1';
                                        v_c.Flag_Mask(idx_fZ) := '1';
                                        r_ID_EX <= (valid=>'1', opcode=>x"11",
                                            op1=>InstrIn, op2=>x"00", ctrl=>v_c,
                                            writes_a=>'1', writes_b=>'0',
                                            reads_a=>'0', reads_b=>'0',
                                            is_single=>'1', is_multi=>'0');
                                        r_IF_ID <= NOP_IF_ID;
                                        dss <= DSS_OPCODE;

                                    -- LD B,#n
                                    when x"21" =>
                                        v_c := INIT_CTRL_BUS;
                                        -- MDR_WE already applied in comb_proc DSS_OP1 cycle
                                        v_c.Bus_Op  := MEM_MDR_elected;
                                        v_c.Reg_Sel := std_logic_vector(to_unsigned(1, REG_SEL_WIDTH));
                                        v_c.Write_B := '1';
                                        r_ID_EX <= (valid=>'1', opcode=>x"21",
                                            op1=>InstrIn, op2=>x"00", ctrl=>v_c,
                                            writes_a=>'0', writes_b=>'1',
                                            reads_a=>'0', reads_b=>'0',
                                            is_single=>'1', is_multi=>'0');
                                        r_IF_ID <= NOP_IF_ID;
                                        dss <= DSS_OPCODE;

                                    -- ALU immediate: MDR has the operand byte
                                    when x"A0"|x"A1"|x"A2"|x"A3"|x"A4"|x"A5"|x"A6"|x"A7" =>
                                        v_c := build_alu_imm(r_IF_ID.opcode);
                                        -- MDR_WE already applied in comb_proc DSS_OP1 cycle
                                        r_ID_EX <= (valid=>'1', opcode=>r_IF_ID.opcode,
                                            op1=>InstrIn, op2=>x"00", ctrl=>v_c,
                                            writes_a=>v_c.Write_A, writes_b=>'0',
                                            reads_a=>'1', reads_b=>'0',
                                            is_single=>'1', is_multi=>'0');
                                        r_IF_ID <= NOP_IF_ID;
                                        dss <= DSS_OPCODE;

                                    -- 2-byte mem ops: op1 is address or port (multi-cycle)
                                    when x"12"|x"22"|x"30"|x"40"|x"16"|x"34"|
                                         x"D0"|x"D2"|x"E0"|x"E2" =>
                                        r_ID_EX <= (valid=>'1', opcode=>r_IF_ID.opcode,
                                            op1=>InstrIn, op2=>x"00", ctrl=>INIT_CTRL_BUS,
                                            writes_a=>writes_a_f(r_IF_ID.opcode),
                                            writes_b=>writes_b_f(r_IF_ID.opcode),
                                            reads_a=>reads_a_f(r_IF_ID.opcode),
                                            reads_b=>reads_b_f(r_IF_ID.opcode),
                                            is_single=>'0', is_multi=>'1');
                                        r_IF_ID <= NOP_IF_ID;
                                        dss <= DSS_OPCODE;

                                    -- 3-byte instructions: save op1, go to DSS_OP2
                                    when others =>
                                        -- Temporarily store op1 in r_ID_EX (not valid yet)
                                        r_ID_EX <= (valid=>'0', opcode=>r_IF_ID.opcode,
                                            op1=>InstrIn, op2=>x"00", ctrl=>INIT_CTRL_BUS,
                                            writes_a=>'0', writes_b=>'0',
                                            reads_a=>'0', reads_b=>'0',
                                            is_single=>'0', is_multi=>'0');
                                        dss <= DSS_OP2;
                                        report "DBG DSS_OP1->OP2: opcode=0x" & to_hstring(r_IF_ID.opcode) &
                                               " op1=0x" & to_hstring(InstrIn) severity note;
                                        -- Keep r_IF_ID valid for opcode reference
                                end case;

                            -- ---------------------------------------------------
                            -- DSS_OP2: second operand byte available on InstrIn
                            -- ---------------------------------------------------
                            when DSS_OP2 =>
                                -- r_ID_EX.op1 holds first operand, InstrIn = op2
                                r_ID_EX <= (valid=>'1', opcode=>r_IF_ID.opcode,
                                    op1=>r_ID_EX.op1, op2=>InstrIn,
                                    ctrl=>INIT_CTRL_BUS,
                                    writes_a=>writes_a_f(r_IF_ID.opcode),
                                    writes_b=>writes_b_f(r_IF_ID.opcode),
                                    reads_a=>reads_a_f(r_IF_ID.opcode),
                                    reads_b=>reads_b_f(r_IF_ID.opcode),
                                    is_single=>'0', is_multi=>'1');
                                r_IF_ID <= NOP_IF_ID;
                                dss <= DSS_OPCODE;
                                report "DBG DSS_OP2: opcode=0x" & to_hstring(r_IF_ID.opcode) &
                                       " op1=0x" & to_hstring(r_ID_EX.op1) &
                                       " op2=0x" & to_hstring(InstrIn) severity note;

                            when others => null;
                        end case;
                    end if; -- not v_raw
                end if; -- r_IF_ID.valid and r_ID_EX.valid='0'

                -- ----------------------------------------------------------
                -- FETCH stage: latch incoming opcode into r_IF_ID
                -- This happens when r_IF_ID is empty and no multi-cycle
                -- operation is consuming the memory bus.
                -- The comb_proc asserts ABUS=PC and Mem_RE when fetch is
                -- possible; we sample InstrIn here.
                -- ----------------------------------------------------------
                -- Fetch conditions:
                --   ess=IDLE (no multi-cycle in flight)
                --   r_IF_ID.valid='0' (IF/ID stage empty)
                --   dss=DSS_OPCODE (not in middle of operand fetch)
                --   r_ID_EX.valid='0' (ID/EX stage also empty, so no hazard risk)
                -- The operand fetches for 2-byte/3-byte instructions use the
                -- same bus as the opcode fetch; they are handled by the DSS logic
                -- above. During DSS_OP1/DSS_OP2, the comb_proc drives ABUS=PC
                -- for the operand, not for a new opcode.

                if r_IF_ID.valid = '0' and dss = DSS_OPCODE and
                   (r_ID_EX.valid = '0' or r_ID_EX.is_single = '1') and
                   ess = ESS_IDLE
                then
                    if Mem_Ready = '1' then
                        r_IF_ID <= (valid => '1', opcode => InstrIn);
                    end if;
                end if;

                -- Interrupt check: taken when pipeline is fully idle
                if r_IF_ID.valid = '0' and r_ID_EX.valid = '0' and
                   dss = DSS_OPCODE and ess = ESS_IDLE
                then
                    if NMI = '1' then
                        handling_nmi <= '1';
                        ess          <= ESS_INT_1;
                    elsif IRQ = '1' and I_Flag = '1' then
                        handling_nmi <= '0';
                        ess          <= ESS_INT_1;
                    end if;
                end if;

            end if; -- ess /= IDLE / IDLE
        end if; -- reset / rising_edge
    end process seq_proc;

    -- =========================================================================
    -- Combinatorial Process: drive CtrlBus
    -- =========================================================================
    comb_proc : process(ess, r_ID_EX, r_IF_ID, r_exec_IR, r_exec_op1, r_exec_op2,
                        FlagsIn, InstrIn, Mem_Ready, NMI, IRQ, I_Flag,
                        handling_nmi, dss)
        variable v_ctrl     : control_bus_t;
        variable v_fetch_ok : boolean;
        variable v_needs_mem: boolean;
    begin
        v_ctrl      := INIT_CTRL_BUS;
        v_fetch_ok  := false;
        v_needs_mem := false;

        -- =====================================================================
        -- Priority 1: ESS multi-cycle execution
        -- =====================================================================
        if ess /= ESS_IDLE then

            case ess is
                when ESS_ADDR_HI =>
                    -- Ciclo: lee el byte alto de la dirección desde [PC] → TMP_H; PC++.
                    -- El estado siguiente depende del opcode en r_exec_IR.
                    v_ctrl.ABUS_Sel   := ABUS_SRC_PC;
                    v_ctrl.Mem_RE     := '1';
                    v_ctrl.Load_TMP_H := '1';
                    v_ctrl.PC_Op      := PC_OP_INC;
                    v_needs_mem := true;

                when ESS_PZ_FETCH =>
                    -- Ciclo: lee la dirección de página cero desde [PC] → TMP_L;
                    -- fuerza TMP_H = 0 (Clear_TMP); PC++.
                    v_ctrl.ABUS_Sel   := ABUS_SRC_PC;
                    v_ctrl.Load_TMP_L := '1';
                    v_ctrl.PC_Op      := PC_OP_INC;
                    v_needs_mem := true;

                when ESS_INDB_SETUP =>
                    -- Ciclo: limpia TMP (base=0) para el modo [B] (dirección = 0 + B).
                    -- No usa el bus de memoria; el siguiente ciclo usa EA = TMP + B.
                    v_ctrl.Clear_TMP := '1';

                when ESS_LD_ABS =>
                    -- Ciclo: lee mem[TMP] → MDR. Dirección absoluta almacenada en TMP.
                    v_ctrl.EA_A_Sel := EA_A_SRC_TMP;
                    v_ctrl.EA_B_Sel := EA_B_SRC_ZERO;
                    v_ctrl.ABUS_Sel := ABUS_SRC_EA_RES;
                    v_ctrl.Mem_RE   := '1';
                    v_ctrl.MDR_WE   := '1';
                    v_needs_mem := true;

                when ESS_LD_IDX =>
                    -- Ciclo: lee mem[TMP + B] → MDR. TMP = base, B = índice.
                    -- Force_ZP fuerza la suma a 8 bits (modo [n+B] de pág. cero).
                    v_ctrl.EA_A_Sel := EA_A_SRC_TMP;
                    v_ctrl.EA_B_Sel := EA_B_SRC_REG_B;
                    v_ctrl.ABUS_Sel := ABUS_SRC_EA_RES;
                    v_ctrl.Mem_RE   := '1';
                    v_ctrl.MDR_WE   := '1';
                    if r_exec_IR = x"16" or r_exec_IR = x"34" then
                        v_ctrl.Force_ZP := '1';
                    end if;
                    v_needs_mem := true;

                when ESS_LD_WB =>
                    -- Ciclo write-back: escribe MDR en A o B según el nibble alto del opcode.
                    -- Bit 4 del opcode: '1' = LD A (familia 0x1x), '0' = LD B (familia 0x2x).
                    v_ctrl.Bus_Op := MEM_MDR_elected;
                    -- opcodes 1x = LD A, 2x = LD B (bit 4 distinguishes)
                    if r_exec_IR(4) = '1' then
                        v_ctrl.Write_A := '1';
                    else
                        v_ctrl.Write_B := '1';
                        v_ctrl.Reg_Sel := std_logic_vector(to_unsigned(1, REG_SEL_WIDTH));
                    end if;
                    v_ctrl.Write_F := '1';
                    v_ctrl.Flag_Mask(idx_fZ) := '1';

                when ESS_ST_ABS =>
                    -- Ciclo: escribe A o B en mem[TMP]. Bit 4 del opcode selecciona la fuente.
                    v_ctrl.EA_A_Sel := EA_A_SRC_TMP;
                    v_ctrl.EA_B_Sel := EA_B_SRC_ZERO;
                    v_ctrl.ABUS_Sel := ABUS_SRC_EA_RES;
                    if r_exec_IR(4) = '1' then v_ctrl.Out_Sel := OUT_SEL_A;
                    else                        v_ctrl.Out_Sel := OUT_SEL_B; end if;
                    v_ctrl.Mem_WE   := '1';
                    v_needs_mem := true;

                when ESS_ST_IDX =>
                    -- Ciclo: escribe A o B en mem[TMP + B]. Force_ZP para modo [n+B].
                    v_ctrl.EA_A_Sel := EA_A_SRC_TMP;
                    v_ctrl.EA_B_Sel := EA_B_SRC_REG_B;
                    v_ctrl.ABUS_Sel := ABUS_SRC_EA_RES;
                    if r_exec_IR(4) = '1' then v_ctrl.Out_Sel := OUT_SEL_A;
                    else                        v_ctrl.Out_Sel := OUT_SEL_B; end if;
                    v_ctrl.Mem_WE   := '1';
                    if r_exec_IR = x"34" then v_ctrl.Force_ZP := '1'; end if;
                    v_needs_mem := true;

                when ESS_PUSH_1 =>
                    -- Ciclo 1/3: decrementa SP. El dato se escribirá en los ciclos 2 y 3.
                    v_ctrl.SP_Op := SP_OP_DEC;

                when ESS_PUSH_2 =>
                    -- Ciclo 2/3: escribe el byte bajo (A, B o F) en mem[SP].
                    v_ctrl.ABUS_Sel  := ABUS_SRC_SP;
                    v_ctrl.Mem_WE    := '1';
                    v_ctrl.SP_Offset := '0';
                    case r_exec_IR is
                        when x"62"  => v_ctrl.Out_Sel := OUT_SEL_F;
                        when x"61"  => v_ctrl.Out_Sel := OUT_SEL_B;
                        when x"63"  => v_ctrl.Out_Sel := OUT_SEL_B;
                        when others => v_ctrl.Out_Sel := OUT_SEL_A;
                    end case;
                    v_needs_mem := true;

                when ESS_PUSH_3 =>
                    -- Ciclo 3/3: escribe el byte alto en mem[SP+1].
                    -- Para PUSH A:B escribe A; para PUSH A/B/F escribe 0x00 (relleno).
                    v_ctrl.ABUS_Sel  := ABUS_SRC_SP;
                    v_ctrl.SP_Offset := '1';
                    v_ctrl.Mem_WE    := '1';
                    if r_exec_IR = x"63" then v_ctrl.Out_Sel := OUT_SEL_A;
                    else                       v_ctrl.Out_Sel := OUT_SEL_ZERO; end if;
                    v_needs_mem := true;

                when ESS_POP_1 =>
                    -- Ciclo 1: lee mem[SP] → MDR. El dato será A, B, F o byte bajo de A:B.
                    v_ctrl.ABUS_Sel  := ABUS_SRC_SP;
                    v_ctrl.Mem_RE    := '1';
                    v_ctrl.MDR_WE    := '1';
                    v_ctrl.SP_Offset := '0';
                    v_needs_mem := true;

                when ESS_POP_2 =>
                    -- Ciclo 2 (POP A o POP B): MDR → registro; SP++.
                    v_ctrl.Bus_Op := MEM_MDR_elected;
                    v_ctrl.SP_Op  := SP_OP_INC;
                    if r_exec_IR = x"65" then
                        v_ctrl.Write_B := '1';
                        v_ctrl.Reg_Sel := std_logic_vector(to_unsigned(1, REG_SEL_WIDTH));
                    else
                        v_ctrl.Write_A := '1';
                    end if;

                when ESS_POP_F_2 =>
                    -- Ciclo 2 (POP F): restaura el registro de flags desde MDR; SP++.
                    -- Usa Load_F_Direct para evitar el enmascaramiento normal de flags.
                    v_ctrl.Bus_Op        := MEM_MDR_elected;
                    v_ctrl.Load_F_Direct := '1';
                    v_ctrl.SP_Op         := SP_OP_INC;

                when ESS_POP_AB_2 =>
                    -- Ciclo 2 (POP A:B): MDR → B; lee mem[SP+1] → MDR (para A).
                    -- Lee y escribe en el mismo ciclo para solapar las dos lecturas del stack.
                    v_ctrl.Bus_Op    := MEM_MDR_elected;
                    v_ctrl.Write_B   := '1';
                    v_ctrl.Reg_Sel   := std_logic_vector(to_unsigned(1, REG_SEL_WIDTH));
                    v_ctrl.ABUS_Sel  := ABUS_SRC_SP;
                    v_ctrl.SP_Offset := '1';
                    v_ctrl.Mem_RE    := '1';
                    v_ctrl.MDR_WE    := '1';
                    v_needs_mem := true;

                when ESS_POP_AB_3 =>
                    -- Ciclo 3 (POP A:B): MDR → A; SP++ (incremento total = +2).
                    v_ctrl.Bus_Op  := MEM_MDR_elected;
                    v_ctrl.Write_A := '1';
                    v_ctrl.SP_Op   := SP_OP_INC;

                when ESS_CALL_1 =>
                    -- Ciclo 1/6: lee el byte bajo de la dirección destino [PC] → TMP_L; PC++.
                    v_ctrl.ABUS_Sel   := ABUS_SRC_PC;
                    v_ctrl.Mem_RE     := '1';
                    v_ctrl.Load_TMP_L := '1';
                    v_ctrl.PC_Op      := PC_OP_INC;
                    v_needs_mem := true;

                when ESS_CALL_2 =>
                    -- Ciclo 2/6: lee el byte alto de la dirección destino [PC] → TMP_H; PC++.
                    v_ctrl.ABUS_Sel   := ABUS_SRC_PC;
                    v_ctrl.Mem_RE     := '1';
                    v_ctrl.Load_TMP_H := '1';
                    v_ctrl.PC_Op      := PC_OP_INC;
                    v_needs_mem := true;

                when ESS_CALL_3 =>
                    -- Ciclo 3/6: decrementa SP. La dirección de retorno (PC actual) se
                    -- empujará en los dos ciclos siguientes (byte bajo primero).
                    v_ctrl.SP_Op := SP_OP_DEC;

                when ESS_CALL_4 =>
                    -- Ciclo 4/6: guarda PCL (byte bajo del PC de retorno) en mem[SP].
                    v_ctrl.ABUS_Sel  := ABUS_SRC_SP;
                    v_ctrl.Mem_WE    := '1';
                    v_ctrl.Out_Sel   := OUT_SEL_PCL;
                    v_ctrl.SP_Offset := '0';
                    v_needs_mem := true;

                when ESS_CALL_5 =>
                    -- Ciclo 5/6: guarda PCH (byte alto del PC de retorno) en mem[SP+1].
                    -- Para CALL ind (0x76) el siguiente paso derreferencia la dirección.
                    v_ctrl.ABUS_Sel  := ABUS_SRC_SP;
                    v_ctrl.Mem_WE    := '1';
                    v_ctrl.Out_Sel   := OUT_SEL_PCH;
                    v_ctrl.SP_Offset := '1';
                    v_needs_mem := true;

                when ESS_CALL_6 =>
                    -- Ciclo 6/6: carga PC desde TMP (salto al inicio de la rutina).
                    v_ctrl.Load_Src_Sel := '1'; -- TMP
                    v_ctrl.PC_Op        := PC_OP_LOAD;

                when ESS_RET_1 =>
                    -- Ciclo 1/3: lee el byte bajo de la dirección de retorno desde mem[SP] → TMP_L.
                    v_ctrl.ABUS_Sel   := ABUS_SRC_SP;
                    v_ctrl.SP_Offset  := '0';
                    v_ctrl.Mem_RE     := '1';
                    v_ctrl.Load_TMP_L := '1';
                    v_needs_mem := true;

                when ESS_RET_2 =>
                    -- Ciclo 2/3: lee el byte alto de la dirección de retorno desde mem[SP+1] → TMP_H.
                    v_ctrl.ABUS_Sel   := ABUS_SRC_SP;
                    v_ctrl.SP_Offset  := '1';
                    v_ctrl.Mem_RE     := '1';
                    v_ctrl.Load_TMP_H := '1';
                    v_needs_mem := true;

                when ESS_RET_3 =>
                    -- Ciclo 3/3: PC ← TMP (retorno); SP += 2 (libera los 2 bytes del stack).
                    v_ctrl.Load_Src_Sel := '1'; -- TMP
                    v_ctrl.PC_Op        := PC_OP_LOAD;
                    v_ctrl.SP_Op        := SP_OP_INC;

                when ESS_RTI_1 =>
                    -- Ciclo 1/4: lee los flags guardados desde mem[SP] → MDR.
                    v_ctrl.ABUS_Sel  := ABUS_SRC_SP;
                    v_ctrl.SP_Offset := '0';
                    v_ctrl.Mem_RE    := '1';
                    v_ctrl.MDR_WE    := '1';
                    v_needs_mem := true;

                when ESS_RTI_2 =>
                    -- Ciclo 2/4: restaura registro de flags (MDR → F directo, sin máscara); SP++.
                    v_ctrl.Bus_Op        := MEM_MDR_elected;
                    v_ctrl.Load_F_Direct := '1';
                    v_ctrl.SP_Op         := SP_OP_INC;

                when ESS_RTI_3 =>
                    -- Ciclo 3/4: lee el byte bajo de la dirección de retorno desde mem[SP] → TMP_L.
                    v_ctrl.ABUS_Sel   := ABUS_SRC_SP;
                    v_ctrl.SP_Offset  := '0';
                    v_ctrl.Mem_RE     := '1';
                    v_ctrl.Load_TMP_L := '1';
                    v_needs_mem := true;

                when ESS_RTI_4 =>
                    -- Ciclo 4/4: lee el byte alto de la dirección de retorno desde mem[SP+1] → TMP_H.
                    v_ctrl.ABUS_Sel   := ABUS_SRC_SP;
                    v_ctrl.SP_Offset  := '1';
                    v_ctrl.Mem_RE     := '1';
                    v_ctrl.Load_TMP_H := '1';
                    v_needs_mem := true;

                when ESS_INT_1 =>
                    -- Ciclo 1/9 (atención a interrupción): SP-- para empujar PCL.
                    v_ctrl.SP_Op := SP_OP_DEC;

                when ESS_INT_2 =>
                    -- Ciclo 2/9: guarda PCL (byte bajo del PC interrumpido) en mem[SP].
                    v_ctrl.ABUS_Sel  := ABUS_SRC_SP;
                    v_ctrl.Mem_WE    := '1';
                    v_ctrl.Out_Sel   := OUT_SEL_PCL;
                    v_ctrl.SP_Offset := '0';
                    v_needs_mem := true;

                when ESS_INT_3 =>
                    -- Ciclo 3/9: guarda PCH (byte alto del PC interrumpido) en mem[SP+1].
                    v_ctrl.ABUS_Sel  := ABUS_SRC_SP;
                    v_ctrl.SP_Offset := '1';
                    v_ctrl.Mem_WE    := '1';
                    v_ctrl.Out_Sel   := OUT_SEL_PCH;
                    v_needs_mem := true;

                when ESS_INT_4 =>
                    -- Ciclo 4/9: SP-- para hacer sitio a los flags.
                    v_ctrl.SP_Op := SP_OP_DEC;

                when ESS_INT_5 =>
                    -- Ciclo 5/9: guarda los flags actuales en mem[SP].
                    v_ctrl.ABUS_Sel  := ABUS_SRC_SP;
                    v_ctrl.Mem_WE    := '1';
                    v_ctrl.Out_Sel   := OUT_SEL_F;
                    v_ctrl.SP_Offset := '0';
                    v_needs_mem := true;

                when ESS_INT_6 =>
                    -- Ciclo 6/9: escribe 0x00 en mem[SP+1] (trama de 2 bytes por elemento).
                    v_ctrl.ABUS_Sel  := ABUS_SRC_SP;
                    v_ctrl.Mem_WE    := '1';
                    v_ctrl.Out_Sel   := OUT_SEL_ZERO;
                    v_ctrl.SP_Offset := '1';
                    v_needs_mem := true;

                when ESS_INT_7 =>
                    -- Ciclo 7/9: lee el byte bajo del vector de interrupción → TMP_L.
                    -- Usa ABUS_SRC_VEC_NMI_L o VEC_IRQ_L según el tipo de interrupción.
                    if handling_nmi = '1' then v_ctrl.ABUS_Sel := ABUS_SRC_VEC_NMI_L;
                    else                        v_ctrl.ABUS_Sel := ABUS_SRC_VEC_IRQ_L; end if;
                    v_ctrl.Mem_RE     := '1';
                    v_ctrl.Load_TMP_L := '1';
                    v_needs_mem := true;

                when ESS_INT_8 =>
                    -- Ciclo 8/9: lee el byte alto del vector de interrupción → TMP_H.
                    if handling_nmi = '1' then v_ctrl.ABUS_Sel := ABUS_SRC_VEC_NMI_H;
                    else                        v_ctrl.ABUS_Sel := ABUS_SRC_VEC_IRQ_H; end if;
                    v_ctrl.Mem_RE     := '1';
                    v_ctrl.Load_TMP_H := '1';
                    v_needs_mem := true;

                when ESS_INT_9 =>
                    -- Ciclo 9/9: PC ← TMP (salta al handler); seq_proc limpia I_Flag y handling_nmi.
                    v_ctrl.Load_Src_Sel := '1'; -- TMP
                    v_ctrl.PC_Op        := PC_OP_LOAD;

                when ESS_BRANCH_2 =>
                    -- Ciclo final de rama relativa tomada: PC ← PC + offset con signo.
                    -- EA = PC + DataIn (offset de 8 bits en complemento a 2).
                    v_ctrl.EA_A_Sel     := EA_A_SRC_PC;
                    v_ctrl.EA_B_Sel     := EA_B_SRC_DATA_IN;
                    v_ctrl.Load_Src_Sel := LOAD_SRC_ALU_RES;
                    v_ctrl.PC_Op        := PC_OP_LOAD;

                when ESS_JP_3 =>
                    -- Ciclo final de salto absoluto: PC ← TMP (16 bits ya en TMP).
                    -- Compartido por JP nn, CALL, RET, RTI e INT.
                    v_ctrl.Load_Src_Sel := '1'; -- TMP
                    v_ctrl.PC_Op        := PC_OP_LOAD;
                    -- RET y RTI: también restauran SP (manejado en RET_3, no aquí)

                when ESS_JP_AB =>
                    -- Ciclo único: PC ← A:B. Calcula EA = A:B + 0 y carga PC.
                    v_ctrl.EA_A_Sel     := EA_A_SRC_REG_AB;
                    v_ctrl.EA_B_Sel     := EA_B_SRC_ZERO;
                    v_ctrl.Load_Src_Sel := LOAD_SRC_ALU_RES;
                    v_ctrl.PC_Op        := PC_OP_LOAD;

                when ESS_JPN_2 =>
                    -- Ciclo único: carga solo el byte bajo del PC desde TMP_L (salto pág. cero).
                    -- PC_H permanece sin cambio; efecto = salto dentro de la misma página.
                    v_ctrl.Load_Src_Sel := '1'; -- TMP
                    v_ctrl.PC_Op        := PC_OP_LOAD_L;

                when ESS_IND_LOAD =>
                    -- Ciclo 1/3 de salto indirecto: PC ← TMP (apunta al puntero en memoria).
                    -- Los dos ciclos siguientes leen los 2 bytes del puntero destino.
                    v_ctrl.Load_Src_Sel := '1'; -- TMP
                    v_ctrl.PC_Op        := PC_OP_LOAD;

                when ESS_IND_READ_L =>
                    -- Ciclo 2/3: lee el byte bajo del destino indirecto [PC] → TMP_L; PC++.
                    v_ctrl.ABUS_Sel   := ABUS_SRC_PC;
                    v_ctrl.Mem_RE     := '1';
                    v_ctrl.Load_TMP_L := '1';
                    v_ctrl.PC_Op      := PC_OP_INC;
                    v_needs_mem := true;

                when ESS_IND_READ_H =>
                    -- Ciclo 3/3: lee el byte alto del destino indirecto [PC] → TMP_H; PC++.
                    v_ctrl.ABUS_Sel   := ABUS_SRC_PC;
                    v_ctrl.Mem_RE     := '1';
                    v_ctrl.Load_TMP_H := '1';
                    v_ctrl.PC_Op      := PC_OP_INC;
                    v_needs_mem := true;

                when ESS_OP16_IMM8 =>
                    -- Ciclo único para ADD16/SUB16 #n (inmediato de 8 bits):
                    -- lee #n desde [PC]; calcula A:B +/- #n; escribe A (byte alto).
                    -- ESS_OP16_WB2 (siguiente ciclo) completará el byte bajo en B.
                    v_ctrl.ABUS_Sel  := ABUS_SRC_PC;
                    v_ctrl.Mem_RE    := '1';
                    v_ctrl.PC_Op     := PC_OP_INC;
                    v_ctrl.EA_A_Sel  := EA_A_SRC_REG_AB;
                    v_ctrl.EA_B_Sel  := EA_B_SRC_DATA_IN;
                    if r_exec_IR = x"E0" then v_ctrl.EA_Op := EA_OP_ADD;
                    else                       v_ctrl.EA_Op := EA_OP_SUB; end if;
                    v_ctrl.Bus_Op    := EA_HIGH_elected;
                    v_ctrl.Write_A   := '1';
                    v_ctrl.F_Src_Sel := '1';
                    v_ctrl.Write_F   := '1';
                    v_ctrl.Flag_Mask := x"F0";
                    v_needs_mem := true;

                when ESS_OP16_FETCH1 =>
                    -- Ciclo 1/3 para ADD16/SUB16 nn (operando de 16 bits en memoria):
                    -- Lee el byte alto del operando [PC] → TMP_H; PC++.
                    -- (El byte bajo op1 ya fue guardado durante DSS; se usa en WB1 vía TMP.)
                    v_ctrl.ABUS_Sel   := ABUS_SRC_PC;
                    v_ctrl.Mem_RE     := '1';
                    v_ctrl.Load_TMP_H := '1';
                    v_ctrl.PC_Op      := PC_OP_INC;
                    v_needs_mem := true;

                when ESS_OP16_WB1 =>
                    -- Ciclo 2/3 (o 2/2 para IMM8): calcula A:B +/- TMP; escribe byte alto → A.
                    -- Para E0/E2 (#n): TMP = {0x00, op1}. Para E1/E3 (#nn): TMP = {op2, op1}.
                    v_ctrl.EA_A_Sel  := EA_A_SRC_REG_AB;
                    v_ctrl.EA_B_Sel  := EA_B_SRC_TMP;
                    if r_exec_IR = x"E0" or r_exec_IR = x"E1" then
                        v_ctrl.EA_Op := EA_OP_ADD;
                    else
                        v_ctrl.EA_Op := EA_OP_SUB;
                    end if;
                    v_ctrl.Bus_Op    := EA_HIGH_elected;
                    v_ctrl.Write_A   := '1';
                    v_ctrl.F_Src_Sel := '1';
                    v_ctrl.Write_F   := '1';
                    v_ctrl.Flag_Mask := x"F0";

                when ESS_OP16_WB2 =>
                    -- Ciclo 3/3: escribe el byte bajo del resultado → B.
                    -- TMP siempre contiene el operando completo (cargado en WB1 o TMP_FROM_OP*).
                    -- Para E0/E2 (#n): TMP = {0x00, op1}. Para E1/E3 (#nn): TMP = {op2, op1}.
                    v_ctrl.EA_A_Sel := EA_A_SRC_REG_AB;
                    v_ctrl.EA_B_Sel := EA_B_SRC_TMP;
                    if r_exec_IR = x"E0" or r_exec_IR = x"E1" then
                        v_ctrl.EA_Op := EA_OP_ADD;
                    else
                        v_ctrl.EA_Op := EA_OP_SUB;
                    end if;
                    v_ctrl.Bus_Op  := EA_LOW_elected;
                    v_ctrl.Write_B := '1';
                    v_ctrl.Reg_Sel := std_logic_vector(to_unsigned(1, REG_SEL_WIDTH));

                when ESS_LDSP_1 =>
                    -- Ciclo 1/2 (LD SP,nn): lee el byte alto de la dirección nn → TMP_H; PC++.
                    -- op1 (byte bajo) ya fue cargado en r_exec_op1 durante DSS.
                    v_ctrl.ABUS_Sel   := ABUS_SRC_PC;
                    v_ctrl.Mem_RE     := '1';
                    v_ctrl.Load_TMP_H := '1';
                    v_ctrl.PC_Op      := PC_OP_INC;
                    v_needs_mem := true;

                when ESS_LDSP_2 =>
                    -- Llega aquí desde:
                    --   LD SP,#nn (0x50): TMP_FROM_OP1→TMP_FROM_OP2→LDSP_2 → SP ← TMP
                    --   LD SP,A:B (0x51): LDSP_AB→LDSP_2 → SP ← A:B (calcula EA)
                    if r_exec_IR = x"50" then
                        -- Ciclo 2/2 (LD SP,nn): SP ← TMP (valor completo en TMP).
                        v_ctrl.Load_Src_Sel := '1'; -- TMP
                    else
                        -- Ciclo único (LD SP,A:B): SP ← A:B usando el sumador EA.
                        v_ctrl.EA_A_Sel     := EA_A_SRC_REG_AB;
                        v_ctrl.EA_B_Sel     := EA_B_SRC_ZERO;
                        v_ctrl.EA_Op        := EA_OP_ADD;
                        v_ctrl.Load_Src_Sel := LOAD_SRC_ALU_RES;
                    end if;
                    v_ctrl.SP_Op := SP_OP_LOAD;

                when ESS_STSP_WB =>
                    -- Ciclo único (ST SP_L,A / ST SP_H,A): calcula EA = SP + 0;
                    -- selecciona el byte bajo (EA_LOW) o alto (EA_HIGH) del SP → A.
                    v_ctrl.EA_A_Sel := EA_A_SRC_SP;
                    v_ctrl.EA_B_Sel := EA_B_SRC_ZERO;
                    v_ctrl.EA_Op    := EA_OP_ADD;
                    if r_exec_IR = x"52" then v_ctrl.Bus_Op := EA_LOW_elected;
                    else                       v_ctrl.Bus_Op := EA_HIGH_elected; end if;
                    v_ctrl.Write_A  := '1';

                when ESS_IO_FETCH =>
                    -- Ciclo 1 (IN/OUT con operando inmediato #n): lee la dirección de puerto
                    -- desde [PC] → TMP_L; limpia TMP_H (dirección = 0x00nn); PC++.
                    v_ctrl.ABUS_Sel   := ABUS_SRC_PC;
                    v_ctrl.Mem_RE     := '1';
                    v_ctrl.Load_TMP_L := '1';
                    v_ctrl.Clear_TMP  := '1';
                    v_ctrl.PC_Op      := PC_OP_INC;
                    v_needs_mem := true;

                when ESS_IO_SETUP =>
                    -- Ciclo 1 (IN/OUT indexado por B): limpia TMP (base = 0).
                    -- El ciclo siguiente usará EA = 0 + B = dirección de puerto.
                    v_ctrl.Clear_TMP := '1';

                when ESS_IN_READ =>
                    -- Ciclo de lectura de puerto: IO_RE sobre la dirección EA; resultado → MDR.
                    -- Para IN A,[B]: EA = TMP + B. Para IN A,#n: EA = TMP + 0.
                    v_ctrl.EA_A_Sel := EA_A_SRC_TMP;
                    if r_exec_IR = x"D1" then v_ctrl.EA_B_Sel := EA_B_SRC_REG_B;
                    else                       v_ctrl.EA_B_Sel := EA_B_SRC_ZERO; end if;
                    v_ctrl.ABUS_Sel := ABUS_SRC_EA_RES;
                    v_ctrl.IO_RE    := '1';
                    v_ctrl.MDR_WE   := '1';

                when ESS_IN_WB =>
                    -- Ciclo write-back de IN: MDR → A; actualiza flag Z.
                    v_ctrl.Bus_Op   := MEM_MDR_elected;
                    v_ctrl.Write_A  := '1';
                    v_ctrl.Write_F  := '1';
                    v_ctrl.Flag_Mask(idx_fZ) := '1';

                when ESS_OUT_WRITE =>
                    -- Ciclo de escritura de puerto: IO_WE sobre la dirección EA; dato = A.
                    -- Para OUT [B],A: EA = TMP + B. Para OUT #n,A: EA = TMP + 0.
                    v_ctrl.EA_A_Sel := EA_A_SRC_TMP;
                    if r_exec_IR = x"D3" then v_ctrl.EA_B_Sel := EA_B_SRC_REG_B;
                    else                       v_ctrl.EA_B_Sel := EA_B_SRC_ZERO; end if;
                    v_ctrl.ABUS_Sel := ABUS_SRC_EA_RES;
                    v_ctrl.Out_Sel  := OUT_SEL_A;
                    v_ctrl.IO_WE    := '1';

                when ESS_SKIP_BYTE =>
                    -- Ciclo extra para rama relativa NO tomada: incrementa PC para
                    -- saltar el byte de offset y reanudar el fetch normal.
                    v_ctrl.PC_Op := PC_OP_INC;

                when ESS_HALT =>
                    -- Estado permanente: el procesador está detenido (HALT).
                    -- Solo una interrupción puede sacarlo de este estado.
                    null; -- processor stopped

                when ESS_TMP_FROM_OP1 =>
                    -- Pipeline operand load cycle 1: load TMP[7:0] from r_exec_op1.
                    -- For zero-page 2-byte instructions: also clear TMP[15:8] to 0x00
                    -- (force_zp equivalent).  Op_Sel='1' routes Op_Data to AddressPath
                    -- DataIn instead of MemData_In.  No memory access needed.
                    v_ctrl.Op_Data    := r_exec_op1;
                    v_ctrl.Op_Sel     := '1';
                    v_ctrl.Load_TMP_L := '1';
                    -- For zero-page modes, I/O immediate, and ADD16/SUB16 #n: clear TMP_H to 0x00.
                    case r_exec_IR is
                        when x"12"|x"22"|x"16"|x"30"|x"40"|x"32"|x"34"|x"D0"|x"D2"|x"E0"|x"E2"
                            => v_ctrl.Clear_TMP := '1';
                        when others => null;
                    end case;

                when ESS_TMP_FROM_OP2 =>
                    -- Pipeline operand load cycle 2: load TMP[15:8] from r_exec_op2.
                    -- After this cycle TMP contains the full 16-bit address/value.
                    -- Op_Sel='1' routes Op_Data to AddressPath DataIn.
                    -- No memory access; seq_proc will dispatch to the execution state.
                    v_ctrl.Op_Data    := r_exec_op2;
                    v_ctrl.Op_Sel     := '1';
                    v_ctrl.Load_TMP_H := '1';

                when ESS_IDLE =>
                    null;

                when others =>
                    null;
            end case;

        -- =====================================================================
        -- Priority 2: Single-cycle EX (r_ID_EX.is_single='1')
        -- =====================================================================
        elsif r_ID_EX.valid = '1' and r_ID_EX.is_single = '1' then
            v_ctrl := r_ID_EX.ctrl;
            if v_ctrl.Mem_RE = '1' or v_ctrl.Mem_WE = '1' then
                v_needs_mem := true;
            end if;
            -- Overlap fetch if bus is free
            if not v_needs_mem and r_IF_ID.valid = '0' then
                v_fetch_ok := true;
            end if;

        -- =====================================================================
        -- Priority 3: Operand fetch during DECODE (DSS_OP1 / DSS_OP2)
        -- =====================================================================
        elsif dss = DSS_OP1 or dss = DSS_OP2 then
            v_ctrl.ABUS_Sel := ABUS_SRC_PC;
            v_ctrl.Mem_RE   := '1';
            v_ctrl.PC_Op    := PC_OP_INC;
            -- Latch MDR during OP1 fetch for instructions whose single-cycle EX
            -- reads MDR (LD A,#n / LD B,#n / ALU imm).  This must happen here,
            -- during the memory-read cycle, so that MDR contains the correct
            -- operand byte BEFORE the overlap fetch potentially changes MemDataIn
            -- in the execution cycle.
            if dss = DSS_OP1 then
                case r_IF_ID.opcode is
                    when x"11"|x"21"|
                         x"A0"|x"A1"|x"A2"|x"A3"|x"A4"|x"A5"|x"A6"|x"A7" =>
                        v_ctrl.MDR_WE := '1';
                    when others => null;
                end case;
            end if;
            v_needs_mem := true;

        -- =====================================================================
        -- Priority 4: Idle - fetch only
        -- =====================================================================
        else
            -- Do NOT generate a fetch when a multi-cycle instruction (is_multi='1')
            -- is sitting in r_ID_EX awaiting ESS dispatch.  The seq_proc fetch
            -- condition requires (r_ID_EX.valid='0' or is_single='1'), so the
            -- instruction on the bus would not be captured into r_IF_ID while the
            -- PC would still be incremented — causing the next instruction to be
            -- permanently skipped.
            if r_IF_ID.valid = '0' and
               not (r_ID_EX.valid = '1' and r_ID_EX.is_multi = '1') then
                v_fetch_ok := true;
            end if;
        end if;

        -- =====================================================================
        -- Overlay FETCH when possible (pipeline overlap)
        -- =====================================================================
        if v_fetch_ok then
            v_ctrl.ABUS_Sel := ABUS_SRC_PC;
            v_ctrl.Mem_RE   := '1';
            v_ctrl.PC_Op    := PC_OP_INC;
        end if;

        CtrlBus <= v_ctrl;

    end process comb_proc;

end architecture pipeline;
