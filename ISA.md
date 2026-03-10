# ISA — Arquitectura del Conjunto de Instrucciones

## Procesador de 8 bits con bus de direcciones de 16 bits

> **Estado: borrador v0.4** — 450 MHz MMCM/PLL; UART1 (segundo canal, puertos 0x05–0x09); acceso atómico a timers 32 bits; UC por microcode; IN/OUT 0xD0–0xD3 definidas.
> *(v0.3: ALU extendida NEG/INCB/DECB; indexado; I/O separada; interrupciones; PFQ; EA-adder; PUSH/POP 16 b; Nexys 7 100T.)*

---

## 1. Visión General

| Parámetro              | Valor                        |
|------------------------|------------------------------|
| Anchura de datos       | 8 bits                       |
| Bus de direcciones     | 16 bits (64 KB)              |
| Número de registros    | 2 visibles (A, B) + especiales |
| Modelo de ejecución    | Acumulador (resultado → A)   |
| Endianness             | Little-endian (byte bajo en dirección menor) |
| Vector de reset        | `0x0000`                     |
| Stack                  | Descendente, SP inicial `0xFFFE` (alineado a par) |
| Ancho del stack-bus    | 16 bits (PUSH/POP de palabra) |
| Prefetch               | Cola de 2 bytes              |
| SRAM página cero       | BlockRAM dedicada, 1 ciclo   |
| Plataforma             | Nexys 7 100T (Artix-7 XC7A100T) |
| Frecuencia de reloj    | 450 MHz (MMCM/PLL interno; SRAM ext. 4 wait states) |
| Unidad de Control      | Microcode (ROM de microinstrucciones) |

El procesador es de arquitectura **acumulador**: la ALU toma A y B como
operandos y el resultado siempre vuelve a A. B actúa como operando
secundario o registro auxiliar.

---

## 2. Registros

| Registro | Bits | Descripción                                              |
|----------|------|----------------------------------------------------------|
| **A**    |  8   | Acumulador. Operando principal de la ALU y destino del resultado. |
| **B**    |  8   | Registro secundario. Segundo operando de la ALU; también usado como índice de página cero. |
| **PC**   | 16   | Program Counter. Apunta a la siguiente instrucción a leer. |
| **SP**   | 16   | Stack Pointer. Apunta al tope del stack (dirección libre). Stack descendente: PUSH decrementa, POP incrementa. |
| **F**    |  8   | Registro de Flags (ver sección 3).                        |

> **Nota de diseño:** Los registros internos TMP\_H:TMP\_L (16 bits) y MDR
> (8 bits) existen en la micro-arquitectura pero **no son accesibles al
> programador**.
>
> El registro **EAR** (Effective Address Register, 16 bits) también es
> interno: el sumador EA de 16 bits escribe en él durante el pipeline de
> fetch. Del mismo modo, **PFQ** (Prefetch Queue, 2 bytes + 1 bit de
> validez) es parte de la UC y no es visible al programador.

---

## 3. Registro de Flags (F) y flag de Interrupción (I)

### 3.1 Registro F (8 bits)

| Bit | Símbolo | Nombre           | Descripción                                           |
|-----|---------|------------------|-------------------------------------------------------|
|  7  | **C**   | Carry / Borrow   | ADD/ADC: carry de bit 7. SUB/SBB/CMP: `NOT borrow` (C=1 → sin préstamo, A≥B). |
|  6  | **H**   | Half-carry       | Carry/Borrow entre nibbles (bits 3→4). Útil para BCD. |
|  5  | **V**   | Overflow         | Desbordamiento en aritmética con signo (complemento a 2). |
|  4  | **Z**   | Zero             | El resultado de la última operación aritmética/lógica es 0x00. |
|  3  | **G**   | Greater          | A > B en comparación con signo (seteado por CMP y operaciones ALU). |
|  2  | **E**   | Equal            | A = B (comparación bit a bit de los operandos de entrada).  |
|  1  | **R**   | Bit desplazado → | Bit 0 desplazado fuera en LSR/ASR.                    |
|  0  | **L**   | Bit desplazado ← | Bit 7 desplazado fuera en LSL/ASL.                    |

### 3.2 Flag de Interrupción I (flip-flop interno)

**I** es un biestable interno a la UC, **no** forma parte de F ni se guarda con `PUSH F`.

| Instrucción | Efecto sobre I    |
|-------------|-------------------|
| `SEI`       | I ← 1 (habilita)  |
| `CLI`       | I ← 0 (deshabilita)|
| Entrada IRQ | I ← 0 (auto)      |
| `RTI`       | I ← 1 (auto)      |

El IMR de I/O (puerto `0x30`) permite máscara individual de fuentes; I actúa como habilitación global.

### Convención de signo en resta

SUB, SBB y CMP sign-extienden los operandos internamente (ver `ALU.vhdl`).
El flag **C** usa la convención *no-borrow*:

```
C = 1  →  sin préstamo  →  A ≥ B  (interpretación unsigned del resultado)
C = 0  →  hubo préstamo →  A < B
```

---

## 4. Mapa de Memoria y Espacio I/O

### 4.1 Mapa de Memoria (64 KB)

```
0x0000 – 0x00FF   Página cero       (acceso rápido, 1 byte de dirección)
0x0100 – 0xFFF9   Memoria general   (RAM/ROM según sistema)
0xFFFA – 0xFFFB   Vector de NMI     (Non-Maskable Interrupt, little-endian)
0xFFFC – 0xFFFD   (reservado)
0xFFFE – 0xFFFF   Vector de IRQ     (Maskable Interrupt, little-endian)
```

> El I/O **no** está mapeado en memoria; se accede con instrucciones `IN`/`OUT`
> (espacio físico separado — ver §4.2).
>
> El stack crece desde `0xFFFF` hacia abajo. SP inicial = `0xFFFF`; el
> primer PUSH escribe en `0xFFFE` (¡coincide con vector IRQ si SP no se
> inicializa antes!). Se recomienda inicializar SP en `0xFFF9` o inferior.

### 4.2 Espacio de I/O (256 puertos, 8-bit independiente)

Acceso exclusivo mediante `IN A, #n` / `OUT #n, A` (o variantes con `[B]`).

