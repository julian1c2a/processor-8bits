# Plan: Simulador / Ensamblador Interactivo — ISA v0.7

> Documento de diseño previo a la codificación.
> Fecha: 13 de marzo de 2026.

---

## 1. Propósito y Alcance

Construir un **emulador + ensamblador en línea de comandos** para la ISA v0.7 del
procesador de 8 bits. El usuario puede:

1. **Modo REPL** — introducir una instrucción ensamblador, que se ensambla y
   ejecuta inmediatamente, y ver cómo evolucionan los registros, flags y la memoria.
2. **Modo Programa** — introducir varias instrucciones que se almacenan a partir
   de una dirección inicial; después ejecutarlas con visualización paso a paso.

El simulador es **software puro** (no necesita GHDL): modela exactamente la
semántica de la ISA (registros, flags, modos de direccionamiento, interrupciones).

---

## 2. Lenguaje y Entorno

| Criterio | Elección | Justificación |
|---|---|---|
| Lenguaje | **Python ≥ 3.10** | `alu_ref.py` ya existe; sin dependencias externas; portable. |
| Dependencias | stdlib solo | `re`, `cmd`, `textwrap`, `struct`, `sys` — nada que instalar. |
| Ubicación | `sim/` dentro del repo | No contamina el árbol de archivos VHDL. |
| Ejecución | `python -m sim` | Punto de entrada estándar con `sim/__main__.py`. |

---

## 3. Arquitectura de Módulos

```
sim/
├── __main__.py         ← punto de entrada: instancia CLI y lanza el loop
├── assembler.py        ← texto ensamblador → lista de bytes (+ metadatos)
├── cpu.py              ← estado de la CPU + ciclo de ejecución
├── display.py          ← renderizado de estado, diff, tabla de memoria
└── cli.py              ← loop interactivo con los dos modos
```

Dependencias entre módulos (sin ciclos):

```
__main__ → cli → assembler
                → cpu
                → display
         display → cpu   (solo lectura de estado)
```

---

## 4. Módulo `cpu.py` — Estado y Ejecución

### 4.1 Clase `CPU`

```python
class CPU:
    # Registros visibles
    A:  int   # 8 bits
    B:  int   # 8 bits
    PC: int   # 16 bits
    SP: int   # 16 bits, inicia 0xFFFE
    F:  int   # 8 bits  — bits: C H V Z G E R L
    LR: int   # 16 bits

    # Flag de interrupción (interno, no parte de F)
    I:  bool

    # Memoria (64 KB)
    mem: bytearray  # bytearray(65536)

    # Espacio I/O simulado (256 puertos)
    io: bytearray   # bytearray(256)

    # Ciclos consumidos por la última instrucción
    cycles: int
```

### 4.2 Codificación del registro F

| Bit | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|-----|---|---|---|---|---|---|---|---|
| Símbolo | C | H | V | Z | G | E | R | L |

Constantes de máscara:

```python
F_C = 0x80; F_H = 0x40; F_V = 0x20; F_Z = 0x10
F_G = 0x08; F_E = 0x04; F_R = 0x02; F_L = 0x01
```

### 4.3 Método `step() → dict`

Ejecuta **una** instrucción a partir de `PC`. Devuelve un `dict` con el diff de
estado (solo los campos que cambiaron):

```python
{ "A": (old, new), "F": (old, new), "mem": [(addr, old, new), ...], ... }
```

### 4.4 Modelo de semántica

Para cada opcode se implementa exactamente lo que dice la ISA.md §7. El modelo
no intenta ser ciclo-preciso (no simula el pipeline); simula el **efecto
arquitectural** de cada instrucción (registros + flags + memoria).

Las instrucciones de interrupción (`IRQ`/`NMI`) se simulan con comandos
explícitos de la CLI (`irq` / `nmi`) en lugar de señales hardware.

**Instrucciones cubiertas en v1.0** (cobertura completa de ISA v0.7):

