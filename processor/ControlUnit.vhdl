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

architecture Behavioral of ControlUnit is

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

                    -- LD B, A (0x20) - NUEVO
                    when x"20" =>
                        next_state <= S_EXEC_MOV_BA;

                    -- LD B, #n (0x21) - NUEVO
                    when x"21" =>
                        next_state <= S_EXEC_LDI_B_1;

                    -- ALU Register Ops (A op B) -> A
                    -- ADD(0x90), SUB(0x92), AND(0x94), OR(0x95), CMP(0x97)
                    when x"90" | x"92" | x"94" | x"95" | x"97" =>
                        next_state <= S_EXEC_ALU_R;

                    -- ALU Immediate Ops (A op #n) -> A
                    -- ADD#(0xA0), SUB#(0xA2), AND#(0xA4), OR#(0xA5), CMP#(0xA7)
                    when x"A0" | x"A2" | x"A4" | x"A5" | x"A7" =>
                        next_state <= S_EXEC_ALU_IMM_1;

                    -- BEQ rel8 (0x80)
                    when x"80" =>
                        if FlagsIn(idx_fZ) = '1' then next_state <= S_EXEC_BRANCH_REL_1; else next_state <= S_SKIP_BYTE; end if;
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