| Puerto | Nombre      | R/W | Descripción |
|--------|-------------|-----|-------------|
| `0x00` | UART_DATA   | R/W | TX: byte a enviar (W). RX: byte recibido (R). |
| `0x01` | UART_STAT   |  R  | `[3]` TX busy · `[2]` RX ready · `[1]` TX_IE · `[0]` RX_IE |
| `0x02` | UART_CTRL   |  W  | `[3]` TX_EN · `[2]` RX_EN · `[1]` TX_IE · `[0]` RX_IE |
| `0x03` | UART_BAUD_L |  W  | Divisor de baudrate — byte bajo |
| `0x04` | UART_BAUD_H |  W  | Divisor de baudrate — byte alto |
| `0x05` | UART1_DATA   | R/W | UART1: TX (W) / RX (R). Segundo canal serie. |
| `0x06` | UART1_STAT   |  R  | `[3]` TX busy · `[2]` RX ready · `[1]` TX_IE · `[0]` RX_IE |
| `0x07` | UART1_CTRL   |  W  | `[3]` TX_EN · `[2]` RX_EN · `[1]` TX_IE · `[0]` RX_IE |
| `0x08` | UART1_BAUD_L |  W  | Divisor baudrate UART1 — byte bajo |
| `0x09` | UART1_BAUD_H |  W  | Divisor baudrate UART1 — byte alto |
| `0x0A–0x0F` | —      | —   | Reservados |
| `0x10` | TMR0_CNT0   | R/W | Timer 0: bits 7:0. Lectura: **latch atómico** — captura los 32 bits en registro sombra; CNT1–3 retornan el snapshot. Escritura: precarga (timer detenido). |
| `0x11` | TMR0_CNT1   |  R  | Timer 0: bits 15:8 del snapshot atómico (válido tras leer CNT0). |
| `0x12` | TMR0_CNT2   |  R  | Timer 0: bits 23:16 del snapshot atómico. |
| `0x13` | TMR0_CNT3   |  R  | Timer 0: bits 31:24 del snapshot atómico. |
| `0x14` | TMR0_RLD0   | R/W | Timer 0: valor de recarga bits  7:0  |
| `0x15` | TMR0_RLD1   | R/W | Timer 0: valor de recarga bits 15:8  |
| `0x16` | TMR0_RLD2   | R/W | Timer 0: valor de recarga bits 23:16 |
| `0x17` | TMR0_RLD3   | R/W | Timer 0: valor de recarga bits 31:24 |
| `0x18` | TMR0_CTRL   | R/W | `[2]` IRQ_EN · `[1]` auto-reload · `[0]` run/stop |
| `0x19–0x1F` | —      | —   | Reservados Timer 0 |
| `0x20` | TMR1_CNT0   | R/W | Timer 1: bits 7:0. Latch atómico ídem TMR0_CNT0. |
| `0x21` | TMR1_CNT1   |  R  | Timer 1: bits 15:8 del snapshot atómico. |
| `0x22` | TMR1_CNT2   |  R  | Timer 1: bits 23:16 del snapshot atómico. |
| `0x23` | TMR1_CNT3   |  R  | Timer 1: bits 31:24 del snapshot atómico. |
| `0x24` | TMR1_RLD0   | R/W | ↑ |
| `0x25` | TMR1_RLD1   | R/W | ↑ |
| `0x26` | TMR1_RLD2   | R/W | ↑ |
| `0x27` | TMR1_RLD3   | R/W | ↑ |
| `0x28` | TMR1_CTRL   | R/W | ↑ |
| `0x29–0x2F` | —      | —   | Reservados Timer 1 |
| `0x30` | IMR         | R/W | Máscara de interrupciones (1=habilitada): `[3]`UART1 · `[2]`TMR1 · `[1]`TMR0 · `[0]`UART0 |
| `0x31` | IFR         | R/W | Flags pendientes (read=get, write 1=clear) |
| `0x32` | IVL         | R/W | Byte bajo del vector IRQ (también en `0xFFFE`) |
| `0x33` | IVH         | R/W | Byte alto del vector IRQ (también en `0xFFFF`) |
| `0x34` | NVIL        | R/W | Byte bajo del vector NMI (también en `0xFFFA`) |
| `0x35` | NVIH        | R/W | Byte alto del vector NMI (también en `0xFFFB`) |
| `0x36–0xFF` | —      | —   | Disponibles para periféricos futuros |

---

## 5. Formatos de Instrucción

```
┌─────────────────────────────────────────────────────────────┐
│ 1 byte   │  [ opcode ]                                       │
│          │  Instrucciones implícitas (NOP, RET, HALT…)       │
├─────────────────────────────────────────────────────────────┤
│ 2 bytes  │  [ opcode ][ operando8 ]                          │
│          │  Inmediato, página cero, salto relativo            │
├─────────────────────────────────────────────────────────────┤
│ 3 bytes  │  [ opcode ][ addr_low ][ addr_high ]              │
│          │  Dirección absoluta de 16 bits (little-endian)     │
└─────────────────────────────────────────────────────────────┘
```

---

## 6. Modos de Direccionamiento

### 6.1 Modos existentes

| Símbolo      | Nombre            | Ejemplo            | Bytes | Descripción                                      |
|--------------|-------------------|--------------------|-------|--------------------------------------------------|
| `IMP`        | Implícito         | `NOP`              | 1     | Sin operando; el registro queda implícito.        |
| `#n`         | Inmediato 8-bit   | `LD A, #0x42`      | 2     | El byte que sigue al opcode es el valor literal.  |
| `#nn`        | Inmediato 16-bit  | `LD SP, #0xFF00`   | 3     | Los dos bytes siguientes forman la dirección.     |
| `[n]`        | Página cero       | `LD A, [0x10]`     | 2     | Dirección `0x00nn` (1 byte). Acceso rápido.       |
| `[nn]`       | Absoluto          | `LD A, [0x1234]`   | 3     | Dirección completa de 16 bits.                    |
| `[B]`        | Indirecto por B   | `LD A, [B]`        | 1     | Dirección = `0x00:B` (página cero vía registro B). |
| `rel8`       | Relativo          | `BEQ rel8`         | 2     | `PC ← PC + sign_ext(rel8)`. Rango ±127 bytes.    |
| `page8`      | Misma página      | `JPN page8`        | 2     | `PC ← PC[15:8] : page8`. Solo cambia byte bajo.  |
| `([nn])`     | Indirecto absoluto| `JP ([0x1234])`    | 3     | `PC ← M[nn+1]:M[nn]`. Salto indirecto.           |

### 6.2 Modos indexados (nuevos)

| Símbolo      | Nombre                  | Ejemplo              | Bytes | Descripción                                           |
|--------------|-------------------------|----------------------|-------|-------------------------------------------------------|
| `[nn+B]`     | Absoluto indexado por B | `LD A, [0x1000+B]`   | 3     | Dirección = `nn + B` (suma sin signo, 16-bit).        |
| `[n+B]`      | Pág-cero indexado por B | `LD A, [0x10+B]`     | 2     | Dirección = `0x00:n + B`. Envuelve dentro de pág-cero.|

