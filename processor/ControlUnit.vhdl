library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use work.CONSTANTS_pkg.ALL;
use work.ALU_pkg.ALL;
use work.DataPath_pkg.ALL;
use work.AddressPath_pkg.ALL;
use work.ControlUnit_pkg.ALL;

entity ControlUnit is
    Port (
        clk      : in  std_logic;
        reset    : in  std_logic;
        
        -- Inputs from DataPath/AddressPath
        FlagsIn  : in  status_vector;
        InstrIn  : in  data_vector; -- Instruction byte from memory
        Mem_Ready: in  std_logic;   -- Wait state input (active high)
        IRQ      : in  std_logic;   -- Interrupt Request
        NMI      : in  std_logic;   -- Non-Maskable Interrupt
        
        -- Output to the rest of the processor
        CtrlBus  : out control_bus_t
    );
end entity ControlUnit;

architecture unique of ControlUnit is

    -- Estados de la FSM principal
    type state_type is (
        S_RESET,
        S_FETCH,        -- Leer opcode de memoria
        S_DECODE,       -- Decodificar opcode y preparar siguiente paso
        
        -- Estados de Ejecución
        S_EXEC_HALT,    -- Detener procesador
        
        S_EXEC_FLAGS,   -- Manipulación de flags (SEC, CLC)
        
        S_EXEC_LDI_1,   -- LD A, #n: Leer inmediato
        S_EXEC_LDI_2,   -- LD A, #n: Escribir en A
        
        S_EXEC_MOV_AB,  -- LD A, B: Transferencia registro
        
        S_EXEC_MOV_BA,  -- LD B, A: Transferencia registro (0x20)
        S_EXEC_LDI_B_1, -- LD B, #n: Leer inmediato (0x21)
        S_EXEC_LDI_B_2, -- LD B, #n: Escribir en B
        
        S_EXEC_ALU_R,   -- ALU A, B (ADD, SUB, AND, OR...)
        
        S_EXEC_ALU_IMM_1, -- ALU A, #n: Fetch inmediato
        S_EXEC_ALU_IMM_2, -- ALU A, #n: Execute & Write Back
        
        S_EXEC_ALU_UNARY, -- Operaciones unarias ALU (Shift, Rotate, etc.)
        
        S_EXEC_PUSH_1,    -- PUSH: Decrementar SP
        S_EXEC_PUSH_2,    -- PUSH: Escribir byte bajo
        S_EXEC_PUSH_3,    -- PUSH: Escribir byte alto (0x00)
        
        S_EXEC_PUSH_F_2,  -- PUSH F: Escribir F
        
        S_EXEC_POP_1,     -- POP: Leer byte bajo
        S_EXEC_POP_2,     -- POP: Guardar en Reg y Incrementar SP
        
        S_EXEC_POP_F_2,   -- POP F: Guardar en F
        
        S_EXEC_POP_AB_2,  -- POP A:B: Guardar B y Leer byte alto
        S_EXEC_POP_AB_3,  -- POP A:B: Guardar A y restaurar SP
        
        S_EXEC_CALL_1,    -- CALL: Leer destino LOW
        S_EXEC_CALL_2,    -- CALL: Leer destino HIGH
        S_EXEC_CALL_3,    -- CALL: Decrementar SP
        S_EXEC_CALL_4,    -- CALL: Push PC LOW
        S_EXEC_CALL_5,    -- CALL: Push PC HIGH
        S_EXEC_CALL_6,    -- CALL: Cargar PC destino

        S_EXEC_RET_1,     -- RET: Leer PC LOW desde Stack
        S_EXEC_RET_2,     -- RET: Leer PC HIGH desde Stack
        S_EXEC_RET_3,     -- RET: Cargar PC y restaurar SP

        S_EXEC_RTI_1,     -- RTI: Pop F (read)
        S_EXEC_RTI_2,     -- RTI: Pop F (write) + Pop PC L (read)
        S_EXEC_RTI_3,     -- RTI: Pop PC L (store) + Pop PC H (read)
        S_EXEC_RTI_4,     -- RTI: Pop PC H (store/load PC)

        S_INT_PUSH_PC_1,  -- INT Entry: Push PC (SP dec)
        S_INT_PUSH_PC_2,  -- INT Entry: Push PC Low
        S_INT_PUSH_PC_3,  -- INT Entry: Push PC High
        S_INT_PUSH_F_1,   -- INT Entry: Push F (SP dec)
        S_INT_PUSH_F_2,   -- INT Entry: Push F (Write F)
        S_INT_PUSH_F_3,   -- INT Entry: Push F (Write 00)
        S_INT_VEC_1,      -- INT Entry: Fetch Vector Low
        S_INT_VEC_2,      -- INT Entry: Fetch Vector High
        S_INT_VEC_3,      -- INT Entry: Load PC

        S_EXEC_ADDR_FETCH_HI, -- LD/ST [nn] o [nn+B]: Leer byte alto de la dirección base
        S_EXEC_PZ_FETCH,      -- LD/ST [n]: Cargar dirección de página cero en TMP
        S_EXEC_INDB_SETUP,    -- LD/ST [B]: Preparar TMP para cálculo de dirección
        S_EXEC_LD_ABS_READ,  -- LD A, [nn]: Leer dato de memoria
        S_EXEC_LD_IDX_READ,  -- LD A, [nn+B]: Calcular EA y leer dato
        S_EXEC_LD_WB,        -- LD A, [...]: Escribir dato en A (Write-Back)
        S_EXEC_ST_ABS_WRITE, -- ST A, [nn]: Escribir dato en memoria
        S_EXEC_ST_IDX_WRITE, -- ST A, [nn+B]: Calcular EA y escribir dato
        
        S_EXEC_IO_FETCH_PORT, -- IN/OUT #n: Leer número de puerto
        S_EXEC_IO_SETUP_REG,  -- IN/OUT [B]: Preparar direccionamiento indirecto
        S_EXEC_IN_READ,       -- IN: Leer del bus I/O
        S_EXEC_IN_WB,         -- IN: Escribir en A
        S_EXEC_OUT_WRITE,     -- OUT: Escribir en bus I/O
        
        S_EXEC_OP16_FETCH_1,  -- 16-bit Ops: Leer operando
        S_EXEC_OP16_IMM8_WB1, -- 16-bit Ops #n: Exec & Write-Back High
        S_EXEC_OP16_WB_1,     -- 16-bit Ops #nn: Write-Back High (A) + Flags
        S_EXEC_OP16_WB_2,     -- 16-bit Ops: Write-Back Low (B) Common
        
        S_EXEC_LDSP_1,        -- LD SP, #nn: Leer byte bajo
        S_EXEC_LDSP_2,        -- LD SP, #nn: Leer byte alto y cargar SP
        S_EXEC_LDSP_AB,       -- LD SP, A:B: Cargar SP desde registros
        S_EXEC_STSP_WB,       -- ST SP_L/H, A: Guardar parte del SP en A
        
        S_EXEC_BRANCH_REL_1, -- BEQ rel8: Fetch operando y cálculo de dirección
        S_EXEC_BRANCH_REL_2, -- BEQ rel8: Carga de PC si salto se toma
        S_SKIP_BYTE,         -- Estado para saltar un byte (operandos no usados)
        
        S_EXEC_JP_1,    -- JP nn: Leer byte bajo
        S_EXEC_JP_2,    -- JP nn: Leer byte alto
        S_EXEC_JP_3     -- JP nn: Cargar PC
    );

    signal state, next_state : state_type;
    
    -- Registro de Instrucción (Opcode)
    signal r_IR : data_vector;
    
    -- Registros internos de la UC
    signal I_Flag : std_logic := '0'; -- Interrupt Enable Flag (0=Disabled, 1=Enabled)
    signal handling_nmi : std_logic := '0'; -- Estado interno para distinguir NMI vs IRQ durante vector fetch

