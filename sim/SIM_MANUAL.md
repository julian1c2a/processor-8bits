# Manual del Simulador / Ensamblador — ISA v0.7

> **Requisitos:** Python ≥ 3.10, stdlib pura (sin dependencias externas).  
> **Arranque:** `python -m sim` desde la raíz del repositorio.

---

## 1. Visión general

El paquete `sim/` es un simulador y ensamblador interactivo que replica exactamente el comportamiento RTL del procesador de 8 bits descrito en `ISA.md` v0.7. Permite:

- Escribir instrucciones una a una y ver el efecto inmediato sobre los registros y la memoria (modo REPL).
- Desarrollar programas completos con etiquetas, directivas `.org`/`.byte`/`.word` y ejecutarlos con traza de cada paso (modo programa).
- Cargar y guardar ficheros binarios.
- Inyectar señales `IRQ` y `NMI` y observar el mecanismo de atención a interrupciones.

### Estructura del paquete

```
sim/
├── __init__.py      # Exporta CPU y Assembler
├── __main__.py      # Punto de entrada: python -m sim
├── alu.py           # Modelo de referencia de la ALU (28 operaciones)
├── cpu.py           # Modelo de la CPU completa (todos los opcodes ISA v0.7)
├── assembler.py     # Ensamblador de 1/2 pasadas con etiquetas
├── display.py       # Funciones de visualización (colores ANSI opcionales)
└── cli.py           # Interfaz de línea de comandos (REPL + programa)
```

---

## 2. Inicio rápido

```
$ python -m sim

Simulador ISA v0.7  —  procesador de 8 bits
Escribe 'help' para ver los comandos disponibles.

(asm) > LD A, #0x42
  LD A, #0x42              [11 42]  2c
    A    : 0x00 → 0x42
    PC   : 0x0000 → 0x0002

(asm) > LD B, #0x0A
  LD B, #0x0a              [21 0a]  2c
    B    : 0x00 → 0x0a
    PC   : 0x0002 → 0x0004

(asm) > ADD
  ADD                      [90]  2c
    A    : 0x42 → 0x4c
    PC   : 0x0004 → 0x0005

(asm) > regs
  A=0x4c  B=0x0a  PC=0x0005  SP=0xfffe  LR=0x0000  I:0
  F=0x00  [ C:0  H:0  V:0  Z:0  G:0  E:0  R:0  L:0 ]
```

---

## 3. Los dos modos de trabajo

### 3.1 Modo REPL — `(asm) >`

El modo por defecto. Cada instrucción que se escribe es:

1. **Ensamblada** al valor de `PC` actual.
2. **Escrita en memoria** en esa posición.
3. **Ejecutada** inmediatamente.
4. **Mostrada** con los bytes codificados, ciclos consumidos y el diff de registros/memoria/E/S.

Útil para explorar el comportamiento de instrucciones individuales o secuencias cortas.

### 3.2 Modo programa — `(prog NNNN) >>`

Se activa con el comando `program [addr]`. En este modo las instrucciones **se acumulan** en un buffer interno en lugar de ejecutarse al momento. Cuando el buffer está completo se lanza `run` para:

1. **Enlazar** (segunda pasada: resolver etiquetas forward).
2. **Cargar** el binario resultante en memoria a partir de `.org`.
3. **Ejecutar** instrucción a instrucción mostrando una traza compacta por línea.

El comando `back` vuelve al modo REPL sin perder el estado de la CPU.

---

## 4. Referencia de comandos

### 4.1 Comandos disponibles en ambos modos