El registro B actúa como índice; su valor **no** se modifica.
Los 3 bytes de `[nn+B]` son: `opcode`, `addr_low + B` se calcula durante la
ejecución; el ensamblador emite `addr_low` y `addr_high` del base.

### 6.3 Modo I/O (nuevo)

| Símbolo   | Nombre          | Ejemplo        | Bytes | Descripción                                    |
|-----------|-----------------|----------------|-------|------------------------------------------------|
| `io[#n]`  | I/O inmediato   | `IN A, #0x01`  | 2     | Puerto = byte literal. Acceso al espacio I/O.  |
| `io[B]`   | I/O indirecto B | `IN A, [B]`    | 1     | Puerto = valor de registro B.                  |

---

## 7. Conjunto de Instrucciones

### 7.1 Sistema

| Opcode | Mnemónico  | Bytes | Operación              | Flags |
|--------|------------|-------|------------------------|-------|
| `0x00` | `NOP`      | 1     | —                      | —     |
| `0x01` | `HALT`     | 1     | Detiene el reloj       | —     |
| `0x02` | `SEC`      | 1     | C ← 1                  | C     |
| `0x03` | `CLC`      | 1     | C ← 0                  | C     |
| `0x04` | `SEI`      | 1     | I ← 1 (habilita interrupciones enmascarables) | — |
| `0x05` | `CLI`      | 1     | I ← 0 (deshabilita interrupciones enmascarables) | — |
| `0x06` | `RTI`      | 1     | F←M[SP]; SP+=2; PC←M[SP+1]:M[SP]; SP+=2; I←1 *(pop F luego pop PC)* | todos |

---

### 7.2 Carga y Almacenamiento

#### Carga de A

| Opcode | Mnemónico         | Bytes | Operación                   | Flags |
|--------|-------------------|-------|-----------------------------|-------|
| `0x10` | `LD A, B`         | 1     | A ← B                       | Z     |
| `0x11` | `LD A, #n`        | 2     | A ← n                       | Z     |
| `0x12` | `LD A, [n]`       | 2     | A ← M[0x00:n]               | Z     |
| `0x13` | `LD A, [nn]`      | 3     | A ← M[nn]                   | Z     |
| `0x14` | `LD A, [B]`       | 1     | A ← M[0x00:B]               | Z     |
| `0x15` | `LD A, [nn+B]`    | 3     | A ← M[nn + B]               | Z     |
| `0x16` | `LD A, [n+B]`     | 2     | A ← M[0x00:n + B]           | Z     |

#### Carga de B

| Opcode | Mnemónico         | Bytes | Operación                   | Flags |
|--------|-------------------|-------|-----------------------------|-------|
| `0x20` | `LD B, A`         | 1     | B ← A                       | —     |
| `0x21` | `LD B, #n`        | 2     | B ← n                       | —     |
| `0x22` | `LD B, [n]`       | 2     | B ← M[0x00:n]               | —     |
| `0x23` | `LD B, [nn]`      | 3     | B ← M[nn]                   | —     |
| `0x24` | `LD B, [B]`       | 1     | B ← M[0x00:B]               | —     |
| `0x25` | `LD B, [nn+B]`    | 3     | B ← M[nn + B]               | —     |

#### Almacenamiento

| Opcode | Mnemónico         | Bytes | Operación                   | Flags |
|--------|-------------------|-------|-----------------------------|-------|
| `0x30` | `ST A, [n]`       | 2     | M[0x00:n] ← A               | —     |
| `0x31` | `ST A, [nn]`      | 3     | M[nn] ← A                   | —     |
| `0x32` | `ST A, [B]`       | 1     | M[0x00:B] ← A               | —     |
| `0x33` | `ST A, [nn+B]`    | 3     | M[nn + B] ← A               | —     |
| `0x34` | `ST A, [n+B]`     | 2     | M[0x00:n + B] ← A           | —     |
| `0x40` | `ST B, [n]`       | 2     | M[0x00:n] ← B               | —     |
| `0x41` | `ST B, [nn]`      | 3     | M[nn] ← B                   | —     |
| `0x42` | `ST B, [nn+B]`    | 3     | M[nn + B] ← B               | —     |

#### Stack Pointer

| Opcode | Mnemónico         | Bytes | Operación                   | Flags |
|--------|-------------------|-------|-----------------------------|-------|
| `0x50` | `LD SP, #nn`      | 3     | SP ← nn                     | —     |
| `0x51` | `LD SP, A:B`      | 1     | SP ← A:B  (A=alto, B=bajo)  | —     |
| `0x52` | `ST SP_L, A`      | 1     | A ← SP[7:0]                 | —     |
| `0x53` | `ST SP_H, A`      | 1     | A ← SP[15:8]                | —     |

---

### 7.3 Stack — PUSH / POP

> **Stack de 16 bits.** Las operaciones PUSH/POP transfieren una **palabra
> de 16 bits** en un solo ciclo de bus de stack (dos bytes en paralelo).
> SP se decrementa/incrementa siempre de 2 en 2 y **debe quedar alineado
> a direcciones pares** en todo momento. El SP inicial es `0xFFFE`.
>
> El byte de flags F (8 bits) se empuja con padding `0x00` en el byte
> alto: `M[SP+1]:M[SP] ← 0x00:F`; al hacer POP sólo se restauran los 8
> bits bajos.

| Opcode | Mnemónico   | Bytes | Operación                                    | Ciclos | Flags |
|--------|-------------|-------|----------------------------------------------|--------|-------|
| `0x60` | `PUSH A`    | 1     | SP−=2; M[SP+1]:M[SP] ← 0x00:A               | 4      | —     |
| `0x61` | `PUSH B`    | 1     | SP−=2; M[SP+1]:M[SP] ← 0x00:B               | 4      | —     |
| `0x62` | `PUSH F`    | 1     | SP−=2; M[SP+1]:M[SP] ← 0x00:F               | 4      | —     |
| `0x63` | `PUSH A:B`  | 1     | SP−=2; M[SP+1]:M[SP] ← A:B                  | 4      | —     |
| `0x64` | `POP A`     | 1     | A ← M[SP]; SP+=2                             | 4      | Z     |
| `0x65` | `POP B`     | 1     | B ← M[SP]; SP+=2                             | 4      | —     |
| `0x66` | `POP F`     | 1     | F ← M[SP]; SP+=2                             | 4      | todos |
| `0x67` | `POP A:B`   | 1     | A:B ← M[SP+1]:M[SP]; SP+=2                  | 4      | —     |

