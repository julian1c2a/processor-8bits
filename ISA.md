# ISA — Arquitectura del Conjunto de Instrucciones

## Procesador de 8 bits con bus de direcciones de 16 bits

> **Estado: borrador v0.2** — ALU extendida (NEG, INCB, DECB); modos indexados; I/O independiente; modelo de interrupciones.

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
| Stack                  | Descendente, SP inicial `0xFFFF` |

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
| `0x05–0x0F` | —      | —   | Reservados (expansión UART / segundo canal) |
| `0x10` | TMR0_CNT0   | R/W | Timer 0: contador bits  7:0  |
| `0x11` | TMR0_CNT1   | R/W | Timer 0: contador bits 15:8  |
| `0x12` | TMR0_CNT2   | R/W | Timer 0: contador bits 23:16 |
| `0x13` | TMR0_CNT3   | R/W | Timer 0: contador bits 31:24 |
| `0x14` | TMR0_RLD0   | R/W | Timer 0: valor de recarga bits  7:0  |
| `0x15` | TMR0_RLD1   | R/W | Timer 0: valor de recarga bits 15:8  |
| `0x16` | TMR0_RLD2   | R/W | Timer 0: valor de recarga bits 23:16 |
| `0x17` | TMR0_RLD3   | R/W | Timer 0: valor de recarga bits 31:24 |
| `0x18` | TMR0_CTRL   | R/W | `[2]` IRQ_EN · `[1]` auto-reload · `[0]` run/stop |
| `0x19–0x1F` | —      | —   | Reservados Timer 0 |
| `0x20` | TMR1_CNT0   | R/W | Timer 1: ídem Timer 0 (offset +0x10) |
| `0x21` | TMR1_CNT1   | R/W | ↑ |
| `0x22` | TMR1_CNT2   | R/W | ↑ |
| `0x23` | TMR1_CNT3   | R/W | ↑ |
| `0x24` | TMR1_RLD0   | R/W | ↑ |
| `0x25` | TMR1_RLD1   | R/W | ↑ |
| `0x26` | TMR1_RLD2   | R/W | ↑ |
| `0x27` | TMR1_RLD3   | R/W | ↑ |
| `0x28` | TMR1_CTRL   | R/W | ↑ |
| `0x29–0x2F` | —      | —   | Reservados Timer 1 |
| `0x30` | IMR         | R/W | Máscara de interrupciones (1=habilitada) `[2]`TMR1 · `[1]`TMR0 · `[0]`UART |
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
| `0x06` | `RTI`      | 1     | SP++; F←M[SP]; SP++; PCL←M[SP]; SP++; PCH←M[SP]; I←1 | todos |

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

| Opcode | Mnemónico  | Bytes | Operación                          | Flags |
|--------|------------|-------|------------------------------------|-------|
| `0x60` | `PUSH A`   | 1     | M[SP] ← A;  SP ← SP − 1           | —     |
| `0x61` | `PUSH B`   | 1     | M[SP] ← B;  SP ← SP − 1           | —     |
| `0x62` | `PUSH F`   | 1     | M[SP] ← F;  SP ← SP − 1           | —     |
| `0x63` | `POP A`    | 1     | SP ← SP + 1;  A ← M[SP]           | Z     |
| `0x64` | `POP B`    | 1     | SP ← SP + 1;  B ← M[SP]           | —     |
| `0x65` | `POP F`    | 1     | SP ← SP + 1;  F ← M[SP]           | todos |

---

### 7.4 Saltos y Llamadas

| Opcode | Mnemónico       | Bytes | Operación                                        | Flags |
|--------|-----------------|-------|--------------------------------------------------|-------|
| `0x70` | `JP nn`         | 3     | PC ← nn  *(salto lejano)*                        | —     |
| `0x71` | `JR rel8`       | 2     | PC ← PC + sign\_ext(rel8)  *(salto relativo ±127)* | —  |
| `0x72` | `JPN page8`     | 2     | PC ← PC[15:8] : page8  *(misma página)*          | —     |
| `0x73` | `JP ([nn])`     | 3     | PC ← M[nn+1]:M[nn]  *(salto indirecto)*          | —     |
| `0x74` | `JP A:B`        | 1     | PC ← A:B  *(salto computado)*                    | —     |
| `0x75` | `CALL nn`       | 3     | M[SP]←PC\_L; SP−−; M[SP]←PC\_H; SP−−; PC ← nn  | —     |
| `0x76` | `CALL ([nn])`   | 3     | Igual pero PC ← M[nn+1]:M[nn]                   | —     |
| `0x77` | `RET`           | 1     | SP++; PC\_H←M[SP]; SP++; PC\_L←M[SP]            | —     |

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
| `0xC1` | `NEG A`    | 1     | A ← −A  (= NOT A + 1)            | C H V Z           |
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

## 8. Tabla de Efectos sobre los Flags

