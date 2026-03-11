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
        clk         : in  std_logic;
        reset       : in  std_logic;

        -- External Memory Interface
        MemAddress  : out address_vector;
        MemData_In  : in  data_vector;
        MemData_Out : out data_vector;
        Mem_WE      : out std_logic;
        Mem_RE      : out std_logic;

        -- External IO Interface (simplificado, comparte buses)
        IO_WE       : out std_logic;
        IO_RE       : out std_logic
    );
end entity Processor_Top;

architecture Structural of Processor_Top is

    -- Component Configurations
    for all : DataPath_comp    use entity work.DataPath(unique);
    for all : AddressPath_comp use entity work.AddressPath(unique);
    for all : ControlUnit_comp use entity work.ControlUnit(unique);

    -- =========================================================================
    -- Señales de Interconexión Interna
    -- =========================================================================
    signal s_CtrlBus    : control_bus_t;
    signal s_Flags      : status_vector;
    signal s_AddressBus : address_vector;
    signal s_DataPath_DataOut : data_vector;
    signal s_DataPath_IndexB  : data_vector;
    signal s_DataPath_RegA    : data_vector; -- Nuevo: Salida A
    signal s_AddressPath_PC   : address_vector; -- PC del AddressPath al DataPath
    signal s_AddressPath_EA   : address_vector; -- Nuevo: Resultado EA
    signal s_AddressPath_Flags: status_vector;  -- Nuevo: Flags EA

begin

    -- ========================================================================
    -- 1. Instantiation of the Control Unit (The Brain)
    -- ========================================================================
    -- La UC recibe el byte de instrucción y los flags, y emite todas las señales de control.
    Inst_UC: ControlUnit_comp
        Port map (
            clk      => clk,
            reset    => reset,
            FlagsIn  => s_Flags,
            InstrIn  => MemData_In, -- El byte de instrucción viene del bus de datos de memoria
            CtrlBus  => s_CtrlBus
        );

    -- ========================================================================
    -- 2. Instantiation of the Address Path (16-bit operations)
    -- ========================================================================
    -- Gestiona PC, SP, LR, y calcula direcciones efectivas.
    Inst_AddrPath: AddressPath_comp
        Port map (
            clk          => clk,
            reset        => reset,
            DataIn       => MemData_In, -- Para cargar TMP desde memoria (ej. JP nn)
            Index_B      => s_DataPath_IndexB, -- Desde RegB del DataPath
            Index_A      => s_DataPath_RegA,   -- Desde RegA del DataPath
            AddressBus   => s_AddressBus,
            PC_Out       => s_AddressPath_PC, -- Exportar PC para CALL/PUSH
            EA_Out       => s_AddressPath_EA, -- Resultado operación 16-bit
            EA_Flags     => s_AddressPath_Flags,
            -- Señales de control desde la UC
            PC_Op        => s_CtrlBus.PC_Op,
            SP_Op        => s_CtrlBus.SP_Op,
            ABUS_Sel     => s_CtrlBus.ABUS_Sel,
            Load_LR      => s_CtrlBus.Load_LR,
            Load_EAR     => s_CtrlBus.Load_EAR,
            Load_TMP_L   => s_CtrlBus.Load_TMP_L,
            Load_TMP_H   => s_CtrlBus.Load_TMP_H,
            Load_Src_Sel => s_CtrlBus.Load_Src_Sel,
            Clear_TMP    => s_CtrlBus.Clear_TMP,
            SP_Offset    => s_CtrlBus.SP_Offset,
            EA_A_Sel     => s_CtrlBus.EA_A_Sel,
            EA_B_Sel     => s_CtrlBus.EA_B_Sel
            EA_Op        => s_CtrlBus.EA_Op
        );

    -- ========================================================================
    -- 3. Instantiation of the Data Path (8-bit operations)
    -- ========================================================================
    -- Gestiona el banco de registros (A, B, R2-R7), la ALU, y el MDR.
    Inst_DataPath: DataPath_comp
        Port map (
            clk       => clk,
            reset     => reset,
            MemDataIn => MemData_In,
            MemDataOut=> s_DataPath_DataOut,
            IndexB_Out=> s_DataPath_IndexB, -- Salida de RegB para el AddressPath
            RegA_Out  => s_DataPath_RegA,
            PC_In     => s_AddressPath_PC,  -- Entrada de PC desde AddressPath
            FlagsOut  => s_Flags,
            -- Señales de control desde la UC
            ALU_Op    => s_CtrlBus.ALU_Op,
            Bus_Op    => s_CtrlBus.Bus_Op,
            Write_A   => s_CtrlBus.Write_A,
            Write_B   => s_CtrlBus.Write_B,
            Reg_Sel   => s_CtrlBus.Reg_Sel,
            Write_F   => s_CtrlBus.Write_F,
            Flag_Mask => s_CtrlBus.Flag_Mask,
            MDR_WE    => s_CtrlBus.MDR_WE,
            ALU_Bin_Sel => s_CtrlBus.ALU_Bin_Sel,
            Out_Sel   => s_CtrlBus.Out_Sel
        );

    -- ========================================================================
    -- 4. Top-Level Connections
    -- ========================================================================
    
    -- El Bus de Direcciones es controlado por el Address Path
    MemAddress <= s_AddressBus;
    
    -- El Bus de Datos de salida es controlado por el Data Path
    MemData_Out <= s_DataPath_DataOut;

    -- Las señales de control de Memoria e I/O vienen directamente de la UC
    Mem_WE <= s_CtrlBus.Mem_WE;
    Mem_RE <= s_CtrlBus.Mem_RE;
    IO_WE  <= s_CtrlBus.IO_WE;
    IO_RE  <= s_CtrlBus.IO_RE;

end architecture Structural;