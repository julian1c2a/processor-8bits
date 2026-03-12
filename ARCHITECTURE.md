# Arquitectura del Procesador de 8 bits

Este documento describe la arquitectura interna del procesador: jerarquía de módulos, pipeline, flujo de señales entre subsistemas, propagación de flags y funcionamiento de las sub-máquinas de estado DSS/ESS.

---

## Jerarquía de Módulos

```text
Processor_Top (structural)
├── ControlUnit   — pipeline IF | DECODE | EXEC | WB
├── AddressPath   — PC, SP, LR, EAR, TMP; sumador EA 16-bit
└── DataPath      — banco registros 8×8, ALU, MDR, RegF
```

Los paquetes de soporte se usan así:

```text
Utils_pkg
  └── CONSTANTS_pkg           ← ceil_log2(NUM_REGISTERS) → REG_SEL_WIDTH
        └── ALU_pkg
        └── DataPath_pkg
        └── AddressPath_pkg
        └── ControlUnit_pkg   → control_bus_t (palabra de control completa)
              └── Pipeline_pkg  → IF_ID_reg_t, ID_EX_reg_t, dss_t, ess_t
```

---

## Pipeline de 4 Etapas

Cada ciclo de reloj avanza las cuatro etapas simultáneamente:

| Etapa | Ciclo | Qué ocurre |
|---|---|---|
| **IF** (Instruction Fetch) | N | `AddressBus ← PC`; memoria devuelve el byte de opcode; `PC++`. La UC registra ese byte en el registro de pipeline **IF/ID**. |
| **DECODE** (ID) | N+1 | La UC decodifica el opcode del IF/ID: calcula `ctrl` (control_bus_t), etiquetas de hazard (`reads_a/b`, `writes_a/b`) y `is_single`/`is_multi`. Si la instrucción tiene operandos, la sub-máquina **DSS** gestiona su fetch byte a byte (ver §DSS). Todo se recoge en el registro **ID/EX**. |
| **EXEC** (EX) | N+2 | Se aplica la micro-operación al DataPath y al AddressPath. Para instrucciones de un ciclo (`is_single=1`) se usa directamente `ID_EX.ctrl`. Para multi-ciclo (`is_multi=1`) la sub-máquina **ESS** toma el control (ver §ESS). |
| **WB** (Write-Back) | N+2 | En la misma fase EXEC, los registros de destino se actualizan al final del ciclo (dentro del mismo proceso síncrono). No existe un ciclo WB dedicado aparte. |

### Diagrama de Tiempo

```
Ciclo:  1       2       3       4       5
        ┌───────┬───────┬───────┬───────┬───────
clk  ───┘       └───────┘       └───────┘
        │ IF:I0 │ IF:I1 │ IF:I2 │ IF:I3 │ ...
        │       │ ID:I0 │ ID:I1 │ ID:I2 │ ...
        │       │       │EX/WB:I0│EX/WB:I1│ ...
```

Para instrucciones multi-ciclo (ej. `LD [nn],A` = 4 ciclos), la UC inserta burbujas en la etapa IF/DECODE gestionando `r_stall` y desactivando `PC++` mientras el ESS no llegue a `ESS_IDLE`.

---

## Flujo de Señales Internas

```
                 ┌──────────────────────────────────────────────────┐
MemData_In  ────►│ ControlUnit                                       │
                 │  ├ IF/ID reg                                       │
                 │  ├ ID/EX reg  (ctrl, opcode, op1, op2, hazard)    │
                 │  ├ DSS FSM   → controla fetch de operandos        │
                 │  └ ESS FSM   → emite control_bus_t multi-ciclo    │
                 │            ↓ s_CtrlBus (control_bus_t)            │
                 └──────────────────────────────────────────────────┘
                              │                    │
                              ▼                    ▼
              ┌───────────────────┐   ┌────────────────────────┐
              │    DataPath       │   │    AddressPath         │
              │  ┌─ BancoReg 8×8 │   │  ┌─ PC (16b)          │
              │  ├─ ALU  8b      │   │  ├─ SP (16b)          │
              │  ├─ MDR          │   │  ├─ EAR (16b)         │
              │  └─ RegF (flags) │   │  ├─ TMP (16b)         │
              └───────┬───────────┘   │  └─ EA Adder (16b)   │
                      │               └────────────┬───────────┘
                      │ s_Flags                    │ s_AddressPath_EA
                      └────────────────────────────┘
                                          │
                                      Processor_Top
```

