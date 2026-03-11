# TODO - Tareas Pendientes del Procesador

Este archivo lista las funcionalidades de la ISA v0.6 que aún no están implementadas en la Unidad de Control (`ControlUnit.vhdl`).

---

## Prioridad Media (Instrucciones Faltantes en UC)

- [ ] **Instrucciones Faltantes**
    - [x] `JPN page8` (0x72) - Salto en la misma página.
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