```
           C  H  V  Z  G  E  R  L
ADD/ADC  [ *  *  *  *  *  *  -  - ]
SUB/SBB  [ *  *  *  *  *  *  -  - ]
CMP      [ *  *  *  *  *  *  -  - ]
AND/OR/XOR [-  -  -  *  *  *  -  - ]
NOT      [ -  -  -  *  -  -  -  - ]
NEG      [ *  *  *  *  -  -  -  - ]
INC/DEC  [ *  *  *  *  -  -  -  - ]
INCB/DECB[ *  *  *  *  -  -  -  - ]   (resultado en ACC; UC lo ruta a B)
LSL/ASL  [ -  -  */- *  -  -  -  * ]   (ASL activa V)
LSR/ASR  [ -  -  -  *  -  -  *  - ]
ROL      [ *  -  -  *  -  -  -  - ]
ROR      [ *  -  -  *  -  -  -  - ]
MUL/MUH  [ *  -  -  *  *  *  -  - ]   (C=1 si parte alta ≠ 0)
LD/ST/MOV[ -  -  -  */- -  -  -  - ]   (Z solo en LD A)
PUSH/POP [ -  -  -  */- -  -  -  - ]   (Z solo en POP A)
CALL/RET [ -  -  -  -  -  -  -  - ]
Saltos   [ -  -  -  -  -  -  -  - ]
SEC/CLC  [ *  -  -  -  -  -  -  - ]

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
Dx  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  (IN/OUT — por asignar)
Ex  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---
Fx  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---
```

Los opcodes marcados con `---` están **reservados** para extensiones futuras.

---

## 10. Ciclos de Bus (estimación de micro-operaciones)

| Instrucción       | Ciclos mínimos | Descripción                                              |
|-------------------|----------------|----------------------------------------------------------|
| NOP, HALT         | 4              | 2 fetch + 2 decode/execute                               |
| 1-byte ALU        | 4              | 2 fetch + 2 execute (ALU combinacional)                  |
| `LD A, #n`        | 6              | 2 fetch opcode + 2 fetch imm8 + 2 write A                |
| `LD A, [n]`       | 8              | 2 fetch op + 2 fetch addr + 2 mem read + 2 write A       |
| `LD A, [nn]`      | 10             | 2 fetch op + 2×2 fetch addr16 + 2 mem read + 2 write A  |
| `LD A, [nn+B]`    | 12             | igual que [nn] + 2 ciclos suma de índice                 |
| `ST A, [nn]`      | 10             | similar a LD                                             |
| `CALL nn`         | 14             | fetch(2) + fetch addr16(4) + push PCH(4) + push PCL(4)  |
| `RET`             | 10             | fetch(2) + pop PCL(4) + pop PCH(4)                       |
| `RTI`             | 12             | fetch(2) + pop F(4) + pop PCL(4) + pop PCH(4) + SEI     |
| `BEQ rel8`        | 6 / 8          | 6 sin salto, 8 con salto (actualizar PC)                 |
| `JP nn`           | 10             | 2 fetch + 4 fetch addr16 + 4 load PC                     |

> Estos valores son orientativos. La microarquitectura final determinará los
> ciclos exactos según el diseño de la Unidad de Control.

---

## 11. Ejemplos de Código

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
    ; Al entrar, la UC ha hecho push automático de PCH, PCL, F; I←0
isr:
    PUSH A            ; salvar A
    PUSH B            ; salvar B
    ; ... cuerpo de la ISR ...
    OUT  0x31, A      ; limpiar flag en IFR (escribir 1 en el bit)
    POP  B
    POP  A
    RTI               ; restaura F, PC; I←1
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

---

## 12. Decisiones de Diseño

### Resueltas

- [x] **NEG A**: implementado en ALU (opcode ALU `0x10`, instrucción `0xC1`).
- [x] **INC B / DEC B**: implementados en ALU (opcodes ALU `0x1A`/`0x1B`, instrucciones `0xC4`/`0xC5`).
- [x] **Modos indexados**: `LD A, [nn+B]` / `ST A, [nn+B]` y variantes implementados.
- [x] **E/S separada**: decidido espacio I/O de 256 puertos independiente del mapa de memoria; instrucciones `IN`/`OUT` (opcodes Dx — por asignar).
- [x] **Interrupciones**: vector IRQ `0xFFFE:0xFFFF`, vector NMI `0xFFFA:0xFFFB`; flag I (flip-flop interno); `SEI`/`CLI`/`RTI`; IMR/IFR en puertos `0x30`/`0x31`.
- [x] **RTI**: opcode `0x06`; restaura F, PC e I.

### Pendientes

- [ ] **Instrucciones IN/OUT**: asignar opcodes en rango `0xDx`; definir `IN A, #n` / `IN A, [B]` / `OUT #n, A` / `OUT [B], A`.
- [ ] **Instrucciones de 16 bits sobre A:B**: suma/resta de 16 bits tratando A:B como par (útil para aritmética de punteros).
- [ ] **Wait states**: protocolo de bus para memoria lenta.
- [ ] **Ciclos de reloj exactos por instrucción**: afinar cuando se diseñe la Unidad de Control.
- [ ] **Segundo canal UART**: puertos `0x05`–`0x0F` reservados.
- [ ] **Acceso atómico a contadores de 32 bits**: latch de snapshot al leer TMR_CNT0 para evitar race condition entre bytes.
7x   JP   JR  JPN JP()  JP   CALL CALL  RET  ---  ---  ---  ---  ---  ---  ---  ---
       nn  r8   p8  [nn] A:B   nn  [nn]