begin

    -- =========================================================================
    -- 1. Proceso Secuencial (Memoria de Estado)
    -- =========================================================================
    seq_proc: process(clk, reset)
    begin
        if reset = '1' then
            state <= S_RESET;
            r_IR  <= (others => '0');
            I_Flag <= '0'; -- Interrupciones deshabilitadas al inicio
        elsif rising_edge(clk) then
            state <= next_state;
            
            -- Latch del Instruction Register (IR)
            -- Capturamos el opcode al final del ciclo FETCH (transición a DECODE)
            if state = S_FETCH then
                r_IR <= InstrIn;
            end if;
        end if;
    end process;

    -- =========================================================================
    -- 2. Lógica Combinacional (Salida y Próximo Estado)
    -- =========================================================================
    comb_proc: process(state, r_IR, InstrIn, FlagsIn)
        variable v_ctrl : control_bus_t;
        variable v_branch_taken : boolean; -- Variable local para evaluar condiciones
    begin
        -- Valores por defecto (NOP seguro) para evitar latches inferidos
        v_ctrl := INIT_CTRL_BUS;
        v_branch_taken := false;
        next_state <= state; -- Por defecto mantenemos estado (o S_RESET si algo falla)

        case state is
            -- -----------------------------------------------------------------
            -- RESET & FETCH
            -- -----------------------------------------------------------------
            when S_RESET =>
                next_state <= S_FETCH;

            when S_FETCH =>
                -- Acceso a Memoria: Leer Opcode en [PC]
                v_ctrl.ABUS_Sel := ABUS_SRC_PC;
                v_ctrl.Mem_RE   := '1';
                
                -- Chequeo de Interrupciones (Prioridad: NMI > IRQ)
                -- Si hay espera de memoria (Mem_Ready=0), no cambiamos de estado,
                -- pero la decisión de ir a INT o DECODE se hace cuando se completa el fetch.
                if (NMI = '1') or (IRQ = '1' and I_Flag = '1') then
                    next_state <= S_INT_PUSH_PC_1; -- Ir a secuencia de interrupción
                else
                    next_state <= S_DECODE;
                end if;

            when S_DECODE =>
                -- En este punto, r_IR tiene el opcode actual.
                -- El PC todavía apunta al opcode. Debemos incrementarlo para
                -- apuntar al siguiente byte (operando o siguiente instrucción).
                v_ctrl.PC_Op := PC_OP_INC;

                -- Decodificación de instrucciones (Opcode Dispatch)
                case r_IR is
                    -- NOP (0x00)
                    when x"00" => 
                        next_state <= S_FETCH; -- Ya incrementamos PC, listo para siguiente
                    
                    -- HALT (0x01)
                    when x"01" => 
                        next_state <= S_EXEC_HALT;
                        
                    -- SEC (0x02) / CLC (0x03)
                    when x"02" | x"03" =>
                        next_state <= S_EXEC_FLAGS;
                        
                    -- SEI (0x04) / CLI (0x05)
                    when x"04" | x"05" =>
                        -- Lógica en proceso secuencial (I_Flag)
                        next_state <= S_FETCH;
                        
                    -- RTI (0x06)
                    when x"06" =>
                        next_state <= S_EXEC_RTI_1;

                    -- LD A, B (0x10)
                    when x"10" =>
                        next_state <= S_EXEC_MOV_AB;

                    -- LD A, #n (0x11)
                    when x"11" =>
                        next_state <= S_EXEC_LDI_1;

                    -- LD A, [n] (0x12)
                    when x"12" =>
                        v_ctrl.Load_TMP_L := '1';
                        next_state <= S_EXEC_ADDR_FETCH_HI;

                    -- LD A, [nn] (0x13)
                    when x"13" =>
                        v_ctrl.Load_TMP_L := '1';
                        next_state <= S_EXEC_ADDR_FETCH_HI;

                    -- LD A, [nn+B] (0x15)
                    when x"15" =>
                        v_ctrl.Load_TMP_L := '1';
                        next_state <= S_EXEC_ADDR_FETCH_HI;

                    -- LD A, [B] (0x14)
                    when x"14" =>
                        next_state <= S_EXEC_INDB_SETUP;

                    -- LD B, A (0x20) - NUEVO
                    when x"20" =>
                        next_state <= S_EXEC_MOV_BA;

                    -- LD B, #n (0x21) - NUEVO
                    when x"21" =>
                        next_state <= S_EXEC_LDI_B_1;

                    -- LD B, [n] (0x22), [nn] (0x23), [B] (0x24), [nn+B] (0x25)
                    when x"22" | x"23" | x"24" | x"25" =>
                        v_ctrl.Load_TMP_L := '1'; -- Carga el primer operando (n o nn_low)
                        next_state <= S_EXEC_ADDR_FETCH_HI;

                    -- ST A, [n] (0x30)
                    when x"30" =>
                        v_ctrl.Load_TMP_L := '1';
                        next_state <= S_EXEC_ADDR_FETCH_HI;

                    -- ST A, [nn] (0x31)
                    when x"31" =>
                        v_ctrl.Load_TMP_L := '1';
                        next_state <= S_EXEC_ADDR_FETCH_HI;

                    -- ST A, [nn+B] (0x33)
                    when x"33" =>
                        v_ctrl.Load_TMP_L := '1';
                        next_state <= S_EXEC_ADDR_FETCH_HI;

                    -- ST A, [B] (0x32)
                    when x"32" =>
                        next_state <= S_EXEC_INDB_SETUP;

                    -- ST B, [n] (0x40), [nn] (0x41), [nn+B] (0x42)
                    when x"40" | x"41" | x"42" =>
                        v_ctrl.Load_TMP_L := '1';
                        next_state <= S_EXEC_ADDR_FETCH_HI;

                    -- LD SP, #nn (0x50)
                    when x"50" =>
                        v_ctrl.Load_TMP_L := '1';
                        next_state <= S_EXEC_LDSP_1;

                    -- LD SP, A:B (0x51)
                    when x"51" =>
                        next_state <= S_EXEC_LDSP_AB;

                    -- ST SP_L, A (0x52) / ST SP_H, A (0x53)
                    when x"52" | x"53" =>
                        next_state <= S_EXEC_STSP_WB;

                    -- IN A, #n (0xD0) / OUT #n, A (0xD2)
                    when x"D0" | x"D2" =>
                        v_ctrl.Load_TMP_L := '1'; -- Cargar operando #n en TMP para usarlo como dirección
                        next_state <= S_EXEC_IO_FETCH_PORT;

                    -- IN A, [B] (0xD1) / OUT [B], A (0xD3)
                    when x"D1" | x"D3" =>
                        -- Direccionamiento indirecto [B]. B ya está en el registro.
                        next_state <= S_EXEC_IO_SETUP_REG;

                    -- ADD16 #n (0xE0), SUB16 #n (0xE2)
                    when x"E0" | x"E2" =>
                        -- El operando está en PC+1 (siguiente ciclo). Vamos a fetch/exec.
                        next_state <= S_EXEC_OP16_IMM8_WB1;

                    -- ADD16 #nn (0xE1), SUB16 #nn (0xE3)
                    when x"E1" | x"E3" =>
                        -- Fetch primer byte a TMP_L.
                        v_ctrl.Load_TMP_L := '1';
                        v_ctrl.Mem_RE     := '1'; -- Necesario activar lectura aquí para latchear en TMP
                        v_ctrl.ABUS_Sel   := ABUS_SRC_PC;
                        v_ctrl.PC_Op      := PC_OP_INC;
                        next_state <= S_EXEC_OP16_FETCH_1;

                    -- ALU Register Ops (A op B) -> A
                    -- ADD(90), ADC(91), SUB(92), SBB(93), AND(94), OR(95), XOR(96), CMP(97)
                    when x"90" | x"91" | x"92" | x"93" | x"94" | x"95" | x"96" | x"97" =>
                        next_state <= S_EXEC_ALU_R;

                    -- ALU Immediate Ops (A op #n) -> A
                    -- ADD#(A0), ADC#(A1), SUB#(A2), SBB#(A3), AND#(A4), OR#(A5), XOR#(A6), CMP#(A7)
                    when x"A0" | x"A1" | x"A2" | x"A3" | x"A4" | x"A5" | x"A6" | x"A7" =>
                        next_state <= S_EXEC_ALU_IMM_1;

                    -- Shift/Rotate Ops (A)
                    -- Unary ops: NOT,NEG,INC,DEC,Shifts,Rotates, CLR, SET, SWAP
                    when x"C0" | x"C1" | x"C2" | x"C3" | x"C4" | x"C5" | x"C6" | x"C7" | x"C8" | x"C9" | x"CA" | x"CB" | x"CC" | x"CD" | x"CE" =>
                        next_state <= S_EXEC_ALU_UNARY;

                    -- Saltos Condicionales (0x80 - 0x8B)
                    when x"80" | x"81" | x"82" | x"83" | x"84" | x"85" | 
                         x"86" | x"87" | x"88" | x"89" | x"8A" | x"8B" =>
                        
                        case r_IR is
                            when x"80" => if FlagsIn(idx_fZ) = '1' then v_branch_taken := true; end if; -- BEQ (Z=1)
                            when x"81" => if FlagsIn(idx_fZ) = '0' then v_branch_taken := true; end if; -- BNE (Z=0)
                            when x"82" => if FlagsIn(idx_fC) = '1' then v_branch_taken := true; end if; -- BCS (C=1)
                            when x"83" => if FlagsIn(idx_fC) = '0' then v_branch_taken := true; end if; -- BCC (C=0)
                            when x"84" => if FlagsIn(idx_fV) = '1' then v_branch_taken := true; end if; -- BVS (V=1)
                            when x"85" => if FlagsIn(idx_fV) = '0' then v_branch_taken := true; end if; -- BVC (V=0)
                            when x"86" => if FlagsIn(idx_fG) = '1' then v_branch_taken := true; end if; -- BGT (G=1)
                            when x"87" => if FlagsIn(idx_fG) = '0' then v_branch_taken := true; end if; -- BLE (G=0)
                            when x"88" => if (FlagsIn(idx_fG) = '1' or FlagsIn(idx_fE) = '1') then v_branch_taken := true; end if; -- BGE
                            when x"89" => if (FlagsIn(idx_fG) = '0' and FlagsIn(idx_fE) = '0') then v_branch_taken := true; end if; -- BLT
                            when x"8A" => if FlagsIn(idx_fH) = '1' then v_branch_taken := true; end if; -- BHC (H=1)
                            when x"8B" => if FlagsIn(idx_fE) = '1' then v_branch_taken := true; end if; -- BEQ2 (E=1)
                            when others => null;
                        end case;

                        if v_branch_taken then
                            next_state <= S_EXEC_BRANCH_REL_1;
                        else
                            next_state <= S_SKIP_BYTE;
                        end if;

                    -- PUSH A (0x60)
                    when x"60" =>
                        next_state <= S_EXEC_PUSH_1;

                    -- PUSH B (0x61)
                    when x"61" =>
                        next_state <= S_EXEC_PUSH_1;

                    -- PUSH F (0x62)
                    when x"62" =>
                        next_state <= S_EXEC_PUSH_1;

                    -- PUSH A:B (0x63)
                    when x"63" =>
                        next_state <= S_EXEC_PUSH_1;

                    -- POP A (0x64)
                    when x"64" =>
                        next_state <= S_EXEC_POP_1;

                    -- POP B (0x65)
                    when x"65" =>
                        next_state <= S_EXEC_POP_1;

                    -- POP F (0x66)
                    when x"66" =>
                        next_state <= S_EXEC_POP_1;

                    -- POP A:B (0x67)
                    when x"67" =>
                        next_state <= S_EXEC_POP_1;

                    -- CALL nn (0x75)
                    when x"75" =>
                        next_state <= S_EXEC_CALL_1;

                    -- RET (0x77)
                    when x"77" =>
                        next_state <= S_EXEC_RET_1;

                    -- JP nn (0x70)
                    when x"70" =>
                        next_state <= S_EXEC_JP_1;

                    when others =>
                        -- Opcode no implementado: tratar como NOP por ahora
                        next_state <= S_FETCH;
                end case;

            -- -----------------------------------------------------------------
            -- EJECUCIÓN: HALT
            -- -----------------------------------------------------------------
            when S_EXEC_HALT =>
                -- Bucle infinito, sin actividad de bus
                next_state <= S_EXEC_HALT;
                
            -- -----------------------------------------------------------------
            -- EJECUCIÓN: Control de Flags (SEC, CLC)
            -- -----------------------------------------------------------------
            when S_EXEC_FLAGS =>
                v_ctrl.Reg_Sel := (others => '0'); -- R0 (A)
                v_ctrl.Bus_Op  := ACC_ALU_elected; -- Necesario para enrutar ALU (aunque no escribamos A)
                v_ctrl.Write_F := '1';
                v_ctrl.Flag_Mask := x"80"; -- Solo actualizar C (bit 7)
                
                if r_IR = x"02" then -- SEC
                    v_ctrl.ALU_Op := OP_CMP; -- A - A = 0 (No borrow -> C=1)
                else -- CLC
                    v_ctrl.ALU_Op := OP_AND; -- A and A (Logic op -> C=0)
                end if;
                next_state <= S_FETCH;

            -- -----------------------------------------------------------------
            -- EJECUCIÓN: LD A, #n  (Opcode 0x11)
            -- -----------------------------------------------------------------
            when S_EXEC_LDI_1 =>
                -- Leer byte inmediato [PC] (PC ya fue incrementado en DECODE)
                v_ctrl.ABUS_Sel := ABUS_SRC_PC;
                v_ctrl.Mem_RE   := '1';
                v_ctrl.MDR_WE   := '1';      -- Capturar dato en MDR
                v_ctrl.PC_Op    := PC_OP_INC; -- Avanzar PC a siguiente instr
                next_state      <= S_EXEC_LDI_2;

            when S_EXEC_LDI_2 =>
                -- Escribir MDR en A
                v_ctrl.Bus_Op   := MEM_MDR_elected;
                v_ctrl.Write_A  := '1';
                v_ctrl.Write_F  := '1';      -- LD A afecta flags Z
                v_ctrl.Flag_Mask(idx_fZ) := '1';
                next_state      <= S_FETCH;

            -- -----------------------------------------------------------------
            -- EJECUCIÓN: LD A, B (Opcode 0x10)
            -- -----------------------------------------------------------------
            when S_EXEC_MOV_AB =>
                -- ALU Pass B -> A
                v_ctrl.ALU_Op   := OP_PSB;
                v_ctrl.Reg_Sel  := std_logic_vector(to_unsigned(1, REG_SEL_WIDTH)); -- R1 (B)
                v_ctrl.Bus_Op   := ACC_ALU_elected;
                v_ctrl.Write_A  := '1';
                v_ctrl.Write_F  := '1';
                v_ctrl.Flag_Mask(idx_fZ) := '1';
                next_state      <= S_FETCH;

            -- -----------------------------------------------------------------
            -- EJECUCIÓN: LD B, A (Opcode 0x20) - NUEVO
            -- -----------------------------------------------------------------
            when S_EXEC_MOV_BA =>
                -- ALU Pass A -> B
                -- A (R0) está fijo en entrada A. Hacemos PASS A y escribimos en B.
                v_ctrl.ALU_Op   := OP_PSA;
                v_ctrl.Reg_Sel  := std_logic_vector(to_unsigned(1, REG_SEL_WIDTH)); -- Select R1 (B) for Write_B
                v_ctrl.Bus_Op   := ACC_ALU_elected;
                v_ctrl.Write_B  := '1'; -- Escribir en Registro seleccionado (B)
                -- LD B, A no afecta flags según ISA
                next_state      <= S_FETCH;

            -- -----------------------------------------------------------------
            -- EJECUCIÓN: LD B, #n (Opcode 0x21) - NUEVO
            -- -----------------------------------------------------------------
            when S_EXEC_LDI_B_1 =>
                -- 1. Fetch inmediato a MDR
                v_ctrl.ABUS_Sel := ABUS_SRC_PC;
                v_ctrl.Mem_RE   := '1';
                v_ctrl.MDR_WE   := '1';
                v_ctrl.PC_Op    := PC_OP_INC;
                next_state      <= S_EXEC_LDI_B_2;

            when S_EXEC_LDI_B_2 =>
                -- 2. Escribir MDR en B
                v_ctrl.Bus_Op   := MEM_MDR_elected;
                v_ctrl.Reg_Sel  := std_logic_vector(to_unsigned(1, REG_SEL_WIDTH)); -- R1 (B)
                v_ctrl.Write_B  := '1';
                -- No flags
                next_state      <= S_FETCH;

            -- -----------------------------------------------------------------
            -- EJECUCIÓN: ALU Reg (A op B)
            -- -----------------------------------------------------------------
            when S_EXEC_ALU_R =>
                v_ctrl.Reg_Sel     := std_logic_vector(to_unsigned(1, REG_SEL_WIDTH)); -- Select B
                v_ctrl.ALU_Bin_Sel := '0'; -- Fuente B = Reg
                v_ctrl.Write_A     := '1'; -- Resultado -> A
                v_ctrl.Bus_Op      := ACC_ALU_elected;
                v_ctrl.Write_F     := '1'; -- Actualizar flags
                
                case r_IR is
                    when x"90" => v_ctrl.ALU_Op := OP_ADD; v_ctrl.Flag_Mask := x"FF";
                    when x"91" => v_ctrl.ALU_Op := OP_ADC; v_ctrl.Flag_Mask := x"FC"; -- C,H,V,Z,G,E
                    when x"92" => v_ctrl.ALU_Op := OP_SUB; v_ctrl.Flag_Mask := x"FF";
                    when x"93" => v_ctrl.ALU_Op := OP_SBB; v_ctrl.Flag_Mask := x"FC"; -- C,H,V,Z,G,E
                    when x"94" => v_ctrl.ALU_Op := OP_AND; v_ctrl.Flag_Mask := x"1C"; -- Z,G,E
                    when x"95" => v_ctrl.ALU_Op := OP_IOR; v_ctrl.Flag_Mask := x"1C";
                    when x"96" => v_ctrl.ALU_Op := OP_XOR; v_ctrl.Flag_Mask := x"1C";
                    when x"97" => v_ctrl.ALU_Op := OP_CMP; v_ctrl.Flag_Mask := x"FF"; v_ctrl.Write_A := '0'; -- CMP A, B (No escribe A)
                    when others => null;
                end case;
                next_state <= S_FETCH;

            -- -----------------------------------------------------------------
            -- EJECUCIÓN: ALU Inmediato (A op #n)
            -- -----------------------------------------------------------------
            when S_EXEC_ALU_IMM_1 =>
                v_ctrl.ABUS_Sel := ABUS_SRC_PC;
                v_ctrl.Mem_RE   := '1';
                v_ctrl.MDR_WE   := '1';
                v_ctrl.PC_Op    := PC_OP_INC;
                next_state      <= S_EXEC_ALU_IMM_2;

            when S_EXEC_ALU_IMM_2 =>
                v_ctrl.ALU_Bin_Sel := '1'; -- Fuente B = MDR (Inmediato)
                v_ctrl.Write_A     := '1';
                v_ctrl.Bus_Op      := ACC_ALU_elected;
                v_ctrl.Write_F     := '1';
                
                case r_IR is
                    when x"A0" => v_ctrl.ALU_Op := OP_ADD; v_ctrl.Flag_Mask := x"FF";
                    when x"A1" => v_ctrl.ALU_Op := OP_ADC; v_ctrl.Flag_Mask := x"FC";
                    when x"A2" => v_ctrl.ALU_Op := OP_SUB; v_ctrl.Flag_Mask := x"FF";
                    when x"A3" => v_ctrl.ALU_Op := OP_SBB; v_ctrl.Flag_Mask := x"FC";
                    when x"A4" => v_ctrl.ALU_Op := OP_AND; v_ctrl.Flag_Mask := x"1C";
                    when x"A5" => v_ctrl.ALU_Op := OP_IOR; v_ctrl.Flag_Mask := x"1C";
                    when x"A6" => v_ctrl.ALU_Op := OP_XOR; v_ctrl.Flag_Mask := x"1C";
                    when x"A7" => v_ctrl.ALU_Op := OP_CMP; v_ctrl.Flag_Mask := x"FF"; v_ctrl.Write_A := '0'; -- CMP #n (No escribe A)
                    when others => null;
                end case;
                next_state <= S_FETCH;

            -- -----------------------------------------------------------------
            -- EJECUCIÓN: ALU Unaria (Shift/Rotate A)
            -- -----------------------------------------------------------------
            when S_EXEC_ALU_UNARY =>
                -- Operaciones unarias (sobre A o B).
                -- Bus_Op=ACC_ALU, Write_F=1.
                v_ctrl.Bus_Op  := ACC_ALU_elected;
                v_ctrl.Write_F := '1';

                -- Escribir en B si es INC B o DEC B, sino en A
                if r_IR = x"C4" or r_IR = x"C5" then
                    v_ctrl.Write_B := '1';
                    v_ctrl.Reg_Sel := std_logic_vector(to_unsigned(1, REG_SEL_WIDTH)); -- R1 (B)
                else
                    v_ctrl.Write_A := '1';
                end if;
                
                case r_IR is
                    when x"C0" => v_ctrl.ALU_Op := OP_NOT; v_ctrl.Flag_Mask := x"10"; -- Z
                    when x"C1" => v_ctrl.ALU_Op := OP_NEG; v_ctrl.Flag_Mask := x"F0"; -- C,H,V,Z
                    when x"C2" => v_ctrl.ALU_Op := OP_INC; v_ctrl.Flag_Mask := x"F0"; -- C,H,V,Z
                    when x"C3" => v_ctrl.ALU_Op := OP_DEC; v_ctrl.Flag_Mask := x"F0"; -- C,H,V,Z
                    when x"C4" => v_ctrl.ALU_Op := OP_INB; v_ctrl.Flag_Mask := x"F0"; -- C,H,V,Z (INC B)
                    when x"C5" => v_ctrl.ALU_Op := OP_DEB; v_ctrl.Flag_Mask := x"F0"; -- C,H,V,Z (DEC B)
                    when x"C6" => v_ctrl.ALU_Op := OP_CLR; v_ctrl.Flag_Mask := x"10"; -- Z
                    when x"C7" => v_ctrl.ALU_Op := OP_SET; v_ctrl.Flag_Mask := x"10"; -- Z
                    when x"C8" => v_ctrl.ALU_Op := OP_LSL; v_ctrl.Flag_Mask := x"11"; -- Z, L
                    when x"C9" => v_ctrl.ALU_Op := OP_LSR; v_ctrl.Flag_Mask := x"12"; -- Z, R
                    when x"CA" => v_ctrl.ALU_Op := OP_ASL; v_ctrl.Flag_Mask := x"31"; -- Z, L, V
                    when x"CB" => v_ctrl.ALU_Op := OP_ASR; v_ctrl.Flag_Mask := x"12"; -- Z, R
                    when x"CC" => v_ctrl.ALU_Op := OP_ROL; v_ctrl.Flag_Mask := x"10"; -- Z
                    when x"CD" => v_ctrl.ALU_Op := OP_ROR; v_ctrl.Flag_Mask := x"10"; -- Z
                    when x"CE" => v_ctrl.ALU_Op := OP_SWP; v_ctrl.Flag_Mask := x"10"; -- Z
                    when others => null;
                end case;
                next_state <= S_FETCH;

            -- -----------------------------------------------------------------
            -- EJECUCIÓN: PUSH A (0x60)
            -- -----------------------------------------------------------------
            when S_EXEC_PUSH_1 =>
                -- Paso 1: Decrementar SP en 2 (Stack descendente, alineado a par)
                v_ctrl.SP_Op := SP_OP_DEC;
                next_state   <= S_EXEC_PUSH_2;

            when S_EXEC_PUSH_2 =>
                -- Paso 2: Escribir A en M[SP] (Little Endian: Byte bajo en dir baja)
                v_ctrl.ABUS_Sel  := ABUS_SRC_SP;
                v_ctrl.Mem_WE    := '1';
                v_ctrl.Out_Sel   := OUT_SEL_A; -- Dato = RegA
                v_ctrl.SP_Offset := '0';       -- Dir = SP
                if r_IR = x"62" then -- PUSH F
                    v_ctrl.Out_Sel := OUT_SEL_F; -- Dato = RegF
                elsif r_IR = x"61" then -- PUSH B
                    v_ctrl.Out_Sel := OUT_SEL_B; -- Dato = RegB
                elsif r_IR = x"63" then -- PUSH A:B
                    v_ctrl.Out_Sel := OUT_SEL_B; -- Dato = RegB (Byte Bajo)
                end if;
                next_state <= S_EXEC_PUSH_3;

            when S_EXEC_PUSH_3 =>
                -- Paso 3: Escribir 0x00 en M[SP+1]
                v_ctrl.ABUS_Sel  := ABUS_SRC_SP;
                v_ctrl.Mem_WE    := '1';
                v_ctrl.Out_Sel   := OUT_SEL_ZERO; -- Dato = 0x00
                v_ctrl.SP_Offset := '1';          -- Dir = SP + 1
                if r_IR = x"63" then -- PUSH A:B
                    v_ctrl.Out_Sel := OUT_SEL_A; -- Dato = RegA (Byte Alto)
                end if;
                next_state       <= S_FETCH;

            -- -----------------------------------------------------------------
            -- EJECUCIÓN: POP A (0x64)
            -- -----------------------------------------------------------------
            when S_EXEC_POP_1 =>
                -- Paso 1: Leer byte bajo M[SP] hacia MDR
                v_ctrl.ABUS_Sel  := ABUS_SRC_SP;
                v_ctrl.Mem_RE    := '1';
                v_ctrl.MDR_WE    := '1';
                v_ctrl.SP_Offset := '0';
                if r_IR = x"67" then next_state <= S_EXEC_POP_AB_2;
                else next_state <= S_EXEC_POP_2;
                end if;

            when S_EXEC_POP_2 =>
                -- Paso 2: Escribir MDR en A y restaurar SP (+2)
                v_ctrl.Bus_Op  := MEM_MDR_elected;
                v_ctrl.Write_A := '1';
                v_ctrl.SP_Op   := SP_OP_INC; -- SP += 2
                if r_IR = x"66" then -- POP F
                    next_state <= S_EXEC_POP_F_2;
                else
                    next_state <= S_FETCH;
                end if;

            when S_EXEC_POP_F_2 =>
                -- Alternativa para POP F: Escribir MDR en F
                v_ctrl.Bus_Op  := MEM_MDR_elected;
                v_ctrl.Load_F_Direct := '1'; -- Carga directa a F
                v_ctrl.SP_Op   := SP_OP_INC; -- SP += 2
                next_state     <= S_FETCH;

            when S_EXEC_POP_AB_2 =>
                -- POP A:B Paso 2: Escribir MDR en B, Leer byte alto M[SP+1]
                v_ctrl.Bus_Op  := MEM_MDR_elected;
                v_ctrl.Write_B := '1';
                v_ctrl.Reg_Sel := std_logic_vector(to_unsigned(1, REG_SEL_WIDTH)); -- R1 (B)
                
                v_ctrl.ABUS_Sel  := ABUS_SRC_SP;
                v_ctrl.SP_Offset := '1';
                v_ctrl.Mem_RE    := '1';
                v_ctrl.MDR_WE    := '1';
                next_state       <= S_EXEC_POP_AB_3;

            when S_EXEC_POP_AB_3 =>
                -- POP A:B Paso 3: Escribir MDR en A, SP += 2
                v_ctrl.Bus_Op  := MEM_MDR_elected;
                v_ctrl.Write_A := '1';
                v_ctrl.SP_Op   := SP_OP_INC;
                next_state     <= S_FETCH;

            -- -----------------------------------------------------------------
            -- EJECUCIÓN: CALL nn (0x75)
            -- -----------------------------------------------------------------
            when S_EXEC_CALL_1 =>
                -- 1. Leer Byte Bajo de destino -> TMP_L. Inc PC.
                v_ctrl.ABUS_Sel   := ABUS_SRC_PC;
                v_ctrl.Mem_RE     := '1';
                v_ctrl.Load_TMP_L := '1';
                v_ctrl.PC_Op      := PC_OP_INC;
                next_state        <= S_EXEC_CALL_2;

            when S_EXEC_CALL_2 =>
                -- 2. Leer Byte Alto de destino -> TMP_H. Inc PC.
                -- Al terminar este ciclo, PC apunta a la instrucción siguiente (Return Addr).
                v_ctrl.ABUS_Sel   := ABUS_SRC_PC;
                v_ctrl.Mem_RE     := '1';
                v_ctrl.Load_TMP_H := '1';
                v_ctrl.PC_Op      := PC_OP_INC;
                next_state        <= S_EXEC_CALL_3;

            when S_EXEC_CALL_3 =>
                -- 3. Reservar Stack (SP -= 2)
                v_ctrl.SP_Op := SP_OP_DEC;
                next_state   <= S_EXEC_CALL_4;

            when S_EXEC_CALL_4 =>
                -- 4. Push PC Low en M[SP]
                v_ctrl.ABUS_Sel  := ABUS_SRC_SP;
                v_ctrl.Mem_WE    := '1';
                v_ctrl.Out_Sel   := OUT_SEL_PCL; -- Salida = PC_L
                v_ctrl.SP_Offset := '0';
                next_state       <= S_EXEC_CALL_5;

            when S_EXEC_CALL_5 =>
                -- 5. Push PC High en M[SP+1]
                v_ctrl.ABUS_Sel  := ABUS_SRC_SP;
                v_ctrl.Mem_WE    := '1';
                v_ctrl.Out_Sel   := OUT_SEL_PCH; -- Salida = PC_H
                v_ctrl.SP_Offset := '1';
                next_state       <= S_EXEC_CALL_6;

            when S_EXEC_CALL_6 =>
                -- 6. Cargar PC con destino (TMP)
                v_ctrl.Load_Src_Sel := '1'; -- Fuente = TMP
                v_ctrl.PC_Op        := PC_OP_LOAD;
                next_state          <= S_FETCH;

            -- -----------------------------------------------------------------
            -- EJECUCIÓN: RET (0x77)
            -- -----------------------------------------------------------------
            -- Nota: Esta es una implementación de 3 ciclos de ejecución para una
            -- arquitectura de memoria de puerto único. La ISA v0.6 prevé una
            -- optimización a 2 ciclos usando RAS y TDP.
            when S_EXEC_RET_1 =>
                -- 1. Leer Low Byte de retorno desde M[SP] -> TMP_L
                v_ctrl.ABUS_Sel   := ABUS_SRC_SP;
                v_ctrl.SP_Offset  := '0';
                v_ctrl.Mem_RE     := '1';
                v_ctrl.Load_TMP_L := '1';
                next_state        <= S_EXEC_RET_2;

            when S_EXEC_RET_2 =>
                -- 2. Leer High Byte de retorno desde M[SP+1] -> TMP_H
                v_ctrl.ABUS_Sel   := ABUS_SRC_SP;
                v_ctrl.SP_Offset  := '1';
                v_ctrl.Mem_RE     := '1';
                v_ctrl.Load_TMP_H := '1';
                next_state        <= S_EXEC_RET_3;

            when S_EXEC_RET_3 =>
                -- 3. Cargar PC con la dirección de retorno (TMP) y restaurar SP
                v_ctrl.Load_Src_Sel := '1'; -- Fuente = TMP
                v_ctrl.PC_Op        := PC_OP_LOAD;
                v_ctrl.SP_Op        := SP_OP_INC; -- SP += 2
                next_state          <= S_FETCH;

            -- -----------------------------------------------------------------
            -- EJECUCIÓN: RTI (0x06)
            -- Secuencia inversa a INT Entry: Pop F, Pop PC
            -- Stack: [SP]=Flags, [SP+1]=00, [SP+2]=PC_L, [SP+3]=PC_H
            -- -----------------------------------------------------------------
            when S_EXEC_RTI_1 =>
                -- 1. Leer Flags desde M[SP]
                v_ctrl.ABUS_Sel  := ABUS_SRC_SP;
                v_ctrl.SP_Offset := '0';
                v_ctrl.Mem_RE    := '1';
                v_ctrl.MDR_WE    := '1';
                next_state       <= S_EXEC_RTI_2;
                
            when S_EXEC_RTI_2 =>
                -- 2. Restaurar F, Inc SP (skip padding), Leer PC_L (que está en SP+2 ahora)
                v_ctrl.Bus_Op        := MEM_MDR_elected;
                v_ctrl.Load_F_Direct := '1'; -- F <- MDR
                v_ctrl.SP_Op         := SP_OP_INC; -- SP += 2 (apunta a PC_L)
                next_state           <= S_EXEC_RTI_3;
                
            when S_EXEC_RTI_3 =>
                -- 3. Leer PC_L desde M[SP] -> TMP_L
                v_ctrl.ABUS_Sel   := ABUS_SRC_SP;
                v_ctrl.SP_Offset  := '0';
                v_ctrl.Mem_RE     := '1';
                v_ctrl.Load_TMP_L := '1';
                next_state        <= S_EXEC_RTI_4;
                
            when S_EXEC_RTI_4 =>
                -- 4. Leer PC_H desde M[SP+1] -> TMP_H
                v_ctrl.ABUS_Sel   := ABUS_SRC_SP;
                v_ctrl.SP_Offset  := '1';
                v_ctrl.Mem_RE     := '1';
                v_ctrl.Load_TMP_H := '1';
                -- Next state: Load PC from TMP + Final SP adjust
                next_state        <= S_INT_VEC_3; -- Reutilizamos estado final de carga PC

            -- -----------------------------------------------------------------
            -- EJECUCIÓN: LD A, [nn] y ST A, [nn]
            -- y modos indexados [nn+B]
            -- -----------------------------------------------------------------
            when S_EXEC_ADDR_FETCH_HI =>
                -- PC apunta al byte alto de la dirección. Lo leemos y lo cargamos en TMP_H.
                -- Al final de este ciclo, TMP contendrá la dirección completa [nn].
                v_ctrl.ABUS_Sel   := ABUS_SRC_PC;
                v_ctrl.Mem_RE     := '1';
                v_ctrl.Load_TMP_H := '1';
                v_ctrl.PC_Op      := PC_OP_INC; -- PC apunta a la siguiente instrucción

                -- Bifurcación según la instrucción
                -- Los modos indexados y absolutos comparten esta lógica de fetch de dirección
                case r_IR is
                    when x"13" | x"23" => next_state <= S_EXEC_LD_ABS_READ;  -- LD [nn]
                    when x"15" | x"25" => next_state <= S_EXEC_LD_IDX_READ;  -- LD [nn+B]
                    when x"31" | x"41" => next_state <= S_EXEC_ST_ABS_WRITE; -- ST [nn]
                    when x"33" | x"42" => next_state <= S_EXEC_ST_IDX_WRITE; -- ST [nn+B]
                    when x"12" | x"22" | x"30" | x"40" => next_state <= S_EXEC_PZ_FETCH; -- [n]
                    when x"14" | x"24" | x"32"         => next_state <= S_EXEC_INDB_SETUP; -- [B]
                    when others => next_state <= S_FETCH;
                end if;

            when S_EXEC_LD_ABS_READ =>
                -- TMP tiene la dirección. La ponemos en el bus y leemos de memoria.
                v_ctrl.EA_A_Sel  := EA_A_SRC_TMP;
                v_ctrl.EA_B_Sel  := EA_B_SRC_ZERO;
                v_ctrl.ABUS_Sel  := ABUS_SRC_EA_RES;
                v_ctrl.Mem_RE    := '1';
                v_ctrl.MDR_WE    := '1'; -- Capturar el dato en MDR
                next_state       <= S_EXEC_LD_WB;

            when S_EXEC_LD_IDX_READ =>
                -- TMP tiene la base, B el índice. Calculamos EA y leemos.
                v_ctrl.EA_A_Sel  := EA_A_SRC_TMP;
                v_ctrl.EA_B_Sel  := EA_B_SRC_REG_B;
                v_ctrl.ABUS_Sel  := ABUS_SRC_EA_RES;
                v_ctrl.Mem_RE    := '1';
                v_ctrl.MDR_WE    := '1';
                next_state       <= S_EXEC_LD_WB;

            when S_EXEC_LD_WB =>
                -- El dato está en MDR. Lo escribimos en A.
                v_ctrl.Bus_Op := MEM_MDR_elected;
                if r_IR(4) = '1' then -- Opcodes 1x (LD A) vs 2x (LD B)
                    v_ctrl.Write_A := '1';
                else -- LD B, ...
                    v_ctrl.Write_B := '1';
                    v_ctrl.Reg_Sel := std_logic_vector(to_unsigned(1, REG_SEL_WIDTH));
                end if;
                v_ctrl.Write_F := '1'; v_ctrl.Flag_Mask(idx_fZ) := '1'; -- LD afecta a Z
                next_state     <= S_FETCH;

            when S_EXEC_ST_ABS_WRITE =>
                -- TMP tiene la dirección. Ponemos la dirección y el dato de A en los buses y escribimos.
                v_ctrl.EA_A_Sel := EA_A_SRC_TMP;
                v_ctrl.EA_B_Sel := EA_B_SRC_ZERO;
                v_ctrl.ABUS_Sel := ABUS_SRC_EA_RES;
                if r_IR(4) = '1' then -- Opcodes 3x (ST A) vs 4x (ST B)
                    v_ctrl.Out_Sel := OUT_SEL_A;
                else
                    v_ctrl.Out_Sel := OUT_SEL_B;
                end if;
                v_ctrl.Mem_WE   := '1';
                next_state      <= S_FETCH;

            when S_EXEC_ST_IDX_WRITE =>
                -- TMP tiene la base, B el índice. Calculamos EA y escribimos A.
                v_ctrl.EA_A_Sel := EA_A_SRC_TMP;
                v_ctrl.EA_B_Sel := EA_B_SRC_REG_B;
                v_ctrl.ABUS_Sel := ABUS_SRC_EA_RES;
                if r_IR(4) = '1' then v_ctrl.Out_Sel := OUT_SEL_A; else v_ctrl.Out_Sel := OUT_SEL_B; end if;
                v_ctrl.Mem_WE   := '1';
                next_state      <= S_FETCH;

            when S_EXEC_PZ_FETCH =>
                -- El operando 'n' está en InstrIn. Lo cargamos en TMP_L y limpiamos TMP_H.
                v_ctrl.Clear_TMP  := '1';
                v_ctrl.Load_TMP_L := '1';
                v_ctrl.PC_Op      := PC_OP_INC;
                
                -- Check bit 5 to distinguish LD (0x12/0x22) vs ST (0x30/0x40)
                -- Opcodes: LD A (12), LD B (22), ST A (30), ST B (40)
                -- Binario: 00010010, 00100010, 00110000, 01000000
                -- LD opcodes have bit 5 = 0 (mostly) or different pattern.
                -- Simple check: opcode < 0x30 is LD.
                if unsigned(r_IR) < x"30" then
                    next_state <= S_EXEC_LD_ABS_READ;
                else
                    next_state <= S_EXEC_ST_ABS_WRITE;
                end if;

            when S_EXEC_INDB_SETUP =>
                -- Preparamos para calcular [B] poniendo TMP a cero.
                v_ctrl.Clear_TMP := '1';
                -- En el siguiente ciclo, TMP será 0, y podemos usar el sumador
                -- para calcular 0 + B.
                -- La instrucción LD B, [B] es de 1 byte, PC ya apunta a la siguiente.
                -- Reutilizamos el estado de lectura indexada.
                next_state <= S_EXEC_LD_IDX_READ;

            -- -----------------------------------------------------------------
            -- EJECUCIÓN: IN / OUT
            -- -----------------------------------------------------------------
            when S_EXEC_IO_FETCH_PORT =>
                -- Leer operando #n (número de puerto) y ponerlo en TMP.
                -- PC se incrementa.
                v_ctrl.ABUS_Sel   := ABUS_SRC_PC;
                v_ctrl.Mem_RE     := '1';
                v_ctrl.Load_TMP_L := '1';
                v_ctrl.Clear_TMP  := '1'; -- TMP_H = 0
                v_ctrl.PC_Op      := PC_OP_INC;
                
                if r_IR = x"D0" then -- IN A, #n
                    next_state <= S_EXEC_IN_READ;
                else -- OUT #n, A
                    next_state <= S_EXEC_OUT_WRITE;
                end if;

            when S_EXEC_IO_SETUP_REG =>
                -- IN A, [B] / OUT [B], A. 
                -- Limpiamos TMP para que EA = 0 + B.
                v_ctrl.Clear_TMP := '1';
                if r_IR = x"D1" then -- IN A, [B]
                    next_state <= S_EXEC_IN_READ;
                else -- OUT [B], A
                    next_state <= S_EXEC_OUT_WRITE;
                end if;

            when S_EXEC_IN_READ =>
                -- Leer del espacio I/O.
                -- Dirección = EA (TMP + B o TMP + 0)
                v_ctrl.EA_A_Sel := EA_A_SRC_TMP;
                -- Si es indirecto [B] (D1), usamos REG_B. Si es inmediato #n (D0), TMP tiene la dir, B=0.
                if r_IR = x"D1" then v_ctrl.EA_B_Sel := EA_B_SRC_REG_B; else v_ctrl.EA_B_Sel := EA_B_SRC_ZERO; end if;
                
                v_ctrl.ABUS_Sel := ABUS_SRC_EA_RES;
                v_ctrl.IO_RE    := '1';
                v_ctrl.MDR_WE   := '1';
                next_state      <= S_EXEC_IN_WB;

            when S_EXEC_IN_WB =>
                -- Escribir MDR en A y actualizar flag Z
                v_ctrl.Bus_Op   := MEM_MDR_elected;
                v_ctrl.Write_A  := '1';
                v_ctrl.Write_F  := '1';
                v_ctrl.Flag_Mask(idx_fZ) := '1';
                next_state      <= S_FETCH;

            when S_EXEC_OUT_WRITE =>
                -- Escribir A en el espacio I/O.
                v_ctrl.EA_A_Sel := EA_A_SRC_TMP;
                if r_IR = x"D3" then v_ctrl.EA_B_Sel := EA_B_SRC_REG_B; else v_ctrl.EA_B_Sel := EA_B_SRC_ZERO; end if;
                v_ctrl.ABUS_Sel := ABUS_SRC_EA_RES;
                v_ctrl.Out_Sel  := OUT_SEL_A;
                v_ctrl.IO_WE    := '1';
                next_state      <= S_FETCH;

            -- -----------------------------------------------------------------
            -- EJECUCIÓN: Operaciones 16-bit (ADD16, SUB16)
            -- -----------------------------------------------------------------
            when S_EXEC_OP16_IMM8_WB1 =>
                -- Ops #n (0xE0, 0xE2). PC apunta al operando inmediato 8-bit.
                -- Leer operando (DataIn), Sign-Extend y operar con A:B.
                v_ctrl.ABUS_Sel := ABUS_SRC_PC;
                v_ctrl.Mem_RE   := '1';
                v_ctrl.PC_Op    := PC_OP_INC;

                -- Configurar EA Adder: A=A:B, B=DataIn(sext).
                v_ctrl.EA_A_Sel := EA_A_SRC_REG_AB;
                v_ctrl.EA_B_Sel := EA_B_SRC_DATA_IN;
                if r_IR = x"E0" then v_ctrl.EA_Op := EA_OP_ADD; else v_ctrl.EA_Op := EA_OP_SUB; end if;

                -- Write-Back A (High) y Flags
                v_ctrl.Bus_Op    := EA_HIGH_elected;
                v_ctrl.Write_A   := '1';
                v_ctrl.F_Src_Sel := '1'; -- Flags desde EA
                v_ctrl.Write_F   := '1';
                v_ctrl.Flag_Mask := x"F0";

                -- Siguiente: Escribir B. Reutilizamos el estado WB_2 común.
                next_state <= S_EXEC_OP16_WB_2;

            when S_EXEC_OP16_FETCH_1 =>
                -- Ya tenemos TMP_L (byte bajo operando). Leemos byte alto -> TMP_H.
                v_ctrl.ABUS_Sel   := ABUS_SRC_PC;
                v_ctrl.Mem_RE     := '1';
                v_ctrl.Load_TMP_H := '1';
                v_ctrl.PC_Op      := PC_OP_INC;
                next_state        <= S_EXEC_OP16_WB_1;

            when S_EXEC_OP16_WB_1 =>
                -- Paso 1: Ejecutar, escribir Byte Alto en A y actualizar Flags
                -- Configurar EA Adder: A=A:B, B=TMP.
                v_ctrl.EA_A_Sel := EA_A_SRC_REG_AB;
                v_ctrl.EA_B_Sel := EA_B_SRC_TMP;
                if r_IR = x"E1" then v_ctrl.EA_Op := EA_OP_ADD; else v_ctrl.EA_Op := EA_OP_SUB; end if;

                -- Escribir EA_HIGH en A
                v_ctrl.Bus_Op := EA_HIGH_elected;
                v_ctrl.Write_A := '1';

                -- Capturar flags de 16 bits ahora (antes de que A cambie y corrompa el cálculo)
                v_ctrl.F_Src_Sel := '1'; -- Fuente = AddressPath
                v_ctrl.Write_F   := '1';
                v_ctrl.Flag_Mask := x"F0"; -- Actualizar C, V, Z (H no se usa en 16b)

                next_state <= S_EXEC_OP16_WB_2;

            when S_EXEC_OP16_WB_2 =>
                -- Paso 2: Escribir Byte Bajo en B
                -- Mantener configuración del sumador (aunque el resultado High sea inválido ahora porque A cambió,
                -- el resultado Low sigue siendo válido porque solo depende de B y TMP_L).
                v_ctrl.EA_A_Sel := EA_A_SRC_REG_AB;
                if r_IR = x"E0" or r_IR = x"E2" then
                    v_ctrl.EA_B_Sel := EA_B_SRC_DATA_IN; -- Para #n, necesitamos mantener el dato en bus
                    v_ctrl.Mem_RE   := '1'; -- Mantener lectura (o asumir dato estable si es síncrono/latch)
                else
                    v_ctrl.EA_B_Sel := EA_B_SRC_TMP;     -- Para #nn, dato en TMP
                end if;

                if r_IR = x"E0" or r_IR = x"E1" then v_ctrl.EA_Op := EA_OP_ADD; else v_ctrl.EA_Op := EA_OP_SUB; end if;
                -- Escribir EA_LOW en B
                v_ctrl.Bus_Op  := EA_LOW_elected;
                v_ctrl.Write_B := '1';
                v_ctrl.Reg_Sel := std_logic_vector(to_unsigned(1, REG_SEL_WIDTH)); -- R1 (B)

                next_state <= S_FETCH;

            -- -----------------------------------------------------------------
            -- EJECUCIÓN: Manipulación del Stack Pointer (LD SP, ST SP)
            -- -----------------------------------------------------------------
            when S_EXEC_LDSP_1 =>
                -- LD SP, #nn. Byte bajo ya en TMP_L (decodificación con Load_TMP_L).
                -- Leer byte alto desde M[PC]
                v_ctrl.ABUS_Sel   := ABUS_SRC_PC;
                v_ctrl.Mem_RE     := '1';
                v_ctrl.Load_TMP_H := '1';
                v_ctrl.PC_Op      := PC_OP_INC;
                next_state        <= S_EXEC_LDSP_2;

            when S_EXEC_LDSP_2 =>
                -- Cargar SP con valor de TMP
                v_ctrl.Load_Src_Sel := '1'; -- Fuente = TMP
                v_ctrl.SP_Op        := SP_OP_LOAD;
                next_state          <= S_FETCH;

            when S_EXEC_LDSP_AB =>
                -- LD SP, A:B.
                -- Usar EA Adder para pasar A:B (A:B + 0)
                v_ctrl.EA_A_Sel     := EA_A_SRC_REG_AB;
                v_ctrl.EA_B_Sel     := EA_B_SRC_ZERO;
                v_ctrl.EA_Op        := EA_OP_ADD;
                
                -- Cargar SP con resultado EA
                v_ctrl.Load_Src_Sel := '0'; -- Fuente = EA Adder
                v_ctrl.SP_Op        := SP_OP_LOAD;
                next_state          <= S_FETCH;

            when S_EXEC_STSP_WB =>
                -- ST SP_L, A (0x52) o ST SP_H, A (0x53).
                -- Pasar SP por el EA Adder (SP + 0) para tenerlo en EA_Out
                v_ctrl.EA_A_Sel := EA_A_SRC_SP;
                v_ctrl.EA_B_Sel := EA_B_SRC_ZERO;
                v_ctrl.EA_Op    := EA_OP_ADD;
                
                -- Escribir en A la parte seleccionada del resultado EA
                if r_IR = x"52" then
                    v_ctrl.Bus_Op := EA_LOW_elected;  -- SP[7:0]
                else
                    v_ctrl.Bus_Op := EA_HIGH_elected; -- SP[15:8]
                end if;
                
                v_ctrl.Write_A := '1';
                -- No afecta flags
                next_state <= S_FETCH;

            -- -----------------------------------------------------------------
            -- EJECUCIÓN: Salto Relativo Condicional (BEQ)
            -- -----------------------------------------------------------------
            when S_EXEC_BRANCH_REL_1 =>
                -- PC apunta al operando rel8. Lo leemos y a la vez calculamos
                -- la dirección de salto: (PC+1) + sign_ext(rel8).
                -- El PC se incrementa para apuntar a la siguiente instrucción.
                v_ctrl.ABUS_Sel := ABUS_SRC_PC;
                v_ctrl.Mem_RE   := '1';
                v_ctrl.PC_Op    := PC_OP_INC;
                next_state      <= S_EXEC_BRANCH_REL_2;

            when S_EXEC_BRANCH_REL_2 =>
                -- El PC ya apunta a la siguiente instrucción (PC+1).
                -- El operando rel8 está en InstrIn.
                -- Usamos el sumador para calcular PC + rel8.
                v_ctrl.EA_A_Sel     := EA_A_SRC_PC;
                v_ctrl.EA_B_Sel     := EA_B_SRC_DATA_IN;
                v_ctrl.Load_Src_Sel := LOAD_SRC_ALU_RES;
                v_ctrl.PC_Op        := PC_OP_LOAD; -- Cargar PC con el resultado
                next_state          <= S_FETCH;

            when S_SKIP_BYTE =>
                -- Salto no tomado: simplemente saltamos el operando y vamos a la siguiente.
                v_ctrl.PC_Op := PC_OP_INC; -- Importante: Saltar el byte de offset (rel8)
                next_state <= S_FETCH;

            -- -----------------------------------------------------------------
            -- EJECUCIÓN: JP nn (Opcode 0x70) - 3 bytes
            -- -----------------------------------------------------------------
            when S_EXEC_JP_1 =>
                v_ctrl.ABUS_Sel   := ABUS_SRC_PC;
                v_ctrl.Mem_RE     := '1';
                v_ctrl.Load_TMP_L := '1';       -- Cargar en TMP[7:0]
                v_ctrl.PC_Op      := PC_OP_INC; -- Avanzar a High Byte
                next_state        <= S_EXEC_JP_2;

            when S_EXEC_JP_2 =>
                v_ctrl.ABUS_Sel   := ABUS_SRC_PC;
                v_ctrl.Mem_RE     := '1';
                v_ctrl.Load_TMP_H := '1';       -- Cargar en TMP[15:8]
                v_ctrl.PC_Op      := PC_OP_INC; -- Avanzar
                next_state        <= S_EXEC_JP_3;

            when S_EXEC_JP_3 =>
                v_ctrl.Load_Src_Sel := '1'; -- Fuente = TMP
                v_ctrl.PC_Op        := PC_OP_LOAD;
                next_state          <= S_FETCH;

            when others =>
                next_state <= S_FETCH;

        end case;

        -- =====================================================================
        -- Lógica de Wait States (Global Stall)
        -- =====================================================================
        -- Si estamos accediendo a memoria y esta no está lista, mantenemos el estado.
        if (v_ctrl.Mem_RE = '1' or v_ctrl.Mem_WE = '1') and Mem_Ready = '0' then
            next_state <= state;
        end if;

        -- Asignación final
        CtrlBus <= v_ctrl;
        
    end process;

end architecture Behavioral;