| Grupo | Mnemonics |
|-------|-----------|
| Sistema | `NOP`, `HALT`, `SEC`, `CLC`, `SEI`, `CLI`, `RTI` |
| Carga A | `LD A, B/\#n/[n]/[nn]/[B]/[nn+B]/[n+B]` |
| Carga B | `LD B, A/\#n/[n]/[nn]/[B]/[nn+B]` |
| Store A | `ST A, [n]/[nn]/[B]/[nn+B]/[n+B]` |
| Store B | `ST B, [n]/[nn]/[nn+B]` |
| Stack Pointer | `LD SP, \#nn` / `LD SP, A:B` / `ST SP_L, A` / `ST SP_H, A` |
| Push/Pop | `PUSH A/B/F/A:B` · `POP A/B/F/A:B` |
| Saltos | `JP nn` · `JR rel8` · `JPN page8` · `JP ([nn])` · `JP A:B` |
| Llamadas | `CALL nn` · `CALL ([nn])` · `RET` · `BSR rel8` · `RET LR` · `CALL LR, nn` |
| Condicionales | `BEQ~BEQ2` (12 variantes, opcodes 0x80–0x8B) |
| ALU reg | `ADD/ADC/SUB/SBB/AND/OR/XOR/CMP/MUL/MUH` |
| ALU imm | `ADD\#/ADC\#/SUB\#/SBB\#/AND\#/OR\#/XOR\#/CMP\#` |
| ALU mem | `ADD[n~nn+B]/SUB[...]/AND/OR/XOR/CMP (12 0xBx)` |
| Unarios | `NOT/NEG/INC/DEC/INC B/DEC B/CLR/SET/LSL/LSR/ASL/ASR/ROL/ROR/SWAP` |
| I/O | `IN A, \#n` · `IN A, [B]` · `OUT \#n, A` · `OUT [B], A` |
| 16 bits | `ADD16 \#n/\#nn` · `SUB16 \#n/\#nn` |

---

## 5. Módulo `assembler.py` — Sintaxis de Entrada

### 5.1 Gramática informal

```
instruction ::= mnemonic [ operand ( "," operand )* ]
mnemonic    ::= [A-Za-z][A-Za-z0-9_]*
operand     ::= "#" number           ; inmediato
              | "[" ( number | reg "+" reg | reg ) "]"   ; memoria
              | "(" "[" number "]" ")"                   ; indirecto absoluto
              | reg                  ; registro simple
              | number               ; para rel8/page8/nn (según contexto)
reg         ::= "A" | "B" | "F" | "SP" | "LR" | "A:B" | "SP_L" | "SP_H"
number      ::= "0x" [0-9A-Fa-f]+   ; hexadecimal
              | "0b" [01]+           ; binario
              | [0-9]+               ; decimal
```

Sintaxis case-insensitive. Espacios libres alrededor de comas y corchetes.

### 5.2 Tabla de resolución mnemónico → opcode

El ensamblador usa una tabla plana (diccionario de patrones regex o tuplas de
matching):

| Patrón de entrada | Opcode | Bytes emitidos |
|---|---|---|
| `NOP` | 0x00 | `[0x00]` |
| `HALT` | 0x01 | `[0x01]` |
| `LD A, #n` | 0x11 | `[0x11, n]` |
| `LD A, [n]` | 0x12 | `[0x12, n]` |
| `LD A, [nn]` | 0x13 | `[0x13, lo(nn), hi(nn)]` |
| `LD A, B` | 0x10 | `[0x10]` |
| `LD A, [B]` | 0x14 | `[0x14]` |
| `LD A, [nn+B]` | 0x15 | `[0x15, lo(nn), hi(nn)]` |
| `LD A, [n+B]` | 0x16 | `[0x16, n]` |
| … (resto completo de §7) | … | … |
| `ADD16 #n` | 0xE0 | `[0xE0, n]` |
| `ADD16 #nn` | 0xE1 | `[0xE1, lo(nn), hi(nn)]` |
| `SUB16 #n` | 0xE2 | `[0xE2, n]` |
| `SUB16 #nn` | 0xE3 | `[0xE3, lo(nn), hi(nn)]` |

Todos los operandos de 16 bits se emiten **little-endian** (byte bajo primero).

### 5.3 Resolución de etiquetas

En modo programa el ensamblador es de **dos pasadas**:

- Pasada 1: asigna dirección a cada instrucción y registra etiquetas.
- Pasada 2: resuelve referencias a etiquetas en operandos (`JP label`,
  `BEQ label`, `BSR label`).