### Señales Clave entre Subsistemas

| Señal | Origen → Destino | Propósito |
|---|---|---|
| `s_CtrlBus` | ControlUnit → DataPath + AddressPath | Palabra de control completa (~30 campos ortogonales) emitida cada ciclo |
| `s_Flags` | DataPath → ControlUnit | Registro F (C,H,V,Z,G,E,L,R) para evaluación de condiciones de salto |
| `s_DataPath_IndexB` | DataPath.R1 → AddressPath | Registro B como índice para modos `[nn+B]` y `[B]` |
| `s_DataPath_RegA` | DataPath.R0 → AddressPath | Registro A para el par `A:B` en instrucciones de 16 bits |
| `s_AddressPath_PC` | AddressPath.PC → DataPath | PC actual para que `CALL`/`BSR` guarden la dirección de retorno |
| `s_AddressPath_EA` | AddressPath.EA_Adder → DataPath | Resultado del sumador EA 16 bits para `ADD16`/`SUB16` y `ST SP` |
| `s_AddressPath_Flags` | AddressPath.EA → DataPath.RegF | Flags C y Z del sumador de 16 bits para `ADD16`/`SUB16` |

El bus de datos externo `MemData_In` llega **simultáneamente** a `ControlUnit.InstrIn`, `AddressPath.DataIn` y `DataPath.MemDataIn`. La UC determina en qué ciclo ese byte es un opcode (etapa IF) o un operando (etapas DECODE/EXEC) a través de los registros de pipeline.

---

## Registro de Flags (RegF)

### Codificación (bit 7 → bit 0)

| Bit | Nombre | Descripción |
|-----|--------|-------------|
| 7 | **C** | Carry / no-Borrow (en SUB: C=1 significa que NO hubo borrow) |
| 6 | **H** | Half-Carry (carry entre nibble bajo y alto; útil para BCD) |
| 5 | **V** | Overflow (desbordamiento con signo, complemento a dos) |
| 4 | **Z** | Zero (resultado == 0) |
| 3 | **G** | Greater-than con signo |
| 2 | **E** | Equal |
| 1 | **L** | Less-than con signo |
| 0 | **R** | Bit desplazado hacia la derecha (fuente: shift); también bit destino de `SET`/`CL` |

### Estrategia de Actualización Enmascarada

`RegF` nunca se sobreescribe completo. La UC emite siempre `Flag_Mask` junto a `Write_F`:

```
new_RegF[i] = Write_F AND Flag_Mask[i]
              ? (F_Src_Sel=0 ? ALU_Stat[i] : EA_Flags[i])
              : RegF[i]   -- bit no afectado: se preserva
```

- `F_Src_Sel = 0` → fuente: ALU_Stat (instrucciones aritméticas/lógicas de 8 bits).
- `F_Src_Sel = 1` → fuente: EA_Flags del sumador AddressPath (instrucciones `ADD16`/`SUB16`).
- `Load_F_Direct = 1` → carga completa sin máscara: usado en `POP F` y `RTI` para restaurar el estado exacto guardado en pila.

---

## Sub-Máquina DSS (Decode Sub-State)

Gestiona el fetch de operandos durante la etapa DECODE. Tiene **3 estados**:

