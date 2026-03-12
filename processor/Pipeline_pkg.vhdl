--------------------------------------------------------------------------------
-- Package: Pipeline_pkg
-- Description:
--   Defines types for the 4-stage pipeline registers used by the pipelined
--   ControlUnit architecture.  Both the IF/ID and ID/EX inter-stage registers
--   are declared here, together with safe NOP default constants.
--
--   The package also declares the two sub-state enumerations:
--     dss_t  – Decode Sub-State: tracks multi-byte operand fetches during the
--              DECODE stage (DSS_OPCODE, DSS_OP1, DSS_OP2).
--     ess_t  – Exec Sub-State: tracks multi-cycle execution sequences; the
--              states mirror the original FSM states from ControlUnit (unique)
--              so that the same micro-operation encoding can be reused.
--
-- Dependencies: CONSTANTS_pkg, ALU_pkg, DataPath_pkg, AddressPath_pkg,
--               ControlUnit_pkg
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use work.CONSTANTS_pkg.ALL;
use work.ALU_pkg.ALL;
use work.DataPath_pkg.ALL;
use work.AddressPath_pkg.ALL;
use work.ControlUnit_pkg.ALL;

package Pipeline_pkg is

    -- =========================================================================
    -- Decode Sub-State
    -- =========================================================================
    -- Tracks how many operand bytes still need to be fetched during DECODE.
    type dss_t is (
        DSS_OPCODE,   -- Processing opcode byte (first DECODE cycle)
        DSS_OP1,      -- Fetching / latching first operand byte
        DSS_OP2       -- Fetching / latching second operand byte
    );

    -- =========================================================================
    -- Exec Sub-State
    -- =========================================================================
    -- Each state represents one micro-operation cycle during multi-cycle
    -- instruction execution.  Naming mirrors the original FSM for clarity.
    type ess_t is (
        ESS_IDLE,         -- No multi-cycle execution in progress

        -- Address fetch helpers
        ESS_ADDR_HI,      -- Fetch high byte of 16-bit address into TMP_H
        ESS_PZ_FETCH,     -- Fetch zero-page byte into TMP_L (clear TMP_H)
        ESS_INDB_SETUP,   -- Clear TMP to compute EA = 0 + B

        -- Load / Store
        ESS_LD_ABS,       -- Read M[TMP] into MDR (absolute addressing)
        ESS_LD_IDX,       -- Read M[TMP+B] into MDR (indexed / indirect)
        ESS_LD_WB,        -- Write MDR into destination register

        ESS_ST_ABS,       -- Write register to M[TMP] (absolute)
        ESS_ST_IDX,       -- Write register to M[TMP+B] (indexed)

        -- Stack: PUSH
        ESS_PUSH_1,       -- SP -= 2
        ESS_PUSH_2,       -- Write low/only byte to M[SP]
        ESS_PUSH_3,       -- Write high/padding byte to M[SP+1]

        -- Stack: POP
        ESS_POP_1,        -- Read M[SP] into MDR
        ESS_POP_2,        -- Write MDR -> register, SP += 2
        ESS_POP_F_2,      -- Write MDR -> F directly, SP += 2
        ESS_POP_AB_2,     -- Write MDR -> B; read M[SP+1] into MDR
        ESS_POP_AB_3,     -- Write MDR -> A, SP += 2

        -- Subroutine call
        ESS_CALL_1,       -- Fetch dest_L -> TMP_L, PC++
        ESS_CALL_2,       -- Fetch dest_H -> TMP_H, PC++
        ESS_CALL_3,       -- SP -= 2
        ESS_CALL_4,       -- Write PC_L to M[SP]
        ESS_CALL_5,       -- Write PC_H to M[SP+1]
        ESS_CALL_6,       -- PC <- TMP (jump to subroutine)

        -- Return
        ESS_RET_1,        -- Read M[SP] -> TMP_L
        ESS_RET_2,        -- Read M[SP+1] -> TMP_H
        ESS_RET_3,        -- PC <- TMP, SP += 2

        -- Return from interrupt
        ESS_RTI_1,        -- Read M[SP] -> MDR (flags)
        ESS_RTI_2,        -- F <- MDR, SP += 2
        ESS_RTI_3,        -- Read M[SP] -> TMP_L
        ESS_RTI_4,        -- Read M[SP+1] -> TMP_H, then reuse ESS_JP_3 to load PC

        -- Interrupt entry (NMI / IRQ)
        ESS_INT_1,        -- SP -= 2 (push PC)
        ESS_INT_2,        -- Write PC_L to M[SP]
        ESS_INT_3,        -- Write PC_H to M[SP+1]
        ESS_INT_4,        -- SP -= 2 (push F)
        ESS_INT_5,        -- Write F to M[SP]
        ESS_INT_6,        -- Write 0x00 to M[SP+1]
        ESS_INT_7,        -- Fetch vector low -> TMP_L
        ESS_INT_8,        -- Fetch vector high -> TMP_H
        ESS_INT_9,        -- PC <- TMP (dispatch to handler)

        -- Branches / Jumps
        ESS_BRANCH_2,     -- Compute PC + rel8 and load PC
        ESS_JP_3,         -- PC <- TMP (common jump final)
        ESS_JP_AB,        -- PC <- A:B (JP A:B)
        ESS_JPN_2,        -- PC_L <- TMP_L (JPN page8 final)

        -- Indirect jumps / calls: read 16-bit pointer from memory
        ESS_IND_LOAD,     -- PC <- TMP (load pointer address)
        ESS_IND_READ_L,   -- Read M[PC] -> TMP_L, PC++
        ESS_IND_READ_H,   -- Read M[PC] -> TMP_H  (then ESS_JP_3)

        -- 16-bit arithmetic
        ESS_OP16_IMM8,    -- ADD16/SUB16 #n: fetch imm, compute EA, write A+flags
        ESS_OP16_FETCH1,  -- ADD16/SUB16 #nn: fetch TMP_H
        ESS_OP16_WB1,     -- Write EA_H -> A, flags
        ESS_OP16_WB2,     -- Write EA_L -> B

        -- Stack Pointer operations
        ESS_LDSP_1,       -- LD SP,#nn: fetch TMP_H
        ESS_LDSP_2,       -- SP <- TMP
        ESS_LDSP_AB,      -- SP <- A:B
        ESS_STSP_WB,      -- ST SP_L/H,A: route SP through EA adder -> A

        -- I/O
        ESS_IO_FETCH,     -- Fetch port # -> TMP_L
        ESS_IO_SETUP,     -- Clear TMP for indirect [B] addressing
        ESS_IN_READ,      -- IO_RE, MDR <- port
        ESS_IN_WB,        -- A <- MDR, update Z
        ESS_OUT_WRITE,    -- IO_WE, port <- A

        -- Miscellaneous
        ESS_SKIP_BYTE,    -- Advance PC past one operand byte (branch-not-taken)
        ESS_HALT,         -- Processor halted

        -- Pipeline: load TMP from pre-fetched operand registers (r_exec_op1/op2)
        -- Used by 3-byte instructions (LD/ST [nn], JP nn, etc.) to load TMP without
        -- an extra memory read cycle.  Two sequential states load low then high byte.
        ESS_TMP_FROM_OP1, -- Load TMP[7:0]  from r_exec_op1 (low byte of 16-bit address)
        ESS_TMP_FROM_OP2  -- Load TMP[15:8] from r_exec_op2 (high byte); then → next ESS
    );

    -- =========================================================================
    -- IF/ID Pipeline Register
    -- =========================================================================
    type IF_ID_reg_t is record
        valid  : std_logic;   -- '1' when register holds a valid fetched opcode
        opcode : data_vector; -- Instruction byte latched from memory
    end record;

    constant NOP_IF_ID : IF_ID_reg_t := (
        valid  => '0',
        opcode => x"00"
    );

    -- =========================================================================
    -- ID/EX Pipeline Register
    -- =========================================================================
    type ID_EX_reg_t is record
        valid     : std_logic;    -- '1' when register holds a decoded instruction
        opcode    : data_vector;  -- Original opcode (used by ESS dispatch)
        op1       : data_vector;  -- First operand byte  (2-byte instructions)
        op2       : data_vector;  -- Second operand byte (3-byte instructions)
        ctrl      : control_bus_t; -- Pre-decoded control word (single-cycle exec)
        writes_a  : std_logic;    -- Hazard tag: instruction writes register A
        writes_b  : std_logic;    -- Hazard tag: instruction writes register B
        reads_a   : std_logic;    -- Hazard tag: instruction reads register A
        reads_b   : std_logic;    -- Hazard tag: instruction reads register B
        is_single : std_logic;    -- '1' = single-cycle execution (ctrl is used directly)
        is_multi  : std_logic;    -- '1' = multi-cycle execution (ESS FSM takes over)
    end record;

    constant NOP_ID_EX : ID_EX_reg_t := (
        valid     => '0',
        opcode    => x"00",
        op1       => x"00",
        op2       => x"00",
        ctrl      => INIT_CTRL_BUS,
        writes_a  => '0',
        writes_b  => '0',
        reads_a   => '0',
        reads_b   => '0',
        is_single => '0',
        is_multi  => '0'
    );

end package Pipeline_pkg;
