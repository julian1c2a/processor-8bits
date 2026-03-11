# VHDL 8-bit Processor

Implementación de un procesador de 8 bits con una arquitectura de conjunto de instrucciones (ISA) personalizada, diseñado en VHDL (estándar 2008) y optimizado para FPGAs Artix-7.

El diseño sigue las mejores prácticas de la industria, incluyendo una arquitectura de doble datapath, pipeline, y un sistema de paquetes VHDL modular y parametrizable para facilitar el mantenimiento y la escalabilidad.

## Características Principales

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
│   ├── alu_ref.py      # Oráculo de referencia en Python
│   └── vectors/        # Vectores de prueba generados (no versionados)
│
└── *.md                # Documentación en formato Markdown
```

## Verificación y Pruebas

El proyecto utiliza un sistema de verificación exhaustivo para la ALU, con un oráculo en Python que genera millones de vectores de prueba para cubrir todas las combinaciones de entradas.

* **Detalles de los Testbenches**

---

## Licencia

Este proyecto se distribuye bajo la licencia MIT. Ver el archivo `LICENSE` para más detalles.

Copyright (c) 2026 MICROELECTRÓNICA26.UMA.EII

---