Las etiquetas se definen con `nombre:` al principio de la línea (opcionalmente
en línea propia).

### 5.4 Tipo de retorno

```python
@dataclass
class AsmResult:
    bytes:   list[int]        # bytes a escribir en memoria
    size:    int              # longitud en bytes
    mnemonic: str             # texto normalizado para display
    opcode:  int              # opcode principal
    error:   str | None       # mensaje de error, None si OK
```

---

## 6. Módulo `display.py` — Formato de Salida

### 6.1 Cabecera de estado de registros

```
A=0x42  B=0x07  PC=0x0005  SP=0x01FE  LR=0x0000  I=1
F=0x10  [ C:0 H:0 V:0 Z:1 G:0 E:0 R:0 L:0 ]
```

### 6.2 Diff tras ejecutar una instrucción

Solo se muestran los valores que **cambiaron** (en color si el terminal lo admite):

```
  LD A, #0x42        (opcode 0x11 · 2 bytes · 2 ciclos)
  ─────────────────────────────────────────
  A : 0x00 → 0x42
  F : 0x00 → 0x00   (sin cambio de flags relevante)
  PC: 0x0000 → 0x0002
```

Cambios en memoria:

```
  ST A, [0x0100]     (opcode 0x31 · 3 bytes · 4 ciclos)
  ─────────────────────────────────────────
  mem[0x0100] : 0x00 → 0x42
  PC          : 0x0002 → 0x0005
```

### 6.3 Vista de memoria (`mem` command)

```
         00 01 02 03 04 05 06 07  08 09 0A 0B 0C 0D 0E 0F
0x0100:  42 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  B...............
```

Formato estilo `xxd` de 16 bytes por línea, columna ASCII a la derecha.

### 6.4 Listado de programa (modo programa, `list` command)

```
  Addr   Bytes        Mnemónico
  ─────────────────────────────────────────
  0x0200 [50 FF 01]   LD SP, #0x01FF
  0x0203 [04]         SEI
  0x0204 [01]         HALT
  0x0205 [01]         HALT
  0x0206 [01]         HALT
  ─────────────────────────────────────────
  5 instrucciones · 7 bytes · 0x0200–0x0206
```

### 6.5 Traza de ejecución paso a paso (modo programa, `run` / `step`)

Para cada instrucción ejecutada:

```
  [0x0200] LD SP, #0x01FF   SP: 0xFFFE → 0x01FF   (2 ciclos)
  [0x0203] SEI               I:  0 → 1              (2 ciclos)
  [0x0204] HALT              <procesador detenido — esperando IRQ/NMI>
```

Si se llega a `HALT`, el simulador pausa y espera que el usuario escriba
`irq` o `nmi` para reanudar la ejecución.

---

## 7. Módulo `cli.py` — Interfaz de Usuario

### 7.1 Prompt y modos

| Modo | Prompt | Descripción |
|---|---|---|
| REPL | `(asm) >` | Instrucción única, ensambla+ejecuta al instante |
| Programa | `(prog 0xNNNN) >>` | Acumula instrucciones; muestra dirección actual |
| Paso a paso | `(step 0xNNNN) >>` | Durante `run`, pausa entre instrucciones |

### 7.2 Comandos del modo REPL

| Comando | Descripción |
|---|---|
| `<instrucción>` | Ensambla y ejecuta. Muestra diff de estado. |
| `program [addr]` | Entra en modo programa. `addr` por defecto `0x0000`. |
| `regs` | Muestra todos los registros y flags. |
| `mem <addr> [n]` | Vuelca `n` bytes desde `addr` (por defecto 64). |
| `io [port]` | Muestra espacio I/O. Sin arg: todos los puertos ≠ 0. |
| `set <reg> <val>` | Modifica un registro directamente (`set A 0x42`, `set SP 0x01FF`). |
| `write <addr> <bytes...>` | Escribe bytes directamente en memoria (`write 0x50 0x11 0x42`). |
| `reset` | Reinicia la CPU (A=B=0, PC=0x0000, SP=0xFFFE, F=0, I=0). Memoria no se borra. |
| `clrmem` | Borra toda la memoria (bytearray de ceros). |
| `load <archivo.asm>` | Carga y ensambla un fichero `.asm` en memoria desde la dirección indicada en el fichero (o `0x0000`). |
| `save <archivo.asm>` | Guarda el buffer de programa actual como fichero `.asm`. |
| `irq` | Solicita una interrupción IRQ al simulador. |
| `nmi` | Solicita una interrupción NMI al simulador. |
| `help [cmd]` | Ayuda general o de un comando concreto. |
| `quit` / `exit` | Salir. |