8x  BEQ  BNE  BCS  BCC  BVS  BVC  BGT  BLE  BGE  BLT  BHC BEQ2  ---  ---  ---  ---
9x  ADD  ADC  SUB  SBB  AND   OR  XOR  CMP  MUL  MUH  ---  ---  ---  ---  ---  ---
Ax ADD# ADC# SUB# SBB# AND#  OR# XOR# CMP#  ---  ---  ---  ---  ---  ---  ---  ---
Bx ADD[] ADD[nn] SUB[] SUB[nn] AND[] OR[] XOR[] CMP[]  ---  ---  ---  ---  ---  ---  ---  ---
Cx  NOT  NEG  INC  DEC INCB DECB  CLR  SET  LSL  LSR  ASL  ASR  ROL  ROR SWAP  ---
Dx  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---
Ex  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---
Fx  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---  ---

```

Los opcodes marcados con `---` están **reservados** para extensiones futuras
(instrucciones de E/S, multiplicación de 16 bits, etc.).

---

## 10. Ciclos de Bus (estimación de micro-operaciones)

| Instrucción       | Ciclos mínimos | Descripción                                              |
|-------------------|----------------|----------------------------------------------------------|
| NOP, HALT         | 4              | 2 fetch + 2 decode/execute                               |
| 1-byte ALU        | 4              | 2 fetch + 2 execute (ALU combinacional)                  |
| `LD A, #n`        | 6              | 2 fetch opcode + 2 fetch imm8 + 2 write A                |
| `LD A, [n]`       | 8              | 2 fetch op + 2 fetch addr + 2 mem read + 2 write A       |
| `LD A, [nn]`      | 10             | 2 fetch op + 2×2 fetch addr16 + 2 mem read + 2 write A  |
| `ST A, [nn]`      | 10             | similar a LD                                             |
| `CALL nn`         | 14             | fetch(2) + fetch addr16(4) + push PCH(4) + push PCL(4)  |
| `RET`             | 10             | fetch(2) + pop PCL(4) + pop PCH(4)                       |
| `BEQ rel8`        | 6 / 8          | 6 sin salto, 8 con salto (actualizar PC)                 |
| `JP nn`           | 10             | 2 fetch + 4 fetch addr16 + 4 load PC                     |

> Estos valores son orientativos. La microarquitectura final determinará los
> ciclos exactos según el diseño de la Unidad de Control.

---

## 11. Ejemplos de Código

### Suma de dos valores en memoria

```asm
    LD  A, [0x10]     ; A ← M[0x0010]
    LD  B, [0x11]     ; B ← M[0x0011]
    ADD               ; A ← A + B
    ST  A, [0x12]     ; M[0x0012] ← A
```

### Bucle: suma un array de 8 elementos (long. en 0x00, datos en 0x01..0x08)

```asm
    LD  A, #0x00      ; acumulador de suma = 0
    LD  B, [0x00]     ; B = contador = n
loop:
    CMP #0            ; ¿B == 0?
    BEQ done          ; si Z=1, fin
    ADD [B]           ; A ← A + M[B]  (página cero vía B)
    LD  B, B          ; no existe autodecrement; cargamos B para DEC
    ; Necesitamos guardar A temporalmente para usar DEC B:
    PUSH A
    LD  A, B
    DEC A
    LD  B, A
    POP  A
    JR  loop
done:
    ST  A, [0x09]
```

> Este ejemplo muestra una limitación del ISA: no hay instrucción
> `DEC B` que preserve A. Se propone añadir `DEC B` (opcode `0xC5`) para
> evitar el push/pop. ✓ (ya está incluido en la sección 7.9)

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

### Salto relativo vs salto lejano

```asm
    CMP #100
    BLT  near_target  ; salto relativo ±127 bytes si A < 100

    ; Si el destino está fuera de ±127 bytes:
    BGE  skip
    JP   far_target   ; salto lejano (3 bytes) si A < 100
skip:
```

---

## 12. Decisiones de Diseño Pendientes

- [ ] **Interrupciones**: definir vector de IRQ en `0xFFFE:0xFFFF` y comportamiento de `SEI`/`CLI`.
- [ ] **Modos indexados**: `LD A, [nn + B]` (B como índice) — muy útil para arrays; requiere hardware de suma en la fase de cálculo de dirección.
- [ ] **NEG A**: implementar en ALU o en microcode como NOT+INC.
- [ ] **E/S mapeada en memoria vs puertos separados**: `IN`/`OUT` con espacio de direcciones independiente (como Z80) o usar `LD`/`ST` con rango reservado.
- [ ] **Instrucciones de 16 bits sobre A:B**: operaciones de 16 bits tratando A:B como par (útil para aritmética de punteros).
- [ ] **Wait states**: protocolo de bus para memoria lenta.
- [ ] **Ciclos de reloj exactos por instrucción**: afina cuando se diseñe la UC.
