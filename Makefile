# Makefile for GHDL

# Directories
SRCDIR_PROC = processor
SRCDIR_TB   = testbenchs
VECTORS_DIR = $(SRCDIR_TB)/vectors
BUILDDIR    = build
BUILDDIR_TESTS = $(BUILDDIR)/build_tests

# GHDL options
# En MSYS2/ucrt64 el binario está en /ucrt64/bin/ghdl
# Desde PowerShell: añadir C:\msys64\ucrt64\bin al PATH o usar mingw32-make
GHDL      = /ucrt64/bin/ghdl
GHDLFLAGS = --std=08 --workdir=$(BUILDDIR)
GHDLFLAGS_TB = --std=08 --workdir=$(BUILDDIR) -frelaxed

# En Windows, asegurar que ucrt64/bin se busque antes que usr/bin (Cygwin) para
# que GHDL use el gcc de MinGW/ucrt64 al elaborar y enlazar los ejecutables.
ifeq ($(OS),Windows_NT)
    export PATH := C:/msys64/ucrt64/bin:$(PATH)
endif

# Python interpreter
PYTHON = python

# VHDL files - Compilation order matters!
VHDL_SRCS_PROC = \
    $(SRCDIR_PROC)/Utils_pkg.vhdl \
    $(SRCDIR_PROC)/CONSTANTS_pkg.vhdl \
    $(SRCDIR_PROC)/ALU_pkg.vhdl \
    $(SRCDIR_PROC)/ALU_functions_pkg.vhdl \
    $(SRCDIR_PROC)/DataPath_pkg.vhdl \
    $(SRCDIR_PROC)/AddressPath_pkg.vhdl \
    $(SRCDIR_PROC)/ControlUnit_pkg.vhdl \
    $(SRCDIR_PROC)/Pipeline_pkg.vhdl \
    $(SRCDIR_PROC)/ALU.vhdl \
    $(SRCDIR_PROC)/DataPath.vhdl \
    $(SRCDIR_PROC)/AddressPath.vhdl \
    $(SRCDIR_PROC)/ControlUnit.vhdl \
    $(SRCDIR_PROC)/Processor_Top.vhdl

