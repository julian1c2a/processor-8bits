# Makefile for GHDL

# Directories
SRCDIR_PROC = processor
SRCDIR_TB = testbenchs
BUILDDIR = build
BUILDDIR_TESTS = $(BUILDDIR)/build_tests

# GHDL options
GHDL = ghdl
GHDLFLAGS = --std=08 --workdir=$(BUILDDIR)

# VHDL files
VHDL_SRCS_PROC = $(wildcard $(SRCDIR_PROC)/*.vhdl)
VHDL_SRCS_TB = $(wildcard $(SRCDIR_TB)/*.vhdl)

# Object files
OBJS_PROC = $(patsubst $(SRCDIR_PROC)/%.vhdl, $(BUILDDIR)/%.o, $(VHDL_SRCS_PROC))
OBJS_TB = $(patsubst $(SRCDIR_TB)/%.vhdl, $(BUILDDIR)/%.o, $(VHDL_SRCS_TB))

# Testbench executables
ifeq ($(OS),Windows_NT)
    EXT = .exe
endif
TB_EXECS = $(patsubst $(SRCDIR_TB)/%_tb.vhdl, $(BUILDDIR_TESTS)/%_tb$(EXT), $(VHDL_SRCS_TB))

.PHONY: all compile test clean

all: compile

compile: $(OBJS_PROC) $(OBJS_TB)

test: $(TB_EXECS)
	@echo "Running testbenches..."
	@for tb in $(TB_EXECS); do \
		$$tb --wave=$(BUILDDIR)/$$(basename $$tb .exe).ghw; \
	done

$(BUILDDIR)/%.o: $(SRCDIR_PROC)/%.vhdl
	$(GHDL) -a $(GHDLFLAGS) $<

$(BUILDDIR)/%.o: $(SRCDIR_TB)/%.vhdl
	$(GHDL) -a $(GHDLFLAGS) $<

$(BUILDDIR_TESTS)/%_tb$(EXT): $(SRCDIR_TB)/%_tb.vhdl $(OBJS_PROC) $(OBJS_TB)
	$(GHDL) -e $(GHDLFLAGS) -o $(BUILDDIR)/$(patsubst $(SRCDIR_TB)/%_tb.vhdl, %_tb, $<)$(EXT) $(patsubst $(SRCDIR_TB)/%_tb.vhdl, %_tb, $<)
	mv $(BUILDDIR)/$(patsubst $(SRCDIR_TB)/%_tb.vhdl, %_tb, $<)$(EXT) $@

clean:
	rm -rf $(BUILDDIR)/*
