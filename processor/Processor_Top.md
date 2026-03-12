# Processor Top Level

La entidad `Processor_Top` integra los subsistemas principales para formar el núcleo completo del procesador. Implementa la arquitectura de **Doble Datapath** con **pipeline de 4 etapas** descrita en la ISA v0.7.

## Archivos relevantes

| Archivo | Descripción |
|---|---|
| `processor/Processor_Top.vhdl` | Top level estructural |
| `processor/ControlUnit.vhdl` | Unidad de Control — pipeline de 4 etapas |
| `processor/Pipeline_pkg.vhdl` | Tipos de registros de pipeline (IF/ID, ID/EX) |
| `processor/ControlUnit_pkg.vhdl` | Tipo `control_bus_t` y constante `INIT_CTRL_BUS` |
| `processor/DataPath.vhdl` | Data Path de 8 bits |
| `processor/AddressPath.vhdl` | Address Path de 16 bits |

## Estructura del Sistema

El diseño separa limpiamente el flujo de datos (8 bits) del flujo de control/direcciones (16 bits), orquestados por una Unidad de Control con pipeline de 4 etapas.

### Jerarquía

```text
Processor_Top (Structural)
├── ControlUnit   — pipeline FETCH|DECODE|EXEC|WB; usa Pipeline_pkg
├── AddressPath   — PC, SP, LR, EAR, TMP; sumador EA 16-bit
└── DataPath      — banco registros 8×8, ALU, MDR, flags
```

## Interconexión Interna

| Señal interna | De → A | Descripción |
|---|---|---|
| `s_CtrlBus` | ControlUnit → DataPath, AddressPath | Palabra de control completa (`control_bus_t`): ~30 campos ortogonales |
| `s_Flags` | DataPath → ControlUnit | Registro F (C,H,V,Z,G,E,R,L) para saltos condicionales |
| `s_DataPath_IndexB` | DataPath → AddressPath | Valor de R1 (B) para modos indexados `[nn+B]` y `[B]` |
| `s_DataPath_RegA` | DataPath → AddressPath | Valor de R0 (A) para operaciones 16-bit (`A:B`) |
| `s_AddressPath_PC` | AddressPath → DataPath | PC actual para `OUT_SEL_PCL`/`PCH` en `CALL` (push retorno) |
| `s_AddressPath_EA` | AddressPath → DataPath | Resultado del sumador EA para `ADD16`/`SUB16` y `ST SP` |
| `s_AddressPath_Flags` | AddressPath → DataPath | Flags de 16 bits (C,Z) para instrucciones `ADD16`/`SUB16` |

El bus de datos externo `MemData_In` llega simultáneamente a `ControlUnit.InstrIn`, `AddressPath.DataIn` y `DataPath.MemDataIn`. En el pipeline v0.7, la UC selecciona cuándo ese dato es un opcode (etapa FETCH) o un operando (etapa DECODE/EXEC) mediante los registros IF/ID e ID/EX.

## Interfaz Externa

| Puerto | Dir | Ancho | Descripción |
| --- | --- | --- | --- |
| `clk` | IN | 1 | Reloj del sistema |
| `reset` | IN | 1 | Reset global síncrono (activo alto) |
| `MemAddress` | OUT | 16 | Dirección al bus de memoria |
| `MemData_In` | IN | 8 | Dato leído de memoria (opcode u operando) |
| `MemData_Out` | OUT | 8 | Dato a escribir en memoria (`ST`, `PUSH`, `CALL`) |
| `Mem_WE` | OUT | 1 | Write enable memoria |
| `Mem_RE` | OUT | 1 | Read enable memoria |
| `Mem_Ready` | IN | 1 | Handshake: `1` = dato válido / escritura aceptada (wait states) |
| `IO_WE` | OUT | 1 | Write enable espacio I/O |
| `IO_RE` | OUT | 1 | Read enable espacio I/O |
| `IRQ` | IN | 1 | Interrupt Request (enmascarable, flag `I`) |
| `NMI` | IN | 1 | Non-Maskable Interrupt (prioridad máxima) |

## Mapa de Memoria (Resumen)

| Rango | Uso |
|---|---|
| `0x0000` | Vector de reset (ejecución comienza aquí) |
| `0x0001–0xFF` | Página cero (acceso rápido con `[n]`) |
| `0x0100–0xFFF9` | Memoria general de programa/datos |
| `0xFFFA–0xFFFB` | Vector NMI (low, high) |
| `0xFFFC–0xFFFD` | Reservado |
| `0xFFFE–0xFFFF` | Vector IRQ (low, high); SP inicial = `0xFFFE` |

El espacio I/O (256 puertos) es independiente del mapa de memoria y se accede exclusivamente con `IN`/`OUT`.