| Comando | Sintaxis | Descripción |
|---|---|---|
| `regs` | `regs` | Muestra todos los registros y flags. |
| `mem` | `mem <addr> [n]` | Volcado xxd de `n` bytes (def. 64) desde `addr`. |
| `io` | `io [start] [n]` | Tabla de puertos de E/S (def. start=0, n=16). |
| `set` | `set <reg> <val>` | Fuerza el valor de un registro. Registros: `A B PC SP F LR I`. |
| `write` | `write <addr> <b0> [b1 …]` | Escribe bytes en memoria. |
| `reset` | `reset` | Soft reset: reinicia registros, conserva la memoria. |
| `clrmem` | `clrmem` | Hard reset: borra registros y toda la memoria. |
| `load` | `load <fichero> [addr]` | Lee un fichero binario y lo carga en memoria desde `addr` (o `PC`). |
| `save` | `save <fichero> <addr> <n>` | Guarda `n` bytes de memoria desde `addr` a fichero binario. |
| `irq` | `irq` | Señal IRQ pendiente (se atiende si `I=1`). |
| `nmi` | `nmi` | Señal NMI pendiente (incondicional). |
| `program` | `program [addr]` | Entra en modo programa con `.org = addr` (def. `PC` actual). |
| `step` | `step` | Ejecuta una sola instrucción (útil durante o después de `run`). |
| `help` | `help` / `h` / `?` | Muestra la ayuda del modo activo. |
| `quit` | `quit` / `exit` / `q` | Sale del simulador. |

### 4.2 Comandos exclusivos del modo programa

| Comando | Descripción |
|---|---|
| `<instrucción>` | Añade instrucción al buffer (no ejecuta). |
| `<etiqueta>:` | Declara una etiqueta en la posición actual. |
| `.org <addr>` | Cambia la dirección base de ensamblado. |
| `.byte v1[,v2,…]` | Emite bytes literales. |
| `.word v1[,v2,…]` | Emite palabras de 16 bits (little-endian). |
| `list` / `ls` | Muestra el listing con dirección, bytes y mnemónico. |
| `run` | Enlaza y ejecuta el programa completo con traza. |
| `rewind` | Reinicia `PC` al `.org` (sin borrar memoria). |
| `delete [n]` | Elimina la última línea del buffer (o la n-ésima). |
| `back` / `b` | Vuelve al modo REPL. |

---

## 5. Sintaxis del ensamblador

### 5.1 Números

El ensamblador acepta literales en cualquier base:

| Prefijo | Base | Ejemplo |
|---|---|---|
| `0x` / `0X` | Hexadecimal | `0xFF`, `0x1A3B` |
| `0b` / `0B` | Binario | `0b10110001` |
| `0o` / `0O` | Octal | `0o377` |
| *(ninguno)* | Decimal | `255`, `1024` |
| `-` / `+` | Signo | `-128`, `+4` |

El prefijo `#` antes del número indica **operando inmediato**. Sin `#`, el número se interpreta como **dirección**.

### 5.2 Modos de direccionamiento

| Sintaxis | Forma | Descripción |
|---|---|---|
| *(sin operando)* | implícito | La instrucción opera solo sobre registros. |
| `A` / `B` / `F` / `A:B` | registro | Referencia directa al registro. |
| `#n` | inmediato 8 bits | Constante de 8 bits. |
| `#nn` | inmediato 16 bits | Constante de 16 bits (valor > 0xFF). |
| `[n]` | página cero (ZP) | Dirección 8 bits (0x00–0xFF). |
| `[nn]` | absoluto | Dirección 16 bits. |
| `[B]` | indirecto por B | La dirección es el contenido de B. |
| `[nn+B]` | indexado absoluto | Dirección = nn + B. |
| `[n+B]` | indexado página cero | Dirección = n + B (resultado en 0x00–0xFF). |
| `([nn])` | indirecto absoluto | La dirección está en mem[nn]:mem[nn+1]. |
| `+n` / `-n` | offset directo REL8 | Desplazamiento firmado relativo al PC. |
| `etiqueta` | dirección simbólica | Para saltos y llamadas. |

**Auto-selección ZP / ABS:** si el valor de la dirección cabe en 8 bits (≤ 0xFF), el ensamblador elige automáticamente la forma ZP (1 byte extra); si no, elige ABS (2 bytes extra).

**Auto-selección ADD16/SUB16 IMM8 / IMM16:** si el valor cabe en un byte con signo (−128…127), se usa la forma IMM8 (opcode 0xE0/0xE2) con extensión de signo; si no, IMM16 (opcode 0xE1/0xE3).

### 5.3 Etiquetas

