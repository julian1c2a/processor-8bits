# TODO - Tareas Pendientes del Procesador

Este archivo lista las funcionalidades de la ISA v0.6 que aún no están implementadas en la Unidad de Control (`ControlUnit.vhdl`).

---

## Prioridad Media (Completar Sets de Instrucciones Faltantes)

Muchas instrucciones están definidas en la ISA pero aún no tienen entrada en el `case` del decodificador de la UC.

- [x] **Operaciones Lógicas (`XOR`)**
  - [x] Opcodes `0x96`, `0xA6` implementados.

- [x] **Instrucciones de Pila para B (`PUSH B`, `POP B`)**
    - [x] Opcodes `0x61`, `0x65`.
    - [x] Añadidos al decodificador y estados de ejecución.

- [x] **Operaciones Unarias Faltantes**
  - [x] `INC B` (0xC4), `DEC B` (0xC5).
  - [x] `CLR A` (0xC6), `SET A` (0xC7), `SWAP A` (0xCE).
  - [x] Añadidas al decodificador y `S_EXEC_ALU_UNARY`.

- [x] **Instrucciones de Control de Flags (`SEC`, `CLC`)**
    - [x] Opcodes `0x02`, `0x03`.
    - [x] Implementado usando operaciones ALU (CMP/AND) con máscara de flags.


- [ ] **Saltos y Llamadas Indirectas (`JP ([nn])`, `CALL ([nn])`)**
  - [ ] Opcodes `0x73`, `0x76`.
  - [ ] Requiere leer una dirección de memoria y luego usarla como destino.

- [ ] **Salto Relativo Incondicional (`JR rel8`)**
  - [ ] Opcode `0x71`.
  - [ ] Similar a `BEQ` pero sin comprobar condición (siempre tomado).

## Prioridad Baja (Optimizaciones y Arquitectura Avanzada v0.6)

Estas características están definidas en la ISA pero requieren cambios estructurales significativos o son optimizaciones sobre la arquitectura actual.

- [x] **Interrupciones Básicas (`IRQ`, `NMI`)**
  - [x] Lógica de prioridad, registro `I`, secuencia de entrada (Push PC/F) y vectores implementada.
  - [x] Instrucciones `SEI`, `CLI`, `RTI` implementadas.

- [ ] **Pipeline de 2 Etapas (`DECODE | EXEC+WB`)**
  - [ ] Reestructurar la `ControlUnit` y el `DataPath` para incluir registros de pipeline.
  - [ ] Implementar lógica de **forwarding** para evitar stalls.

- [ ] **Especulación de Dirección BRAM**
  - [ ] Modificar la FSM para emitir direcciones a la BRAM durante la etapa de decodificación.

- [ ] **BRAM True Dual-Port (TDP)**
  - [ ] Separar el acceso a la pila (Stack) a un puerto de memoria dedicado para paralelizar `PUSH`/`POP` con otras operaciones.

- [ ] **Link Register (LR) y `BSR`/`RET LR`**
  - [ ] Añadir el registro LR al `AddressPath`.
  - [ ] Implementar la lógica para `BSR` (Branch to Subroutine) y `RET LR`.

- [ ] **Return Address Stack (RAS)**
  - [ ] Implementar la pila hardware de 4 niveles para la predicción de saltos de `RET`.