> **Nota de compatibilidad:** Los opcodes anteriores `0x63`–`0x65` (POP A,
> POP B, POP F) se reubican en `0x64`–`0x66`. `0x63` pasa a `PUSH A:B`,
> nuevo. Se inserta `POP A:B` en `0x67`.

---

### 7.4 Saltos y Llamadas

| Opcode | Mnemónico       | Bytes | Operación                                                   | Ciclos | Flags |
|--------|-----------------|-------|-------------------------------------------------------------|--------|-------|
| `0x70` | `JP nn`         | 3     | PC ← nn  *(salto lejano)*                                   | 6      | —     |
| `0x71` | `JR rel8`       | 2     | PC ← PC + sign\_ext(rel8)  *(salto relativo ±127)*          | 4/6    | —     |
| `0x72` | `JPN page8`     | 2     | PC ← PC[15:8] : page8  *(misma página)*                     | 4      | —     |
| `0x73` | `JP ([nn])`     | 3     | PC ← M[nn+1]:M[nn]  *(salto indirecto)*                     | 8      | —     |
| `0x74` | `JP A:B`        | 1     | PC ← A:B  *(salto computado)*                               | 2      | —     |
| `0x75` | `CALL nn`       | 3     | SP−=2; M[SP+1]:M[SP]←PC; PC←nn                             | 8      | —     |
| `0x76` | `CALL ([nn])`   | 3     | SP−=2; M[SP+1]:M[SP]←PC; PC←M[nn+1]:M[nn]                  | 10     | —     |
| `0x77` | `RET`           | 1     | PC←M[SP+1]:M[SP]; SP+=2                                     | 6      | —     |

> **`JR rel8` vs `JPN page8`:**
> `JR` (relativo) es más general: puede alcanzar cualquier página si se
> encadena. `JPN` es útil en bucles de página única donde se quiere
> garantizar que no hay acceso a 3 bytes.

---

### 7.5 Saltos Condicionales

Todos son **relativos** (`PC ← PC + sign_ext(rel8)`), 2 bytes, no modifican flags.

| Opcode | Mnemónico | Condición | Descripción                                  |
|--------|-----------|-----------|----------------------------------------------|
| `0x80` | `BEQ`     | Z = 1     | Igual / resultado cero                        |
| `0x81` | `BNE`     | Z = 0     | Distinto / resultado no cero                  |
| `0x82` | `BCS`     | C = 1     | Carry set / sin préstamo (A ≥ B unsigned)     |
| `0x83` | `BCC`     | C = 0     | Carry clear / hubo préstamo (A < B unsigned)  |
| `0x84` | `BVS`     | V = 1     | Overflow signed                               |
| `0x85` | `BVC`     | V = 0     | Sin overflow signed                           |
| `0x86` | `BGT`     | G = 1     | A > B con signo (tras CMP)                    |
| `0x87` | `BLE`     | G = 0     | A ≤ B con signo (tras CMP)                    |
| `0x88` | `BGE`     | G=1 ∨ E=1 | A ≥ B con signo                              |
| `0x89` | `BLT`     | G=0 ∧ E=0 | A < B con signo                              |
| `0x8A` | `BHC`     | H = 1     | Half-carry set (útil para BCD)                |
| `0x8B` | `BEQ2`    | E = 1     | A = B (comparación directa de operandos)      |

---

### 7.6 Operaciones ALU — Registro (A op B → A)

| Opcode | Mnemónico  | Bytes | Operación ALU           | Flags modificados  |
|--------|------------|-------|-------------------------|--------------------|
| `0x90` | `ADD`      | 1     | A ← A + B               | C H V Z G E        |
| `0x91` | `ADC`      | 1     | A ← A + B + C           | C H V Z G E        |
| `0x92` | `SUB`      | 1     | A ← A − B               | C H V Z G E        |
| `0x93` | `SBB`      | 1     | A ← A − B − C           | C H V Z G E        |
| `0x94` | `AND`      | 1     | A ← A AND B             | Z G E              |
| `0x95` | `OR`       | 1     | A ← A OR B              | Z G E              |
| `0x96` | `XOR`      | 1     | A ← A XOR B             | Z G E              |
| `0x97` | `CMP`      | 1     | flags ← A − B (A no cambia) | C H V Z G E   |
| `0x98` | `MUL`      | 1     | A ← [A × B](7:0)        | C Z G E            |
| `0x99` | `MUH`      | 1     | A ← [A × B](15:8)       | C Z G E            |

---

### 7.7 Operaciones ALU — Inmediato (A op #n → A)

*B no es modificado; el microcode usa un registro temporal interno.*

| Opcode | Mnemónico      | Bytes | Operación ALU           | Flags modificados  |
|--------|----------------|-------|-------------------------|--------------------|
| `0xA0` | `ADD #n`       | 2     | A ← A + n               | C H V Z G E        |
| `0xA1` | `ADC #n`       | 2     | A ← A + n + C           | C H V Z G E        |
| `0xA2` | `SUB #n`       | 2     | A ← A − n               | C H V Z G E        |
| `0xA3` | `SBB #n`       | 2     | A ← A − n − C           | C H V Z G E        |
| `0xA4` | `AND #n`       | 2     | A ← A AND n             | Z G E              |
| `0xA5` | `OR  #n`       | 2     | A ← A OR n              | Z G E              |
| `0xA6` | `XOR #n`       | 2     | A ← A XOR n             | Z G E              |
| `0xA7` | `CMP #n`       | 2     | flags ← A − n (A no cambia) | C H V Z G E   |

---

### 7.8 Operaciones ALU — Memoria (A op M[...] → A)

#### Modo Página cero / Absoluto

| Opcode | Mnemónico        | Bytes | Operación                | Flags modificados |
|--------|------------------|-------|--------------------------|-------------------|
| `0xB0` | `ADD [n]`        | 2     | A ← A + M[0x00:n]        | C H V Z G E       |
| `0xB1` | `ADD [nn]`       | 3     | A ← A + M[nn]            | C H V Z G E       |
| `0xB2` | `SUB [n]`        | 2     | A ← A − M[0x00:n]        | C H V Z G E       |
| `0xB3` | `SUB [nn]`       | 3     | A ← A − M[nn]            | C H V Z G E       |
| `0xB4` | `AND [n]`        | 2     | A ← A AND M[0x00:n]      | Z G E             |
| `0xB5` | `OR  [n]`        | 2     | A ← A OR  M[0x00:n]      | Z G E             |
| `0xB6` | `XOR [n]`        | 2     | A ← A XOR M[0x00:n]      | Z G E             |
| `0xB7` | `CMP [n]`        | 2     | flags ← A − M[0x00:n]    | C H V Z G E       |