- Sintaxis: `nombre:` al principio de la línea (o seguido de instrucción).
- Caracteres válidos: `[a-zA-Z_][a-zA-Z0-9_]*` (case-sensitive).
- Se resuelven en **segunda pasada** dentro del modo programa, lo que permite referencias forward.
- En modo REPL las etiquetas forward **no** están permitidas (no hay segunda pasada).

```
; Ejemplo con etiqueta forward
        LD A, #0x00
loop:   INC A
        CMP #0x10
        BNE loop       ; referencia backward — OK en REPL y programa
        HALT

; Referencia forward — sólo en modo programa
        BEQ done
        INC A
done:   HALT
```

### 5.4 Comentarios

Se ignora todo lo que va desde `;` o `//` hasta el final de la línea.

```
LD A, #0x42   ; carga 66 decimal
ADD           // suma A + B
```

### 5.5 Directivas

| Directiva | Efecto |
|---|---|
| `.org <addr>` | Cambia el contador de programa del ensamblador. |
| `.byte v1[,v2,…]` | Emite bytes literales en memoria (cada valor: 0–255). |
| `.word v1[,v2,…]` | Emite palabras little-endian de 16 bits. |

---

## 6. Codificación de saltos relativos

Para las instrucciones `JR`, `BSR`, `BEQ`/`BNE`/`BCS`/`BCC`/`BVS`/`BVC`/`BGT`/`BLE`/`BGE`/`BLT`/`BHC`/`BEQ2` el operando de rama puede expresarse de tres formas:

| Forma | Ensamblador | CPU |
|---|---|---|
| Offset con signo | `BEQ +4` / `BNE -6` | El byte codificado **es** el offset (ya calculado). |
| Dirección absoluta | `BEQ 0x0210` | rel8 = target − (PC_instrucción + 2); error si ∉ [−128, 127]. |
| Etiqueta | `BNE loop` | Igual que dirección absoluta, resuelta en segunda pasada. |

La CPU suma el byte firmado de rel8 al PC **después del fetch del operando** (PC = dirección\_instrucción + 2), lo que es el comportamiento estándar del pipeline.

---

## 7. Modelo de la CPU

### 7.1 Registros

| Registro | Tamaño | Valor inicial | Notas |
|---|---|---|---|
| `A` | 8 bits | 0x00 | Acumulador principal. |
| `B` | 8 bits | 0x00 | Registro auxiliar / índice. |
| `PC` | 16 bits | 0x0000 | Contador de programa. |
| `SP` | 16 bits | 0xFFFE | Puntero de pila, word-aligned (bit 0 siempre 0). |
| `F` | 8 bits | 0x00 | Registro de flags. |
| `LR` | 16 bits | 0x0000 | Link register (guarda dirección de retorno de CALL/BSR). |
| `I` | 1 bit | 0 | Habilitación de IRQ (no forma parte de F). |

### 7.2 Registro de flags F

```
  bit:  7    6    5    4    3    2    1    0
  flag: C    H    V    Z    G    E    R    L
```

| Flag | Significado |
|---|---|
| `C` | Carry / no-borrow |
| `H` | Half-carry (nibble bajo) |
| `V` | Overflow en complemento a dos |
| `Z` | Zero |
| `G` | Greater than (comparación con signo: A > B) |
| `E` | Equal (A == B) |
| `R` | Bit expulsado por la derecha (desplazamientos) |
| `L` | Bit expulsado por la izquierda (desplazamientos) |

> El flag `I` es un flip-flop separado, **no** está en F y **no** se guarda en la pila con `PUSH F`.

### 7.3 Pila

- La pila es **descendente y word-aligned** (SP siempre par).
- `PUSH x`: SP −= 2, luego escribe word en mem[SP].
- `POP  x`: lee word de mem[SP], luego SP += 2.
- Las operaciones de pila son siempre de 16 bits, en formato little-endian (byte bajo en la dirección menor).

### 7.4 Interrupciones

| Vector | Dirección | Condición |
|---|---|---|
| IRQ | 0xFFFE:0xFFFF | Requiere `I = 1` |
| NMI | 0xFFFA:0xFFFB | Incondicional |

