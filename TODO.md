# TODO - Tareas Pendientes del Procesador

Este archivo lista el estado de implementación de la ISA v0.7 en la Unidad de Control (`ControlUnit.vhdl`).

---

## Completado en v0.7

- [x] **Interrupciones Básicas (`IRQ`, `NMI`)**
  - [x] Lógica de prioridad, registro `I`, secuencia de entrada (Push PC/F) y vectores.
  - [x] Instrucciones `SEI`, `CLI`, `RTI`.

- [x] **Pipeline de 4 Etapas (`FETCH | DECODE | EXEC | WB`)**
  - [x] Registros de pipeline IF/ID e ID/EX (`Pipeline_pkg.vhdl`).
  - [x] Solapamiento FETCH+EXEC para instrucciones ALU de 1 ciclo.
  - [x] Detección de hazards RAW con stalls.
  - [x] Flush de pipeline en saltos tomados y ramas.
  - [x] Sub-FSM DECODE (`dss`) para instrucciones multi-byte (1/2/3 bytes).
  - [x] Sub-FSM EXEC (`ess`) para instrucciones multi-ciclo (CALL, RET, PUSH, POP…).

- [x] **Testbenches de sistema (`Processor_Top_tb.vhdl`) — TB-01 a TB-13: ALL PASS**
  - [x] TB-01 @1415ns — Instrucciones unarias (NOT, NEG, INC, DEC, CLR, SET, SWAP).
  - [x] TB-02 @1825ns — ALU registro (ADD, ADC, SUB, SBB, AND, OR, XOR, CMP, MUL, MUH).
  - [x] TB-03 @1345ns — ALU inmediato.
  - [x] TB-04 @1325ns — Desplazamientos y rotaciones (LSL, LSR, ASL, ASR, ROL, ROR).
  - [x] TB-05 @1795ns — Cargas y almacenamientos (modos: #n, [n], [nn], [B], [nn+B]).
  - [x] TB-06 @1585ns — Saltos incondicionales (JP nn, JR, JPN, JP([nn]), JP A:B).
  - [x] TB-07 @2515ns — Saltos condicionales (BEQ..BEQ2).
  - [x] TB-08 @1025ns — CALL/RET.
  - [x] TB-09 @1125ns — PUSH/POP (A, B, F, A:B).
  - [x] TB-10 @935ns  — Stack Pointer (LD SP, RD SP_L/H).
  - [x] TB-11 @1495ns — ADD16/SUB16.
  - [x] TB-12 @1615ns — Interrupciones IRQ y NMI con RTI.
  - [x] TB-13 @515ns  — Pipeline hazards: stall RAW (LD A→ADD #0) y flush (JP sobre INC A).

---

## Pendiente — Optimizaciones Avanzadas (v0.8+)

- [ ] **Forwarding / Bypassing** (v0.8)
  - [ ] Bypass EX→EX y MEM→EX para eliminar stalls RAW en secuencias A←op(A,B).
  - [ ] Actualmente se insertan stalls de 1 ciclo por dependencia RAW.

- [ ] **Especulación de Dirección BRAM**
  - [ ] Emitir la dirección al bus en el último ciclo de DECODE para modos `[n]`, `[B]`, stack.
  - [ ] Ganancia estimada: −1 ciclo en `LD/ST [n]`, `PUSH`/`POP`.

- [ ] **BRAM True Dual-Port (TDP)**
  - [ ] Port B exclusivo para la pila (stack) — permite solapar push/pop con fetch.
  - [ ] `CALL nn` baja de 6 a 4 ciclos, `RET` de 3 a 2 ciclos.

- [ ] **Link Register (LR) y `BSR`/`RET LR`**
  - [ ] LR ya existe en `AddressPath`. Falta cablear `Load_LR` desde la UC pipeline.
  - [ ] Instrucción `BSR rel8` (opcode `0xF0`): 2 bytes, 4 ciclos.
  - [ ] Instrucción `RET LR` (opcode `0xF1`): 1 byte, 1 ciclo.

- [ ] **Return Address Stack (RAS)**
  - [ ] Pila hardware de 4 entradas para predicción especulativa de `RET`.

- [ ] **PUSH LR / POP LR**
  - [ ] Opcodes provisionales `0x68`/`0x69`. Actualizar §7.3, §8, §9 y §11 de ISA.md.