#### Modo indexado por B

| Opcode | Mnemónico        | Bytes | Operación                | Flags modificados |
|--------|------------------|-------|--------------------------|-------------------|
| `0xB8` | `ADD [nn+B]`     | 3     | A ← A + M[nn+B]          | C H V Z G E       |
| `0xB9` | `SUB [nn+B]`     | 3     | A ← A − M[nn+B]          | C H V Z G E       |
| `0xBA` | `AND [nn+B]`     | 3     | A ← A AND M[nn+B]        | Z G E             |
| `0xBB` | `OR  [nn+B]`     | 3     | A ← A OR  M[nn+B]        | Z G E             |
| `0xBC` | `XOR [nn+B]`     | 3     | A ← A XOR M[nn+B]        | Z G E             |
| `0xBD` | `CMP [nn+B]`     | 3     | flags ← A − M[nn+B]      | C H V Z G E       |

---

### 7.9 Operaciones de Un Operando (sobre A ó B)

| Opcode | Mnemónico  | Bytes | Operación                       | Flags modificados |
|--------|------------|-------|---------------------------------|-------------------|
| `0xC0` | `NOT A`    | 1     | A ← ~A                          | Z                 |
| `0xC1` | `NEG A`    | 1     | A ← −A  (= NOT A + 1)           | C H V Z           |
| `0xC2` | `INC A`    | 1     | A ← A + 1                       | C H V Z           |
| `0xC3` | `DEC A`    | 1     | A ← A − 1                       | C H V Z           |
| `0xC4` | `INC B`    | 1     | B ← B + 1                       | —                 |
| `0xC5` | `DEC B`    | 1     | B ← B − 1                       | —                 |
| `0xC6` | `CLR A`    | 1     | A ← 0x00                        | Z                 |
| `0xC7` | `SET A`    | 1     | A ← 0xFF                        | Z                 |
| `0xC8` | `LSL A`    | 1     | A ← A << 1  (0 entra por bit 0) | C Z L             |
| `0xC9` | `LSR A`    | 1     | A ← A >> 1  (0 entra por bit 7) | Z R               |
| `0xCA` | `ASL A`    | 1     | A ← A << 1  (aritmético)        | C V Z L           |
| `0xCB` | `ASR A`    | 1     | A ← A >> 1  (propaga bit 7)     | Z R               |
| `0xCC` | `ROL A`    | 1     | A ← rota izq A (a través de C)  | C Z               |
| `0xCD` | `ROR A`    | 1     | A ← rota der A (a través de C)  | C Z               |
| `0xCE` | `SWAP A`   | 1     | A ← nibbles intercambiados      | Z                 |

> `NEG A`, `INC B` y `DEC B` están implementados en `ALU.vhdl`
> (opcodes ALU `0x10`, `0x1A`, `0x1B` respectivamente).
> La UC enruta el resultado de `INC B`/`DEC B` hacia el registro B; los
> flags generados por la ALU se descartan.

---

### 7.10 Instrucciones de E/S — IN / OUT

Acceden **exclusivamente** al espacio I/O de 256 puertos (§4.2); nunca al mapa de
memoria. El bus I/O tiene su propia señal de selección (`IO_SEL`) independiente de
`MEM_SEL`.

| Opcode | Mnemónico      | Bytes | Operación        | Ciclos | Flags |
|--------|----------------|-------|------------------|--------|-------|
| `0xD0` | `IN  A, #n`    | 2     | A ← IOspace[n]   | 4      | Z     |
| `0xD1` | `IN  A, [B]`   | 1     | A ← IOspace[B]   | 2      | Z     |
| `0xD2` | `OUT #n, A`    | 2     | IOspace[n] ← A   | 4      | —     |
| `0xD3` | `OUT [B], A`   | 1     | IOspace[B] ← A   | 2      | —     |

> **Ciclos (con PFQ activo):**
>
> - Variante `#n` (inmediato): byte de puerto ya en PFQ + 1 ciclo bus I/O + 1 decode/write = **4 ciclos.**
> - Variante `[B]` (indirecta): puerto en B → 1 ciclo bus I/O + 1 write = **2 ciclos.**
>
> **Flag Z:** solo `IN` actualiza Z según el dato leído (encuesta de FIFO, etc.). `OUT` nunca modifica flags.

---

### 7.11 Instrucciones de 16 bits — ADD16 / SUB16

Operan sobre el par **A:B** como entero de 16 bits (A = byte alto, B = byte bajo).
Reutilizan el **sumador EA de 16 bits** (§10.2) como ALU de 16 bits; la ALU de 8 bits
**no** interviene. Ideadas para aritmética de punteros.

| Opcode | Mnemónico    | Bytes | Operación                           | Ciclos | Flags |
|--------|--------------|-------|-------------------------------------|--------|-------|
| `0xE0` | `ADD16 #n`   | 2     | A:B ← A:B + sign\_ext(n, 16)        | 4      | C V Z |
| `0xE1` | `ADD16 #nn`  | 3     | A:B ← A:B + nn                      | 6      | C V Z |
| `0xE2` | `SUB16 #n`   | 2     | A:B ← A:B − sign\_ext(n, 16)        | 4      | C V Z |
| `0xE3` | `SUB16 #nn`  | 3     | A:B ← A:B − nn                      | 6      | C V Z |

> **Flags:**
>
> - **C** = carry/borrow de bit 15. En SUB16 usa la convención *no-borrow* (C=1 → A:B ≥ operando).
> - **V** = overflow signed de 16 bits.
> - **Z** = 1 si el resultado A:B = `0x0000`.
> - G y E no se actualizan (no hay CMP16).
>
> **Ciclos con PFQ activo:**
>
> - `#n` (2 bytes): opcode + imm8 en PFQ → sign-extend a 16 b + suma EA + write A:B = **4 ciclos**.
> - `#nn` (3 bytes): opcode + imm\_lo en PFQ; imm\_hi se lee el siguiente ciclo solapado = **6 ciclos**.
>
> **Nota de diseño:** el resultado escribe los 8 bits altos en A y los 8 bits bajos en B.
> B pierde su rol de índice y A su rol de acumulador durante la instrucción; ambos
> registros quedan con el nuevo puntero al terminar.

---

## 8. Tabla de Efectos sobre los Flags

