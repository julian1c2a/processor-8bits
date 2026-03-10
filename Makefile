# Makefile for GHDL

# Directories
SRCDIR_PROC = processor
SRCDIR_TB   = testbenchs
VECTORS_DIR = $(SRCDIR_TB)/vectors
BUILDDIR    = build
BUILDDIR_TESTS = $(BUILDDIR)/build_tests

# GHDL options
GHDL      = /mingw64/bin/ghdl
GHDLFLAGS = --std=08 --workdir=$(BUILDDIR)

# Python interpreter
PYTHON = python

# VHDL files (ALU_pkg.vhdl must be analysed before ALU.vhdl and testbenches)
VHDL_SRCS_PROC = $(SRCDIR_PROC)/ALU_pkg.vhdl $(SRCDIR_PROC)/ALU.vhdl
VHDL_SRCS_TB   = $(wildcard $(SRCDIR_TB)/*.vhdl)

# Object files
OBJS_PROC = $(patsubst $(SRCDIR_PROC)/%.vhdl, $(BUILDDIR)/%.o, $(VHDL_SRCS_PROC))
OBJS_TB   = $(patsubst $(SRCDIR_TB)/%.vhdl,   $(BUILDDIR)/%.o, $(VHDL_SRCS_TB))

# Standard testbench executables (all *_tb.vhdl except ALU_exhaustive_tb)
MANUAL_TB_SRCS  = $(filter-out $(SRCDIR_TB)/ALU_exhaustive_tb.vhdl, $(VHDL_SRCS_TB))
TB_EXECS = $(patsubst $(SRCDIR_TB)/%_tb.vhdl, $(BUILDDIR_TESTS)/%_tb$(EXT), $(MANUAL_TB_SRCS))

# Exhaustive test operations
EX_OPS = NOP ADD ADC SUB SBB LSL LSR ROL ROR INC DEC AND OR XOR NOT ASL \
         PA PB CL SET MUL MUH CMP ASR SWAP

ifeq ($(OS),Windows_NT)
    EXT = .exe
endif

EX_EXEC   = $(BUILDDIR_TESTS)/ALU_exhaustive_tb$(EXT)
EX_CSVS   = $(patsubst %, $(VECTORS_DIR)/%.csv, $(EX_OPS))

# -------------------------------------------------------------------------
.PHONY: all compile test test-exhaustive vectors clean

all: compile

compile: $(BUILDDIR) $(OBJS_PROC) $(OBJS_TB)

# Run the manual testbench
test: $(TB_EXECS)
	@echo "Running manual testbenches..."
	@for tb in $(TB_EXECS); do \
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
# Compilation rules
# -------------------------------------------------------------------------
$(BUILDDIR):
	mkdir -p $(BUILDDIR)

$(BUILDDIR_TESTS):
	mkdir -p $(BUILDDIR_TESTS)

$(BUILDDIR)/%.o: $(SRCDIR_PROC)/%.vhdl | $(BUILDDIR)
	$(GHDL) -a $(GHDLFLAGS) $<

$(BUILDDIR)/%.o: $(SRCDIR_TB)/%.vhdl | $(BUILDDIR)
	$(GHDL) -a $(GHDLFLAGS) $<

$(BUILDDIR_TESTS)/%_tb$(EXT): $(SRCDIR_TB)/%_tb.vhdl $(OBJS_PROC) $(OBJS_TB) | $(BUILDDIR_TESTS)
	$(GHDL) -e $(GHDLFLAGS) -o $@ $(notdir $(basename $<))

clean:
	rm -rf $(BUILDDIR)
	rm -rf $(VECTORS_DIR)
