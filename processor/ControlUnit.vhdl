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
        
        S_EXEC_LDI_1,   -- LD A, #n: Leer inmediato
        S_EXEC_LDI_2,   -- LD A, #n: Escribir en A
        
        S_EXEC_MOV_AB,  -- LD A, B: Transferencia registro
        
        S_EXEC_MOV_BA,  -- LD B, A: Transferencia registro (0x20)
        S_EXEC_LDI_B_1, -- LD B, #n: Leer inmediato (0x21)
        S_EXEC_LDI_B_2, -- LD B, #n: Escribir en B
        
        S_EXEC_ALU_R,   -- ALU A, B (ADD, SUB, AND, OR...)
        
        S_EXEC_ALU_IMM_1, -- ALU A, #n: Fetch inmediato
        S_EXEC_ALU_IMM_2, -- ALU A, #n: Execute & Write Back
        
        S_EXEC_PUSH_1,    -- PUSH: Decrementar SP
        S_EXEC_PUSH_2,    -- PUSH: Escribir byte bajo
        S_EXEC_PUSH_3,    -- PUSH: Escribir byte alto (0x00)
        
        S_EXEC_POP_1,     -- POP: Leer byte bajo
        S_EXEC_POP_2,     -- POP: Guardar en Reg y Incrementar SP
        
        S_EXEC_CALL_1,    -- CALL: Leer destino LOW
        S_EXEC_CALL_2,    -- CALL: Leer destino HIGH
        S_EXEC_CALL_3,    -- CALL: Decrementar SP
        S_EXEC_CALL_4,    -- CALL: Push PC LOW
        S_EXEC_CALL_5,    -- CALL: Push PC HIGH
        S_EXEC_CALL_6,    -- CALL: Cargar PC destino

        S_EXEC_RET_1,     -- RET: Leer PC LOW desde Stack
        S_EXEC_RET_2,     -- RET: Leer PC HIGH desde Stack
        S_EXEC_RET_3,     -- RET: Cargar PC y restaurar SP

        S_EXEC_ADDR_FETCH_HI, -- LD/ST [nn] o [nn+B]: Leer byte alto de la dirección base
        S_EXEC_PZ_FETCH,      -- LD/ST [n]: Cargar dirección de página cero en TMP
        S_EXEC_INDB_SETUP,    -- LD/ST [B]: Preparar TMP para cálculo de dirección
        S_EXEC_LD_ABS_READ,  -- LD A, [nn]: Leer dato de memoria
        S_EXEC_LD_IDX_READ,  -- LD A, [nn+B]: Calcular EA y leer dato
        S_EXEC_LD_WB,        -- LD A, [...]: Escribir dato en A (Write-Back)
        S_EXEC_ST_ABS_WRITE, -- ST A, [nn]: Escribir dato en memoria
        S_EXEC_ST_IDX_WRITE, -- ST A, [nn+B]: Calcular EA y escribir dato
        
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