```
             C  H  V  Z  G  E  R  L
ADD/ADC    [ *  *  *  *  *  *  -  -  ]
SUB/SBB    [ *  *  *  *  *  *  -  -  ]
CMP        [ *  *  *  *  *  *  -  -  ]
AND/OR/XOR [ -  -  -  *  *  *  -  -  ]
NOT        [ -  -  -  *  -  -  -  -  ]
NEG        [ *  *  *  *  -  -  -  -  ]
INC/DEC    [ *  *  *  *  -  -  -  -  ]
INCB/DECB  [ *  *  *  *  -  -  -  -  ]   (resultado en ACC; UC lo ruta a B)
LSL/ASL    [ -  -  */- *  -  -  -  * ]   (ASL activa V)
LSR/ASR    [ -  -  -  *  -  -  *  -  ]
ROL        [ *  -  -  *  -  -  -  -  ]
ROR        [ *  -  -  *  -  -  -  -  ]
MUL/MUH    [ *  -  -  *  *  *  -  -  ]   (C=1 si parte alta ≠ 0)
LD/ST/MOV  [ -  -  -  */- -  -  -  - ]   (Z solo en LD A)
PUSH/POP   [ -  -  -  */- -  -  -  - ]   (Z solo en POP A)
CALL/RET   [ -  -  -  -  -  -  -  -  ]
Saltos     [ -  -  -  -  -  -  -  -  ]
SEC/CLC    [ *  -  -  -  -  -  -  -  ]
IN         [ -  -  -  *  -  -  -  -  ]   (Z según byte leído del espacio I/O)
OUT        [ -  -  -  -  -  -  -  -  ]
ADD16/SUB16[ *  -  *  *  -  -  -  -  ]   (C/V/Z de 16 bits; Z si A:B=0x0000)

*  = modificado según el resultado
-  = no modificado
```

---

## 9. Tabla de Opcodes (mapa de 256 entradas)

```
      0    1    2    3    4    5    6    7    8    9    A    B    C    D    E    F
0x  NOP HALT  SEC  CLC  SEI  CLI  RTI  ---  ---  ---  ---  ---  ---  ---  ---  ---
1x  LDA  LDA  LDA  LDA  LDA LDA  LDA  ---  ---  ---  ---  ---  ---  ---  ---  ---
        B   #n  [n] [nn]  [B][nn+B][n+B]
2x  LDB  LDB  LDB  LDB  LDB LDB  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---
        A   #n  [n] [nn]  [B][nn+B]
3x  STA  STA  STA STA STA  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---
       [n] [nn]  [B][nn+B][n+B]
4x  STB  STB  STB  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---
       [n] [nn][nn+B]
5x LDSP LDSP RDSP RDSP  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---
      #nn A:B   _L   _H
6x PUSHA PUSHB PUSHF POPA POPB POPF  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---
7x   JP   JR  JPN  JP() JP CALL CALL  RET  ---  ---  ---  ---  ---  ---  ---  ---
       nn   r8   p8  [nn] A:B   nn  [nn]
8x  BEQ  BNE  BCS  BCC  BVS  BVC  BGT  BLE  BGE  BLT  BHC BEQ2  ---  ---  ---  ---
9x  ADD  ADC  SUB  SBB  AND   OR  XOR  CMP  MUL  MUH  ---  ---  ---  ---  ---  ---
Ax ADD# ADC# SUB# SBB# AND#  OR# XOR# CMP#  ---  ---  ---  ---  ---  ---  ---  ---
Bx ADD[] ADD[nn] SUB[] SUB[nn] AND[] OR[] XOR[] CMP[] ADD[nn+B] SUB[nn+B] AND[nn+B] OR[nn+B] XOR[nn+B] CMP[nn+B]  ---  ---
Cx  NOT  NEG  INC  DEC INCB DECB  CLR  SET  LSL  LSR  ASL  ASR  ROL  ROR SWAP  ---
Dx IN#  IN[] OUT# OUT[]  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---
    #n   [B]  #n   [B]
Ex ADD16# ADD16## SUB16# SUB16##  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---
      #n   #nn     #n    #nn
Fx  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---
```

Los opcodes marcados con `---` están **reservados** para extensiones futuras.

---

## 10. Micro-Arquitectura — Unidades Hardware

### 10.1 Cola de Prefetch (PFQ — 2 bytes)

```
  ┌─────────┬─────────┬───────┐
  │ PFQ[0]  │ PFQ[1]  │ valid │   ← 2 bytes + 2 bits de validez
  └────┬────┴────┬────┴───────┘
       │         │
  opcode      operando8  (o addr_low del operando de 16 bits)
```

La UC rellena la cola en ciclos de bus libres. Al decodificar:

- **Instrucción de 1 byte**: consume PFQ[0]; adelanta PFQ[1]→PFQ[0] y lanza
  fetch del siguiente byte.
- **Instrucción de 2 bytes**: consume PFQ[0] + PFQ[1]; lanza dos nuevos
  fetches.
- **Instrucción de 3 bytes**: consume PFQ[0] + PFQ[1]; el tercer byte
  (addr_high) se lee en el ciclo siguiente solapado con el inicio de
  ejecución.
- **Salto tomado**: la cola se vacía (flush) y los dos slots se marcan
  inválidos; el fetch retoma desde la nueva dirección.

**Ganancia típica**: −2 ciclos en todas las instrucciones de 2+ bytes.

---

### 10.2 Sumador EA de 16 bits (unidad de cálculo de dirección efectiva)

Unidad dedicada, independiente de la ALU de datos:

```
  base[15:0]  ←  TMP_H:TMP_L  (dirección base de la instrucción)
  + index[7:0] ←  0x00:B        (B extendido a cero en el byte alto)
  ─────────────────────────────
  EAR[15:0]   →  bus de direcciones
```

- La suma empieza en paralelo con la fase de fetch del segundo byte de
  dirección: cuando addr_high llega, el propagate carry del byte bajo ya
  está resuelto → latencia total = 1 ciclo extra (en lugar de 2).
- Para modos sin indexado (`[n]`, `[nn]`) el sumador pasa la dirección base
  directamente (index = 0).
- Para página cero el byte alto de base es siempre `0x00`; la suma se
  reduce a 8 bits y puede hacerse en la mitad del ciclo.

**Ganancia**: `LD A, [nn+B]` pasa de 12 → 8 ciclos.

---

### 10.3 Stack de 16 bits con SP alineado a par

El bus interno del stack es de **16 bits**: PUSH y POP transfieren dos bytes
en un solo ciclo de acceso. Esto requiere que la SRAM de datos exponga un
puerto de 16 bits (o bien que el stack use su propio banco de 16 bits).

**Regla de alineación:** SP es **siempre par**. La UC fuerza el bit 0 de SP
a `0` en la inicialización y en cualquier instrucción que lo modifique
directamente (`LD SP, #nn`, `LD SP, A:B`). Si el programador intenta cargar
un SP impar, el bit 0 se fuerza a 0 silenciosamente; esto se documenta como
comportamiento definido.