**Secuencia de atención:**

1. Push PC (16 bits, LE).
2. Push F (16 bits, sólo el byte bajo tiene datos).
3. PC ← mem16[vector].
4. I ← 0.

**RTI (retorno de interrupción):**

1. Pop F (16 bits; sólo los 8 bits bajos se escriben en F).
2. Pop PC (16 bits).
3. I ← 1.

**HALT:** la CPU entra en estado de espera. Si llega un NMI, la atiende inmediatamente. Si llega un IRQ y `I = 1`, también. En cualquier otro caso permanece detenida hasta la siguiente señal. El comando `step` en el CLI avanza un ciclo incluso en HALT.

### 7.5 Comportamientos especiales documentados en ISA v0.7

| Instrucción | Comportamiento |
|---|---|
| `INC B` / `DEC B` | Resultado → B; **flags descartados** (no se modifican). |
| `LD SP, #nn` | Bit 0 forzado a 0: `SP = nn & 0xFFFE`. |
| `LD SP, A:B` | SP = (A<<8)\|B, bit 0 forzado a 0. |
| `ST SP_L, A` | **Lee** SP[7:0] → A (no escribe; nombre histórico confuso). |
| `ST SP_H, A` | **Lee** SP[15:8] → A (ídem). |
| `CMP` / `CMP #n` | No modifica A; actualiza todos los flags. |
| `ADD16 #n` (IMM8) | n se extiende con signo a 16 bits antes de sumar. |
| `RTI` | Restaura F de la palabra leída de pila (bits 15:8 ignorados). |

---

## 8. Modelo de la ALU (sim/alu.py)

La ALU implementa **28 operaciones**, cada una con la firma:

```python
fn(a: int, b: int, cin: int) -> (acc: int, status: int)
```

donde `acc ∈ [0, 255]` y `status` es el byte de flags `C H V Z G E R L`.

| Función | Mnemónico ISA |
|---|---|
| `ref_ADD` | ADD (A+B) |
| `ref_ADC` | ADC (A+B+C) |
| `ref_SUB` | SUB (A−B) |
| `ref_SBB` | SBB (A−B−C) |
| `ref_AND` | AND |
| `ref_IOR` | OR |
| `ref_XOR` | XOR |
| `ref_NOT` | NOT A |
| `ref_NEG` | NEG A (complemento a dos) |
| `ref_INC` | INC A |
| `ref_DEC` | DEC A |
| `ref_INB` | INC B (resultado para B, flags descartados en cpu.py) |
| `ref_DEB` | DEC B (ídem) |
| `ref_CMP` | CMP (sólo flags, acc devuelto = 0) |
| `ref_LSL` | LSL A (desplazamiento lógico izquierda) |
| `ref_LSR` | LSR A (desplazamiento lógico derecha) |
| `ref_ASL` | ASL A (aritmético izquierda, detecta overflow) |
| `ref_ASR` | ASR A (aritmético derecha, replica bit 7) |
| `ref_ROL` | ROL A (rotación izquierda cíclica) |
| `ref_ROR` | ROR A (rotación derecha cíclica) |
| `ref_SWP` | SWAP A (nibble-swap) |
| `ref_MUL` | MUL (A×B, byte bajo) |
| `ref_MUH` | MUH (A×B, byte alto) |
| `ref_PSA` | PA (pasa A sin cambio) |
| `ref_PSB` | PB (pasa B sin cambio) |
| `ref_CLR` | CLR A (fuerza a 0) |
| `ref_SET` | SET A (fuerza a 0xFF) |

Las operaciones ADD16/SUB16 **no** usan la ALU de 8 bits; tienen su propia aritmética de 16 bits en `_alu16()` y `_alu16_sub()` dentro de `cpu.py`, y sólo actualizan `C`, `V` y `Z` (no G, E, H, R, L).

---

## 9. Flujo interno del ensamblador