begin

    -- =========================================================================
    -- 1. Proceso Secuencial (Memoria de Estado)
    -- =========================================================================
    seq_proc: process(clk, reset)
    begin
        if reset = '1' then
            state <= S_RESET;
            r_IR  <= (others => '0');
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
                next_state      <= S_DECODE;

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

                    -- LD A, B (0x10)
                    when x"10" =>
                        next_state <= S_EXEC_MOV_AB;

                    -- LD A, #n (0x11)
                    when x"11" =>
                        next_state <= S_EXEC_LDI_1;

                    -- LD A, [nn] (0x13)
                    when x"13" =>
                        v_ctrl.Load_TMP_L := '1';
                        next_state <= S_EXEC_ADDR_FETCH_HI;

                    -- LD A, [nn+B] (0x15)
                    when x"15" =>
                        v_ctrl.Load_TMP_L := '1';
                        next_state <= S_EXEC_ADDR_FETCH_HI;

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

                    -- ST A, [nn] (0x31)
                    when x"31" =>
                        v_ctrl.Load_TMP_L := '1';
                        next_state <= S_EXEC_ADDR_FETCH_HI;

                    -- ST A, [nn+B] (0x33)
                    when x"33" =>
                        v_ctrl.Load_TMP_L := '1';
                        next_state <= S_EXEC_ADDR_FETCH_HI;

                    -- ST B, [n] (0x40), [nn] (0x41), [nn+B] (0x42)
                    when x"40" | x"41" | x"42" =>
                        v_ctrl.Load_TMP_L := '1';
                        next_state <= S_EXEC_ADDR_FETCH_HI;

                    -- ALU Register Ops (A op B) -> A
                    -- ADD(0x90), SUB(0x92), AND(0x94), OR(0x95), CMP(0x97)
                    when x"90" | x"92" | x"94" | x"95" | x"97" =>
                        next_state <= S_EXEC_ALU_R;

                    -- ALU Immediate Ops (A op #n) -> A
                    -- ADD#(0xA0), SUB#(0xA2), AND#(0xA4), OR#(0xA5), CMP#(0xA7)
                    when x"A0" | x"A2" | x"A4" | x"A5" | x"A7" =>
                        next_state <= S_EXEC_ALU_IMM_1;

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

                    -- POP A (0x64)
                    when x"64" =>
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
                    when x"92" => v_ctrl.ALU_Op := OP_SUB; v_ctrl.Flag_Mask := x"FF";
                    when x"94" => v_ctrl.ALU_Op := OP_AND; v_ctrl.Flag_Mask := x"1C"; -- Z,G,E
                    when x"95" => v_ctrl.ALU_Op := OP_IOR; v_ctrl.Flag_Mask := x"1C";
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
                    when x"A2" => v_ctrl.ALU_Op := OP_SUB; v_ctrl.Flag_Mask := x"FF";
                    when x"A4" => v_ctrl.ALU_Op := OP_AND; v_ctrl.Flag_Mask := x"1C";
                    when x"A5" => v_ctrl.ALU_Op := OP_IOR; v_ctrl.Flag_Mask := x"1C";
                    when x"A7" => v_ctrl.ALU_Op := OP_CMP; v_ctrl.Flag_Mask := x"FF"; v_ctrl.Write_A := '0'; -- CMP #n (No escribe A)
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
                next_state       <= S_EXEC_PUSH_3;

            when S_EXEC_PUSH_3 =>
                -- Paso 3: Escribir 0x00 en M[SP+1]
                v_ctrl.ABUS_Sel  := ABUS_SRC_SP;
                v_ctrl.Mem_WE    := '1';
                v_ctrl.Out_Sel   := OUT_SEL_ZERO; -- Dato = 0x00
                v_ctrl.SP_Offset := '1';          -- Dir = SP + 1
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
                next_state       <= S_EXEC_POP_2;

            when S_EXEC_POP_2 =>
                -- Paso 2: Escribir MDR en A y restaurar SP (+2)
                v_ctrl.Bus_Op  := MEM_MDR_elected;
                v_ctrl.Write_A := '1';
                v_ctrl.SP_Op   := SP_OP_INC; -- SP += 2
                -- (Byte alto M[SP+1] se ignora en POP A de 8 bits)
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
                    when x"13" | x"23" => next_state <= S_EXEC_LD_ABS_READ;  -- LD A/B, [nn]
                    when x"15" | x"25" => next_state <= S_EXEC_LD_IDX_READ;  -- LD A/B, [nn+B]
                    when x"31" | x"41" => next_state <= S_EXEC_ST_ABS_WRITE; -- ST A/B, [nn]
                    when x"33" | x"42" => next_state <= S_EXEC_ST_IDX_WRITE; -- ST A/B, [nn+B]
                    when x"22" | x"40" => next_state <= S_EXEC_PZ_FETCH;     -- LD/ST A/B, [n]
                    when x"24"         => next_state <= S_EXEC_INDB_SETUP;   -- LD B, [B]
                    when others        => next_state <= S_FETCH; -- Error, volver a fetch
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
                if r_IR = x"13" or r_IR = x"15" then -- LD A, ...
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
                if r_IR = x"31" or r_IR = x"40" then -- ST A/B, [n] o [nn]
                    v_ctrl.Out_Sel := OUT_SEL_A when r_IR = x"31" else OUT_SEL_B;
                else
                    v_ctrl.Out_Sel := OUT_SEL_A;
                end if;
                v_ctrl.Mem_WE   := '1';
                next_state      <= S_FETCH;

            when S_EXEC_ST_IDX_WRITE =>
                -- TMP tiene la base, B el índice. Calculamos EA y escribimos A.
                v_ctrl.EA_A_Sel := EA_A_SRC_TMP;
                v_ctrl.EA_B_Sel := EA_B_SRC_REG_B;
                v_ctrl.ABUS_Sel := ABUS_SRC_EA_RES;
                if r_IR = x"33" then v_ctrl.Out_Sel := OUT_SEL_A; else v_ctrl.Out_Sel := OUT_SEL_B; end if;
                v_ctrl.Mem_WE   := '1';
                next_state      <= S_FETCH;

            when S_EXEC_PZ_FETCH =>
                -- El operando 'n' está en InstrIn. Lo cargamos en TMP_L y limpiamos TMP_H.
                v_ctrl.Clear_TMP  := '1';
                v_ctrl.Load_TMP_L := '1';
                v_ctrl.PC_Op      := PC_OP_INC;
                if r_IR = x"22" then -- LD B, [n]
                    next_state <= S_EXEC_LD_ABS_READ;
                else -- ST B, [n]
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

        -- Asignación final
        CtrlBus <= v_ctrl;
        
    end process;

end architecture Behavioral;