```
  PUSH word  →  SP ← SP − 2; M[SP+1]:M[SP] ← word_high:word_low
  POP  word  →  word ← M[SP+1]:M[SP]; SP ← SP + 2
```

SP inicial de reset: `0xFFFE`.

**Ganancia**:

- `CALL nn`    : 14 → 8 ciclos
- `RET`        : 10 → 6 ciclos
- `RTI`        : 12 → 8 ciclos

---

### 10.4 SRAM Rápida (Nexys 7 100T — Artix-7 XC7A100T)

La placa Nexys 7 100T incorpora **4 MB de SRAM asíncrona IS61WV102416BLL**
(ciclo de 10 ns typ). A la frecuencia de reloj objetivo de **450 MHz** (≈ 2.2 ns
por ciclo), la SRAM externa necesita ⌈ 10 ns / 2.2 ns ⌉ = **5 ciclos totales** (4 wait
states). El controlador de bus mantiene `CS#` activo durante los ciclos de espera y
muestrea los datos en el 5.º ciclo.

Además la FPGA dispone de **BlockRAM** (RAMB36/RAMB18) con latencia de
1 ciclo síncrono, ideal para:

| Uso propuesto              | Recurso              | Latencia    |
|----------------------------|----------------------|-------------|
| Página cero (256 B)        | RAMB18 ×1            | 1 ciclo     |
| Stack interno (2 KB)       | RAMB18 ×1            | 1 ciclo     |
| Memoria de programa (ROM)  | RAMB36 ×N            | 1 ciclo     |
| Memoria de datos general   | SRAM IS61WV102416BLL | 5 ciclos (4 wait states @ 450 MHz) |

Con página cero y stack en BlockRAM, los accesos más frecuentes (variables
locales, paso de parámetros) tienen latencia de **1 ciclo**.

---

## 11. Ciclos de Bus — Estimación Revisada

Bases del modelo: prefetch de 2 bytes activo, sumador EA solapado, PUSH/POP
de 16 bits, página cero y stack en BRAM (1 ciclo), memoria general en SRAM
external 10 ns a 50 MHz (1 ciclo de acceso).

| Instrucción        | Sin optim. | **Con optim.** | Δ  | Descripción resumida                                      |
|--------------------|------------|----------------|----|-----------------------------------------------------------|
| NOP / HALT         | 4          | **2**          | −2 | Opcode ya en PFQ; decode+execute en 2                     |
| 1-byte ALU (reg)   | 4          | **2**          | −2 | PFQ tiene el opcode; ALU combinacional                    |
| `LD A, #n`         | 6          | **2**          | −4 | Opcode + imm8 ya en PFQ; solo write A                     |
| `LD A, B`          | 4          | **2**          | −2 | 1 byte en PFQ                                             |
| `LD A, [n]`        | 8          | **4**          | −4 | Opcode+addr en PFQ; read pág-cero BRAM 1 ciclo + write A  |
| `ST A, [n]`        | 8          | **4**          | −4 | Igual; write BRAM 1 ciclo                                 |
| `LD A, [nn]`       | 10         | **6**          | −4 | PFQ da op+addr_low; addr_high 1 ciclo; mem 1 ciclo; wA    |
| `ST A, [nn]`       | 10         | **6**          | −4 | Ídem                                                      |
| `LD A, [nn+B]`     | 12         | **6**          | −6 | PFQ + EA solapada; mem 1 ciclo; write A                   |
| `ST A, [nn+B]`     | 12         | **6**          | −6 | Ídem                                                      |
| `ADD #n`           | 6          | **2**          | −4 | Opcode+imm8 en PFQ; ALU comb; write A                     |
| `ADD [n]`          | 10         | **4**          | −6 | PFQ; BRAM pág-cero; ALU; write A                          |
| `ADD [nn+B]`       | 14         | **8**          | −6 | PFQ + EA solapada; mem; ALU; write A                      |
| `JP nn`            | 10         | **6**          | −4 | PFQ da op+addr_low; addr_high 1c; PC load; flush PFQ      |
| `JR rel8`          | 6/8        | **2/4**        | −4 | PFQ; no-salto=2, salto=4 (flush+fetch)                    |
| `JP A:B`           | 4          | **2**          | −2 | 1-byte; PC←A:B; flush                                     |
| `CALL nn`          | 14         | **8**          | −6 | PFQ; fetch addr_high; SP−2; push PC(16b); PC←nn           |
| `CALL ([nn])`      | 18         | **10**         | −8 | CALL + lectura indirecta de destino                        |
| `RET`              | 10         | **6**          | −4 | PFQ; pop PC(16b) BRAM; SP+2; flush                        |
| `RTI`              | 12         | **8**          | −4 | pop F(16b), pop PC(16b), SP+4; I←1; flush                 |
| `PUSH A`           | 6          | **4**          | −2 | SP−2; write 16b BRAM                                      |
| `POP A`            | 6          | **4**          | −2 | read 16b BRAM; SP+2; write A                              |
| `PUSH A:B`         | 6          | **4**          | —  | SP−2; write 16b BRAM (A=high, B=low)                      |
| `POP A:B`          | 6          | **4**          | —  | read 16b BRAM; SP+2; A←high, B←low                       |
| `BEQ rel8`         | 6/8        | **2/4**        | −4 | Igual que JR (misma lógica)                               |
| `IN A, #n`         | 6          | **4**          | −2 | PFQ; fetch puerto + ciclo I/O                             |
| `IN A, [B]`        | 4          | **2**          | −2 | Puerto en B; sólo ciclo I/O + write A                    |
| `OUT #n, A`        | 6          | **4**          | −2 | PFQ; fetch puerto + ciclo I/O                             |
| `OUT [B], A`       | 4          | **2**          | −2 | Puerto en B; sólo ciclo I/O                              |
| `ADD16 #n`         | —          | **4**          |  — | EA adder 16 b; sign-ext imm8; write A:B                   |
| `ADD16 #nn`        | —          | **6**          |  — | EA adder 16 b; fetch imm16 solapado; write A:B            |
| `SUB16 #n`         | —          | **4**          |  — | Ídem ADD16 #n (sumador en modo resta)                     |
| `SUB16 #nn`        | —          | **6**          |  — | Ídem ADD16 #nn                                            |

> Ciclos expresados en **ciclos de reloj** (1 ciclo = 1 período). Modelo de
> referencia: **450 MHz** (MMCM/PLL Artix-7), BRAM 1 ciclo, SRAM externa
> IS61WV102416BLL 5 ciclos (4 wait states). El bus I/O añade 1 ciclo de
> latencia adicional sobre un acceso de registro.