### 7.3 Comandos del modo Programa

Hereda todos los comandos del REPL más:

| Comando | Descripción |
|---|---|
| `<instrucción>` | Ensambla y **añade** la instrucción al buffer en la dirección actual. Avanza el cursor. |
| `<etiqueta>:` | Define una etiqueta en la dirección actual. |
| `list` | Muestra el buffer completo con `display.listing()`. |
| `run` | Carga el buffer en memoria, resetea PC a `start_addr` y ejecuta mostrando la traza completa. |
| `step` | Igual que `run` pero pausa después de cada instrucción (espera Enter). |
| `rewind` | Vuelve el cursor al inicio del buffer (para sobreescribir). |
| `delete [n]` | Elimina la última instrucción (o la instrucción número `n`). |
| `back` | Sale al modo REPL (conserva el buffer para continuar luego). |

### 7.4 Ciclo de vida de `run`

```
1. Copiar buffer de bytes al bytearray mem[] desde start_addr.
2. CPU.PC ← start_addr.
3. Bucle:
     snapshot_before = cpu.snapshot()
     result = cpu.step()
     diff = compare(snapshot_before, cpu.snapshot())
     display.step_trace(addr, mnemonic, diff, result.cycles)
     if cpu.halted:
         print "<HALT — escribe irq/nmi/quit>"
         esperar comando del usuario
     if cpu.PC >= end_addr or cpu.PC == start_addr (bucle infinito detectado):
         break
4. Mostrar estado final completo.
```

---

## 8. Ficheros `.asm` — Formato de Texto

Los ficheros de ensamblado usan el mismo formato que la línea de comandos:

```asm
; Comentarios con ;
; Directiva de origen:
.org 0x0200

    LD  SP, #0x01FF     ; inicializar pila
    SEI                 ; habilitar interrupciones
bucle:
    HALT                ; esperar IRQ
    JP  bucle           ; volver a esperar
```

Directivas reconocidas:

| Directiva | Descripción |
|---|---|
| `.org <addr>` | Establece el origen de la siguiente instrucción. |
| `.byte <v1>[, v2, ...]` | Emite bytes literales. |
| `.word <v1>[, v2, ...]` | Emite palabras de 16 bits little-endian. |

---

## 9. Manejo de Errores

| Situación | Respuesta |
|---|---|
| Mnemónico desconocido | `Error: instrucción desconocida: 'LDA'` — sugerencia si hay coincidencia cercana |
| Operando fuera de rango | `Error: offset 0x80 fuera de rango rel8 (−128..+127)` |
| Lectura de dirección no inicializada | Warning no fatal; devuelve `0x00` |
| División / overflow en `MUL` | El flag C se activa; resultado truncado a 8 bits normalmente |
| HALT sin IRQ/NMI disponible en `run` | Pausa con mensaje, aguarda comando |
| Fichero no encontrado en `load` | Mensaje de error, vuelve al prompt |

---

## 10. Estructura de Ficheros Final

```
sim/
├── __main__.py         ~  50 líneas   — arranque
├── assembler.py        ~ 400 líneas   — tabla de opcodes, parser, 2 pasadas
├── cpu.py              ~ 450 líneas   — estado CPU, execute(), ALU interna
├── display.py          ~ 200 líneas   — render registros, diff, hex dump
└── cli.py              ~ 350 líneas   — REPL + modo programa + comandos

Total estimado: ~1 450 líneas de Python.
```

---

## 11. Plan de Implementación por Fases

### Fase 1 — CPU + ALU (núcleo)

**Fichero:** `cpu.py`

1. Clase `CPU`: `__init__`, `reset()`, `snapshot()`.
2. Helpers de lectura/escritura de memoria: `mem_read(addr)`, `mem_write(addr, val)`.
3. Helpers de stack: `push16(val)`, `pop16() → int`.
4. ALU interna: función `alu_op(op, a, b, cin=0) → (result, flags)` que replica `alu_ref.py`.
5. Método `step() → StepResult`:
   - Decodifica opcode en `PC`.
   - Despacha a handler por grupo.
   - Retorna diff.