```
Texto de entrada
       │
       ▼
┌─────────────────────────────┐
│  _parse_line()              │
│  · Elimina comentarios      │
│  · Detecta .org/.byte/.word │
│  · Extrae etiqueta (si hay) │
│  · Llama a _encode()        │
└────────────┬────────────────┘
             │
             ▼
┌─────────────────────────────┐
│  _encode()                  │
│  · Normaliza texto          │
│  · _split_mnemonic():       │
│    busca la clave más       │
│    larga en _MNEMONIC_KEYS  │
│  · _classify_operand():     │
│    determina forma (IMM8,   │
│    ZP, ABS, REL8, ...)      │
│  · Consulta _LOOKUP dict    │
│  · _encode_operand():       │
│    produce lista de bytes   │
└────────────┬────────────────┘
             │
             ▼
         AsmLine
  (addr, encoded[], size,
   _patch_label si forward)
             │
   [sólo modo programa]
             │
             ▼
┌────────────────────────────┐
│  link() — segunda pasada   │
│  · Resuelve _patch_label   │
│  · Calcula rel8 definitivo │
│  · Devuelve binario plano  │
└────────────────────────────┘
```

### 9.1 Tabla de instrucciones (`_TABLE` y `_LOOKUP`)

La tabla `_TABLE` es una lista de tuplas `(mnemonic_key, operand_form, opcode)`: los 100+ opcodes ISA v0.7. El diccionario `_LOOKUP` se construye desde ella con clave `(mnemonic_key_upper, operand_form)` → `opcode`.

La búsqueda greedy en `_split_mnemonic` prueba las claves ordenadas de mayor a menor longitud para resolver ambigüedades como `CALL LR` vs `CALL`, `NOT A` vs `NOT`, `LD SP` vs `LD A`.

---

## 10. Flujo interno del CLI

```
CLI.run()
    │
    ├─── input() ──► _dispatch(line)
    │                     │
    │         ┌───────────┴──────────────┐
    │         │                          │
    │    REPL mode                  PROG mode
    │    _repl_exec(line)           _prog_feed(line)
    │         │                          │
    │    asm.assemble_line()        asm.feed()
    │    cpu.mem[PC..] = bytes      (acumula AsmLine)
    │    cpu.step()                       │
    │    show_diff(result)          "run" → link() + _cmd_run()
    │                                     └─ loop cpu.step()
    │                                        show_step_trace()
    │
    └─── show_regs / show_mem / show_io / ...
```

### 10.1 Traza en modo `run`

El bucle de `_cmd_run()` detiene la ejecución cuando:

- `PC` apunta justo después del último byte del programa (fin natural).
- La CPU entra en `HALT` y no hay interrupción pendiente inmediata.
- Se alcanzan 100 000 pasos (límite anti-bucle infinito).

---

## 11. Visualización

Las funciones de `display.py` usan colores ANSI **sólo si `stdout` es un TTY** (terminal interactivo). Si la salida se redirige a fichero o se usa en pipe, el texto es limpio sin códigos de escape.

| Función | Descripción |
|---|---|
| `show_regs(cpu)` | Línea compacta con todos los registros y flags. |
| `show_diff(result)` | Mnemónico + bytes + ciclos + cambios de reg/mem/io. |
| `show_step_trace(result)` | Traza de una línea para bucle `run`. |
| `show_mem(cpu, addr, n)` | Volcado xxd: 16 bytes/fila, hex + ASCII. |
| `show_io(cpu, start, n)` | Tabla de puertos de E/S. |
| `show_listing(lines, highlight_pc)` | Listing numerado con dir., bytes y mnemónico. |

---

## 12. Ejemplos de sesión

### 12.1 Probar una suma con desbordamiento

```
(asm) > LD A, #0xFF
  LD A, #0xff              [11 ff]  2c
    A    : 0x00 → 0xff
    PC   : 0x0000 → 0x0002

(asm) > ADD #0x01
  ADD #0x01                [a0 01]  2c
    A    : 0xff → 0x00
    PC   : 0x0002 → 0x0004
    F    : 0x00 [........] → 0x90 [C..Z....]
```

Carry activo, resultado cero → `C=1 Z=1`.

### 12.2 Programa: suma de los primeros N naturales