---

## 12. Ejemplos de Código

### Suma de dos valores en memoria

```asm
    LD  A, [0x10]     ; A ← M[0x0010]
    LD  B, [0x11]     ; B ← M[0x0011]
    ADD               ; A ← A + B
    ST  A, [0x12]     ; M[0x0012] ← A
```

### Recorrer un array indexado por B

```asm
    LD  B, #0x00      ; índice = 0
loop:
    LD  A, [0x20+B]   ; A ← M[0x0020 + B]  (modo indexado)
    ; ... procesar A ...
    INC B             ; B++
    CMP #8            ; ¿B == 8?
    BNE loop
```

### Negar un valor (complemento a dos)

```asm
    LD  A, #0x05      ; A = 5
    NEG A             ; A = -5  (0xFB)
    ; flag C=0 (borrow), V=0, Z=0
```

### ISR mínima (rutina de servicio de interrupción)

```asm
    ; Al entrar, la UC ha hecho push automático de F (16b) y PC (16b); I←0
    ; SP ha bajado 4 bytes (2 × PUSH de 16 bits, alineado a par)
isr:
    PUSH A:B          ; salvar A y B en un solo ciclo de stack (4 ciclos)
    ; ... cuerpo de la ISR ...
    OUT  0x31, A      ; limpiar flag en IFR (escribir 1 en el bit)
    POP  A:B          ; restaurar A y B
    RTI               ; pop F (16b), pop PC (16b); SP+=4; I←1
```

### Llamada a subrutina

```asm
    LD  A, #42
    LD  B, #7
    CALL 0x0200       ; salta a subrutina en 0x0200
    ST   A, [0x50]    ; guarda resultado
    HALT

; Subrutina en 0x0200: A ← A * B (los 8 bits bajos)
0x0200:
    MUL               ; A ← (A × B)[7:0]
    RET
```

### Aritmética de punteros con ADD16

```asm
    ; A:B apunta a la base de un array de structs de 4 bytes (base = 0x2000)
    LD   A, #0x20
    LD   B, #0x00
    ADD16 #4          ; A:B ← 0x2004  (struct[1])  — #n, 4 ciclos
    ADD16 #4          ; A:B ← 0x2008  (struct[2])
    ADD16 #0x01F8     ; A:B ← 0x2200  (salto de bloque > 127 — #nn, 6 ciclos)
    JP   A:B          ; salto computado a la dirección calculada
```

---

## 13. Decisiones de Diseño

### Resueltas

- [x] **NEG A**: implementado en ALU (opcode ALU `0x10`, instrucción `0xC1`).
- [x] **INC B / DEC B**: implementados en ALU (opcodes ALU `0x1A`/`0x1B`, instrucciones `0xC4`/`0xC5`).
- [x] **Modos indexados**: `LD A, [nn+B]` / `ST A, [nn+B]` y variantes implementados.
- [x] **E/S separada**: espacio I/O de 256 puertos independiente del mapa de memoria; instrucciones `IN`/`OUT` (opcodes `0xD0`–`0xD3` — ver §7.10).
- [x] **Interrupciones**: vector IRQ `0xFFFE:0xFFFF`, vector NMI `0xFFFA:0xFFFB`; flag I (flip-flop interno); `SEI`/`CLI`/`RTI`; IMR/IFR en puertos `0x30`/`0x31`.
- [x] **RTI**: opcode `0x06`; restaura F y PC con PUSH/POP de 16 bits.
- [x] **Cola de prefetch de 2 bytes (PFQ)**: reduce en −2 a −4 ciclos todas las instrucciones de 2+ bytes. Flush en salto tomado.
- [x] **Sumador EA de 16 bits dedicado**: cálculo de dirección efectiva solapado con el último fetch de la dirección base. Latencia del modo `[nn+B]`: 6 ciclos (antes 12).
- [x] **PUSH/POP de 16 bits**: bus interno de stack de 16 bits; un solo ciclo de acceso por operación. `CALL` baja a 8 ciclos, `RET` a 6, `RTI` a 8.
- [x] **SP alineado a par**: SP se decrementa/incrementa siempre en 2; bit 0 forzado a `0` en reset y en `LD SP`. SP inicial = `0xFFFE`.
- [x] **Plataforma Nexys 7 100T**: Stack y página cero en BlockRAM (1 ciclo); memoria de programa en BRAM; memoria de datos general en SRAM externa IS61WV102416BLL (1 ciclo a 50 MHz, 1+1 wait a 100 MHz).
- [x] **PUSH A:B / POP A:B**: instrucciones nuevas (opcodes `0x63`/`0x67`) para salvar/restaurar el par en un solo ciclo de stack.
- [x] **Frecuencia de reloj**: 450 MHz mediante MMCM/PLL interno del Artix-7. SRAM IS61WV102416BLL necesita 4 wait states (5 ciclos totales). BRAM sigue con latencia de 1 ciclo.
- [x] **Segundo canal UART (UART1)**: puertos `0x05`–`0x09` (espejo funcional de UART0). `0x0A`–`0x0F` reservados. IMR bit `[3]` habilitado para UART1.
- [x] **Acceso atómico a contadores de 32 bits**: leer `TMRx_CNT0` captura los 32 bits en un registro sombra; CNT1–3 retornan el valor del snapshot. Evita race condition sin necesidad de detener el timer.
- [x] **Instrucciones IN/OUT**: opcodes `0xD0`–`0xD3` asignados. `IN A, #n` (2 B, 4 ciclos), `IN A, [B]` (1 B, 2 ciclos), `OUT #n, A` (2 B, 4 ciclos), `OUT [B], A` (1 B, 2 ciclos). Descritas en §7.10.
- [x] **Unidad de Control**: primera implementación basada en **microcode** (ROM de microinstrucciones). La opción hardwired queda como optimización futura opcional.
- [x] **Instrucciones 16 bits (ADD16/SUB16)**: opcodes `0xE0`–`0xE3`; aritmética de punteros sobre A:B reutilizando el sumador EA. `#n` sign-extendido (4 ciclos), `#nn` literal (6 ciclos). Flags C, V, Z de 16 bits. Ver §7.11.

### Pendientes

- [ ] **Implementación microcode**: pendiente de ISA estable (ya cubierta) **y** diseño del *datapath* (señales de control, ancho de la palabra de microinstrucción, secuenciador de estados). No puede comenzar hasta tener el datapath VHDL esbozado. Después: codificar PFQ flush, solapamiento EA, wait states BRAM/SRAM.