| Estado | Descripción |
|--------|-------------|
| `DSS_OPCODE` | Ciclo inicial: se procesa el opcode (1 byte ya disponible en IF/ID). Para instrucciones de 1 byte la decodificación finaliza aquí. |
| `DSS_OP1` | Se está leyendo el primer byte de operando (PC++ y espera hit de memoria). Usado en instrucciones de 2 y 3 bytes. |
| `DSS_OP2` | Se está leyendo el segundo byte de operando. Exclusivo de instrucciones de 3 bytes (`LD A,[nn]`, `ST [nn],A`, `JP nn`, `CALL nn`, etc.). |

Cuando el DSS llega a `DSS_OP2` (o a `DSS_OP1` para 2 bytes), activa el latch del byte en `ID_EX.op1` / `ID_EX.op2` y retorna a `DSS_OPCODE` en el siguiente ciclo.

---

## Sub-Máquina ESS (Execute Sub-State)

Gestiona la ejecución multi-ciclo. El estado de reposo es `ESS_IDLE`. Al llegar una instrucción con `is_multi=1`, el ESS toma el control y emite señales de micro-operación hasta completar la secuencia.

### Grupos de Estados

| Grupo | Estados | Secuencia típica |
|-------|---------|-----------------|
| **Fetch aux** | `ESS_ADDR_HI`, `ESS_PZ_FETCH`, `ESS_INDB_SETUP` | Ensambla la dirección efectiva en TMP antes de acceder a memoria |
| **Load** | `ESS_LD_ABS`, `ESS_LD_IDX`, `ESS_LD_WB` | Lee de memoria hacia MDR, luego escribe MDR en el registro destino |
| **Store** | `ESS_ST_ABS`, `ESS_ST_IDX` | Escribe el registro fuente en la dirección calculada |
| **PUSH** | `ESS_PUSH_1..3` | SP−=2, escribe byte bajo en M[SP], byte alto en M[SP+1] |
| **POP** | `ESS_POP_1..2`, `ESS_POP_F_2`, `ESS_POP_AB_2..3` | Lee M[SP] en MDR, escribe en destino (registro, F, o par A:B), SP+=2 |
| **CALL** | `ESS_CALL_1..6` | Fetch destino (2 bytes), SP−=2, push retorno (2 bytes), salta |
| **RET** | `ESS_RET_1..3` | Pop dirección (2 bytes desde pila), PC←TMP, SP+=2 |
| **RTI** | `ESS_RTI_1..4` | Pop F, pop PC (reutiliza RET_1..3 para los últimos 3 ciclos) |
| **INT** | `ESS_INT_1..9` | Push PC (2 bytes) + push F (2 bytes) + fetch vector (2 bytes) + salto |
| **Branch** | `ESS_BRANCH_2`, `ESS_JP_3`, `ESS_JP_AB`, `ESS_JPN_2` | Calcula PC+rel8 o carga TMP en PC |
| **Indirect** | `ESS_IND_LOAD`, `ESS_IND_READ_L`, `ESS_IND_READ_H` | Lee puntero de 16 bits desde memoria, luego salta |
| **OP16** | `ESS_OP16_IMM8`, `ESS_OP16_FETCH1`, `ESS_OP16_WB1`, `ESS_OP16_WB2` | Operaciones aritméticas de 16 bits sobre el par A:B |
| **SP ops** | `ESS_LDSP_1..2`, `ESS_LDSP_AB`, `ESS_STSP_WB` | Carga/guarda el Stack Pointer |
| **I/O** | `ESS_IO_FETCH`, `ESS_IO_SETUP`, `ESS_IN_READ`, `ESS_IN_WB`, `ESS_OUT_WRITE` | Acceso a puertos de entrada/salida de 8 bits |
| **Misc** | `ESS_SKIP_BYTE`, `ESS_HALT` | Avanza PC (branch-not-taken con operando de 1 byte); detiene el núcleo |

### Diagrama de Transiciones ESS (extracto principal)

