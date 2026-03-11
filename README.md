# VHDL 8-bit Processor

Implementación de un procesador de 8 bits con una arquitectura de conjunto de instrucciones (ISA) personalizada, diseñado en VHDL (estándar 2008).

El diseño sigue las mejores prácticas de la industria, incluyendo una arquitectura de doble datapath, pipeline, y un sistema de paquetes VHDL modular y parametrizable para facilitar el mantenimiento y la escalabilidad.

## Características de la Arquitectura (ISA v0.6)

* **Arquitectura Acumulador:** El registro `A` (R0) actúa como operando principal y destino.
* **Banco de Registros:** 8 registros de 8 bits de propósito general (R0-R7).
* **Doble Datapath:**
  * **Data Path (8 bits):** Gestiona la ALU y el banco de registros.
  * **Address Path (16 bits):** Gestiona el PC, SP y el cálculo de direcciones efectivas.
* **Pipeline de 2 Etapas:** `DECODE | EXEC+WB` con forwarding para minimizar stalls.
* **Especulación de Dirección:** Optimización para accesos a BRAM (memoria interna de la FPGA).
* **Stack de 16 bits:** Operaciones `PUSH`/`POP` de palabra completa para mayor eficiencia.
* **Frecuencia Objetivo:** 450 MHz en dispositivos Artix-7 (Nexys 7 100T).

---

## Estado Actual de la Implementación

La implementación VHDL actual ha completado la infraestructura hardware principal (DataPath, AddressPath, ALU) y una Unidad de Control multiciclo funcional que soporta un subconjunto significativo de la ISA, incluyendo:

* **Carga/Almacenamiento:** Registros (A, B), Inmediato (#n), Absoluto ([nn]), Página Cero ([n]), Indexado ([nn+B]) e Indirecto ([B]).
* **Operaciones ALU:** Aritméticas (ADD, SUB), Lógicas (AND, OR), Comparación (CMP), Incremento/Decremento (INC, DEC), Negación (NEG) y Desplazamientos/Rotaciones.
* **Flujo de Control:** Saltos incondicionales (JP) y toda la familia de saltos condicionales relativos (BEQ, BNE, BCS, etc.).
* **Pila (Stack):** Soporte completo para PUSH/POP de registros (A, B, F) y pares (A:B).
* **Subrutinas:** Implementación completa de `CALL nn` y `RET`.
* **E/S:** Instrucciones `IN` y `OUT` con direccionamiento inmediato e indirecto.

Las características más avanzadas de la ISA v0.6 (pipeline, BSR, RAS, etc.) están definidas como el objetivo final, pero aún no están implementadas en la Unidad de Control actual
---

## Documentación de la Arquitectura

La documentación técnica detallada de cada subsistema se encuentra en los siguientes archivos:

* **ISA - Conjunto de Instrucciones:** La especificación completa del procesador, incluyendo modos de direccionamiento, mapa de memoria y opcodes.

### Módulos Hardware

1. **Processor Top Level:** Describe la integración de los componentes principales.
2. **Data Path (8-bit):** Explica el funcionamiento del banco de registros, la ALU y el bus de datos.
3. **Address Path (16-bit):** Detalla la gestión del PC, SP y el sumador de direcciones.
4. **ALU (Unidad Aritmético-Lógica):** Especificación de las operaciones y flags de la ALU.

---

## Estructura del Proyecto

```
├── processor/          # Código fuente VHDL de los componentes del procesador
│   ├── Processor_Top.vhdl
│   ├── ControlUnit.vhdl
│   ├── DataPath.vhdl
│   ├── AddressPath.vhdl
│   ├── ALU.vhdl
│   └── *.pkg.vhdl      # Paquetes de definiciones y constantes
│
├── testbenchs/         # Testbenches y herramientas de simulación
│   ├── ALU_exhaustive_tb.vhdl
│   ├── Processor_Top_tb.vhdl
│   ├── alu_ref.py      # Oráculo de referencia en Python
│   └── vectors/        # Vectores de prueba generados (no versionados)
│
└── *.md                # Documentación en formato Markdown
```

## Verificación y Pruebas

El proyecto utiliza un sistema de verificación exhaustivo para la ALU (con oráculo en Python) y un testbench de sistema (`Processor_Top_tb.vhdl`) que carga y ejecuta programas de prueba para validar la integración de los componentes y la lógica de control.

* **Detalles de los Testbenches**

---

## Licencia

Este proyecto se distribuye bajo la licencia MIT. Ver el archivo `LICENSE` para más detalles.

Copyright (c) 2026 MICROELECTRÓNICA26.UMA.EII

---