```
(asm) > program 0x0100
Modo programa — .org = 0x0100

(prog 0x0100) >> ; suma 1+2+…+5 en A
(prog 0x0100) >> LD A, #0x00   ; acumulador = 0
(prog 0x0102) >> LD B, #0x01   ; contador = 1
(prog 0x0104) >> loop:
(prog 0x0104) >> ADD            ; A += B
(prog 0x0105) >> INC B
(prog 0x0106) >> CMP #0x06      ; B == 6?
(prog 0x0108) >> BNE loop       ; no → repetir
(prog 0x010a) >> HALT

(prog 0x010b) >> list
  ──────────────────────────────────────
   Nº    Addr  Bytes           Mnemónico
  ──────────────────────────────────────
    1  0x0100  11 00           LD A, #0x00
    2  0x0102  21 01           LD B, #0x01
    3  0x0104                  loop:
    4  0x0104  90              ADD
    5  0x0105  c2              INC A      ← aquí debería ser INC B (0xC4)
  ...

(prog 0x010b) >> run
```

> **Nota:** en el ejemplo anterior `INC B` tiene opcode 0xC4 (`INC B`); si se escribe `INC A` por error el listing lo mostrará antes de ejecutar.

### 12.3 Interrupción desde HALT

```
(asm) > set I 1          ; habilitar IRQ
(asm) > LD A, #0xFF
(asm) > HALT
  HALT                   [01]  2c
  ⏸  HALT — CPU detenida. Esperando NMI / IRQ.

(asm) > irq              ; inyectar señal
IRQ solicitado

(asm) > step             ; avanzar un ciclo
[0x????] <IRQ>           []  9c
  SP   : 0xfffe → 0xfffa
  PC   : …→ [vector IRQ]
  I    : 1 → 0
```

### 12.4 Carga de binario externo

```
(asm) > clrmem
Hard reset — registros y memoria borrados

(asm) > load firmware.bin 0x8000
Cargados 512 bytes en 0x8000 desde "firmware.bin"

(asm) > set PC 0x8000
PC ← 0x8000

(asm) > step
[0x8000] …
```

---

## 13. Uso programático (Python)

El paquete puede importarse directamente para casos de test o integración:

```python
from sim import CPU, Assembler
from sim.display import show_regs

cpu = CPU()
asm = Assembler()

# Modo REPL: ensamblar y ejecutar
for line in ['LD A, #0x10', 'LD B, #0x20', 'ADD']:
    r = asm.assemble_line(line, cpu.PC)
    assert r.error is None, r.error
    for i, b in enumerate(r.bytes):
        cpu.mem[cpu.PC + i] = b
    cpu.step()

show_regs(cpu)   # A=0x30 B=0x20 …

# Modo programa: dos pasadas
asm2 = Assembler()
asm2.reset(org=0x0200)
for line in [
    'start: LD A, #0x00',
    '       INC A',
    '       CMP #0x05',
    '       BNE start',
    '       HALT',
]:
    asm2.feed(line)

binary, listing = asm2.link()
assert not any(l.error for l in listing)

cpu2 = CPU()
for i, b in enumerate(binary):
    cpu2.mem[0x0200 + i] = b
cpu2.PC = 0x0200

for _ in range(50):
    sr = cpu2.step()
    if sr.halted:
        break

assert cpu2.A == 5
```

---

## 14. Limitaciones conocidas (v0.7)

| Limitación | Descripción |
|---|---|
| Sin memoria mapeada | La memoria es un `bytearray` plano de 64 KB. No hay peripherals mapeados en memoria automáticos (usa `write`/`set` para simularlos). |
| Sin pipeline real | El simulador es cycle-accurate en conteo de ciclos pero no modela el pipeline de 4 etapas del RTL; no hay stalls RAW observables. |
| Etiquetas forward en REPL | Las referencias a etiquetas que aún no han sido definidas no funcionan en modo REPL (sí en modo programa). |
| Sin breakpoints | No hay comando `break`; se puede aproximar con el límite de pasos de `run`. |
| `readline` opcional | El historial de comandos requiere el módulo `readline` (disponible en Linux/macOS; en Windows puede requerir `pyreadline3`). |