VHDL_SRCS_TB   = $(wildcard $(SRCDIR_TB)/*.vhdl)

# Object files
OBJS_PROC = $(patsubst $(SRCDIR_PROC)/%.vhdl, $(BUILDDIR)/%.o, $(VHDL_SRCS_PROC))
OBJS_TB   = $(patsubst $(SRCDIR_TB)/%.vhdl,   $(BUILDDIR)/%.o, $(VHDL_SRCS_TB))

# Standard testbench executables (excluir exhaustivo e interactivo)
MANUAL_TB_SRCS  = $(filter-out $(SRCDIR_TB)/ALU_exhaustive_tb.vhdl \
                               $(SRCDIR_TB)/ALU_run_tb.vhdl, \
                               $(VHDL_SRCS_TB))
TB_EXECS = $(patsubst $(SRCDIR_TB)/%_tb.vhdl, $(BUILDDIR_TESTS)/%_tb$(EXT), $(MANUAL_TB_SRCS))

# Exhaustive test operations
EX_OPS = NOP ADD ADC SUB SBB LSL LSR ROL ROR INC DEC AND IOR XOR NOT ASL \
         PSA PSB CLR SET MUL MUH CMP ASR SWP NEG INB DEB

ifeq ($(OS),Windows_NT)
    EXT = .exe
endif

EX_EXEC   = $(BUILDDIR_TESTS)/ALU_exhaustive_tb$(EXT)
EX_CSVS   = $(patsubst %, $(VECTORS_DIR)/%.csv, $(EX_OPS))

# Simulador interactivo
RUN_EXEC  = $(BUILDDIR_TESTS)/ALU_run_tb$(EXT)

# Processor_Top_tb executable (elaborado una vez, ejecutado con -g por programa)
PROC_TB_EXEC = $(BUILDDIR_TESTS)/Processor_Top_tb$(EXT)

# Lista de programas de test del procesador (01..13)
PROC_TB_NUMS = 01 02 03 04 05 06 07 08 09 10 11 12 13

# -------------------------------------------------------------------------
.PHONY: all compile test test-exhaustive vectors sim sim-compile clean \
        proc_tb_compile test-proc $(addprefix proc_tb_, $(PROC_TB_NUMS))

all: compile

compile: $(BUILDDIR) $(OBJS_PROC) $(OBJS_TB)

# Run the manual testbench
test: $(TB_EXECS)
	@echo "Running manual testbenches..."
	@for tb in $(TB_EXECS); do \
		echo "Executing $$tb..."; \
		$$tb --wave=$(BUILDDIR)/$$(basename $$tb .exe).ghw; \
	done

# Generate all CSV vector files with the Python oracle
vectors: $(EX_CSVS)

$(VECTORS_DIR)/%.csv: $(SRCDIR_TB)/alu_ref.py
	@mkdir -p $(VECTORS_DIR)
	$(PYTHON) $(SRCDIR_TB)/alu_ref.py $*

# Build the exhaustive testbench executable (compiled once, run per-op)
$(EX_EXEC): $(OBJS_PROC) $(OBJS_TB) | $(BUILDDIR_TESTS)
	$(GHDL) -e $(GHDLFLAGS) -o $@ ALU_exhaustive_tb

# Build the interactive run testbench executable
$(RUN_EXEC): $(OBJS_PROC) $(OBJS_TB) | $(BUILDDIR_TESTS)
	$(GHDL) -e $(GHDLFLAGS) -o $@ ALU_run_tb

# Solo compilar el simulador interactivo (sin lanzarlo)
sim-compile: $(RUN_EXEC)

# Compilar y mostrar el comando para lanzar el simulador.
# NOTA: make no puede lanzar programas interactivos en mintty porque
# winpty falla cuando es nieto del terminal (mintty→make→winpty).
# Hay que ejecutar alu_sim.py directamente desde el prompt de mintty.
sim: $(RUN_EXEC)
	@echo ""
	@echo "  Simulador compilado: $(RUN_EXEC)"
	@echo ""
	@echo "  Modo interactivo — ejecuta directamente desde mintty:"
	@echo "    winpty $(PYTHON) $(SRCDIR_TB)/alu_sim.py"
	@echo ""
	@echo "  Calculo directo (sin winpty):"
	@echo "    $(PYTHON) $(SRCDIR_TB)/alu_sim.py ADD 10 20"
	@echo "    $(PYTHON) $(SRCDIR_TB)/alu_sim.py ADC 0xFF 0x01 1"
	@echo ""

# Run exhaustive tests for all operations
test-exhaustive: $(EX_EXEC) $(EX_CSVS)
	@echo "Running exhaustive tests..."
	@fail=0; \
	for op in $(EX_OPS); do \
		$(EX_EXEC) -gVECTOR_FILE=$(VECTORS_DIR)/$$op.csv \
			--wave=$(BUILDDIR)/exhaustive_$$op.ghw 2>&1 \
			| tee /dev/stderr | grep -q "FAIL" && fail=1 || true; \
	done; \
	if [ $$fail -eq 0 ]; then echo "=== Todos los tests exhaustivos PASS ==="; \
	else echo "=== Hay FALLOS en los tests exhaustivos ===" && exit 1; fi

# -------------------------------------------------------------------------
# Processor integration testbenches (TB-01 .. TB-13)
# -------------------------------------------------------------------------

# Compilar/elaborar el ejecutable Processor_Top_tb una sola vez
proc_tb_compile: $(PROC_TB_EXEC)

$(PROC_TB_EXEC): $(OBJS_PROC) $(OBJS_TB) | $(BUILDDIR_TESTS)
	$(GHDL) -e $(GHDLFLAGS_TB) -o $@ Processor_Top_tb

# Regla genérica: proc_tb_01, proc_tb_02 … proc_tb_13
# Convierte el sufijo numérico (con cero) en el valor del generic PROGRAM_SEL
define PROC_TB_RULE
proc_tb_$(1): $(PROC_TB_EXEC)
	@echo "=== Procesador TB-$(1) (PROGRAM_SEL=$(shell expr $(1) + 0)) ==="
	$(PROC_TB_EXEC) -gPROGRAM_SEL=$(shell expr $(1) + 0) \
		--wave=$(BUILDDIR)/proc_$(1).ghw

endef
$(foreach n,$(PROC_TB_NUMS),$(eval $(call PROC_TB_RULE,$(n))))

# Ejecutar todos los programas de integración del procesador
test-proc: proc_tb_compile
	@echo "=== Ejecutando todos los tests de integración del procesador ==="
	@fail=0; \
	for n in $(PROC_TB_NUMS); do \
		nval=$$(expr $$n + 0); \
		echo "--- proc_tb_$$n (PROGRAM_SEL=$$nval) ---"; \
		$(PROC_TB_EXEC) -gPROGRAM_SEL=$$nval \
			--wave=$(BUILDDIR)/proc_$$n.ghw 2>&1 || fail=1; \
	done; \
	if [ $$fail -eq 0 ]; then echo "=== TODOS LOS TESTS PASS ==="; \
	else echo "=== HAY FALLOS ===" && exit 1; fi

# -------------------------------------------------------------------------
# Compilation rules
# -------------------------------------------------------------------------
$(BUILDDIR):
	mkdir -p $(BUILDDIR)

$(BUILDDIR_TESTS):
	mkdir -p $(BUILDDIR_TESTS)

$(BUILDDIR)/%.o: $(SRCDIR_PROC)/%.vhdl | $(BUILDDIR)
	$(GHDL) -a $(GHDLFLAGS) $<

$(BUILDDIR)/%.o: $(SRCDIR_TB)/%.vhdl | $(BUILDDIR)
	$(GHDL) -a $(GHDLFLAGS_TB) $<

$(BUILDDIR_TESTS)/%_tb$(EXT): $(SRCDIR_TB)/%_tb.vhdl $(OBJS_PROC) $(OBJS_TB) | $(BUILDDIR_TESTS)
	$(GHDL) -e $(GHDLFLAGS) -o $@ $(notdir $(basename $<))

clean:
	rm -rf $(BUILDDIR)
	rm -rf $(VECTORS_DIR)