6. Manejador de interrupciones: `interrupt(vector_addr)`.

**Criterio de éxito:** `python -c "from sim.cpu import CPU; c=CPU(); c.mem[0]=0xC2; c.step(); assert c.A==1"` pasa.

### Fase 2 — Ensamblador

**Fichero:** `assembler.py`

1. Tabla de instrucciones como lista de dataclasses `InstrDef(pattern, opcode, operands)`.
2. Función `assemble_line(text, pc) → AsmResult`.
3. Función `assemble_program(lines, start) → (bytes, symbol_table, errors)` (2 pasadas).
4. Parser de números: hex/bin/dec, rango y truncamiento automático.

**Criterio de éxito:** `assemble_line("LD A, #0x42", 0)` devuelve `[0x11, 0x42]`.

### Fase 3 — Display

**Fichero:** `display.py`

1. `show_regs(cpu)` → string multilínea.
2. `show_diff(diff) → string`.
3. `show_mem(cpu, addr, count) → string`.
4. `show_listing(buffer) → string`.
5. `show_step_trace(addr, mnemonic, diff, cycles) → string`.

**Criterio de éxito:** output legible sin excepciones.

### Fase 4 — CLI REPL básico

**Fichero:** `cli.py` + `__main__.py`

1. Loop con `input()`, parseo de comandos especiales vs. instrucciones.
2. Modo REPL: ensamblar + ejecutar + mostrar diff.
3. Comandos: `regs`, `mem`, `reset`, `quit`, `help`.

**Criterio de éxito:** `python -m sim` lanza el prompt; `LD A, #0x42` + `ADD #0x08` muestra `A: 0x00 → 0x4A`.

### Fase 5 — Modo Programa

**Fichero:** `cli.py` (extensión)

1. Sub-modo `program [addr]` con prompt distinto.
2. Buffer de instrucciones con etiquetas.
3. Comandos `list`, `run`, `step`, `delete`, `back`.
4. Pausa en `HALT`, reanuda con `irq`/`nmi`.

**Criterio de éxito:** cargar el programa TB-12 manualmente, `run`, ver traza completa con IRQ y NMI.

### Fase 6 — Ficheros y pulido

**Fichero:** todos

1. `load`/`save` de ficheros `.asm`.
2. Directivas `.org`, `.byte`, `.word`.
3. Detección de color de terminal (`os.isatty`).
4. Historial de comandos con `readline` (si disponible).
5. Comando `set` / `write` para inyectar estado.

**Criterio de éxito:** `load testbenchs/vectors/_sim_run.csv` no aplica; pero `load prog.asm` + `run` reproduce el TB-12 correctamente.

---

## 12. Tests del Simulador

| Test | Método | Qué verifica |
|---|---|---|
| ALU interna | `sim/tests/test_cpu_alu.py` — corre los mismos CSVs de `alu_ref.py` | Las 28 operaciones, ~2M vectores |
| Ensamblador | `sim/tests/test_assembler.py` | Cada mnemónico con sus variantes; little-endian; etiquetas |
| Programas TB | `sim/tests/test_programs.py` | Porta los 13 programas de `Processor_Top_tb.vhdl` al simulador y verifica las mismas condiciones de PASS |

Los tests de programas actúan como **cross-check**: si el simulador Python
coincide con el hardware VHDL en los 13 TBs, el modelo es correcto.

---

## 13. Dependencias del Diseño con la ISA

El simulador implementa **semántica perfecta ISA v0.7**. Los aspectos micro-
arquitecturales (pipeline, stalls, ciclos exactos) se modelan solo como
`cycles: int` en el `StepResult` (valor informativo, no afecta al comportamiento
funcional).

Las optimizaciones de v0.8+ (forwarding, TDP, RAS, BSR/RET LR) no requieren
cambios en el simulador cuando se implementen en VHDL: la semántica visible
al programador no cambia.

---

*Fin del documento de plan. Siguiente paso: codificación comenzando por Fase 1 (`cpu.py`).*
