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

- [ ] **Testbench del pipeline**
  - [ ] Verificar solapamiento FETCH+EXEC con programa de ALU intensiva.
  - [ ] Verificar stalls RAW (escritura A seguida de lectura A en instrucción siguiente).
  - [ ] Verificar flush en salto tomado (BEQ, JR, JP nn).