```
                    ┌────────────┐
             reset  │            │
              ────► │  ESS_IDLE  │ ◄─────────────────────────────────┐
                    └─────┬──────┘                                    │
         is_multi=1        │                                           │
    ┌──────────────────────┴────────────────────────────────┐         │
    │                                                       │         │
    ▼                           ▼                           ▼         │
LD abs            CALL                    PUSH             INT        │
  ADDR_HI           CALL_1→CALL_2           PUSH_1           INT_1..9 │
  LD_ABS            CALL_3..5               PUSH_2..3        ────────►┘
  LD_WB ──────────► ESS_IDLE                ESS_IDLE
```

La tabla de transiciones completa está implementada en `ControlUnit.vhdl` dentro del proceso `seq_proc`, sección "ESS transition table".

---

## Detección de Hazards

La UC detecta hazards RAW (Read After Write) comparando las etiquetas del ID/EX:

- Si `ID_EX.writes_a = '1'` y la instrucción siguiente tiene `reads_a = '1'`, se inserta una burbuja (stall de 1 ciclo).
- Lo mismo para el registro B (`writes_b` / `reads_b`).

No se implementa forwarding; la solución es conservadora (stall exacto de 1 ciclo cuando hay dependencia).

---

## Resumen de Archivos Fuente

| Archivo | Paquete/Entidad | Propósito |
|---------|-----------------|-----------|
| `Utils_pkg.vhdl` | `Utils_pkg` | `ceil_log2` para dimensionamiento en elaboración |
| `CONSTANTS_pkg.vhdl` | `CONSTANTS_pkg` | Constantes globales: `DATA_WIDTH`, `ADDRESS_WIDTH`, `REG_SEL_WIDTH`, … |
| `ALU_pkg.vhdl` | `ALU_pkg` | Opcodes de la ALU (`opcode_vector`), tipos de datos |
| `ALU_functions_pkg.vhdl` | `ALU_functions_pkg` | Implementación combinacional de las 29 operaciones de la ALU |
| `ALU.vhdl` | `ALU` | Entidad RTL que instancia `ALU_functions_pkg` |
| `DataPath_pkg.vhdl` | `DataPath_pkg` | Constantes de control del DataPath (`BUS_OP_*`, `OUT_SEL_*`) |
| `DataPath.vhdl` | `DataPath` | Banco de registros, instancia ALU, MDR, RegF |
| `AddressPath_pkg.vhdl` | `AddressPath_pkg` | Constantes de control del AddressPath (`PC_OP_*`, `ABUS_SRC_*`, …) |
| `AddressPath.vhdl` | `AddressPath` | PC, SP, LR, EAR, TMP, sumador EA |
| `ControlUnit_pkg.vhdl` | `ControlUnit_pkg` | Tipo `control_bus_t` y constante `INIT_CTRL_BUS` |
| `Pipeline_pkg.vhdl` | `Pipeline_pkg` | Registros de pipeline `IF_ID_reg_t`, `ID_EX_reg_t`; enumeraciones `dss_t`, `ess_t` |
| `ControlUnit.vhdl` | `ControlUnit` | Lógica de control: pipeline de 4 etapas, DSS, ESS, hazards |
| `Processor_Top.vhdl` | `Processor_Top` | Top-level estructural: interconecta los tres subsistemas |

---

## Documentación Adicional

| Archivo | Contenido |
|---------|-----------|
| [ISA.md](ISA.md) | Conjunto de instrucciones completo (formatos, modos de direccionamiento, ciclos) |
| [ALU.md](ALU.md) | Descripción detallada de las 29 operaciones de la ALU y sus flags |
| [processor/AddressPath.md](processor/AddressPath.md) | Subsistema de 16 bits: registros, sumador EA, multiplexor de bus |
| [processor/DataPath.md](processor/DataPath.md) | Subsistema de 8 bits: banco de registros, MDR, RegF |
| [processor/Processor_Top.md](processor/Processor_Top.md) | Señales internas, mapa de memoria y puertos externos |
| [testbenchs/README-TB.md](testbenchs/README-TB.md) | Guía de ejecución de los bancos de prueba |
