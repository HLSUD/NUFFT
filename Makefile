# CURAFFT Makefile




CC   ?= gcc
CXX  ?= g++
NVCC ?= nvcc


CFLAGS    ?= -fPIC -O3 -funroll-loops -march=native
CXXFLAGS  ?= $(CFLAGS) -std=c++14
NVCCFLAGS ?= -std=c++14 -ccbin=$(CXX) \
	     --default-stream per-thread -Xcompiler "$(CXXFLAGS)"

# For debugging, tell nvcc to add symbols to host and device code respectively,
#NVCCFLAGS+= -g -G
# and enable cufinufft internal flags.
#NVCCFLAGS+= -DINFO -DDEBUG -DRESULT -DTIME


#set your cuda path
CUDA_ROOT := /usr/local/cuda

# Common includes
INC += -I$(CUDA_ROOT)/include -Iinclude/cuda_sample

# NVCC-specific libs
NVCC_LIBS_PATH += -L$(CUDA_ROOT)/lib64

ifdef NVCC_STUBS
    $(info detected CUDA_STUBS -- setting CUDA stubs directory)
    NVCC_LIBS_PATH += -L$(NVCC_STUBS)
endif

LIBS += -lm -lcudart -lstdc++ -lnvToolsExt -lcufft -lcuda



# Include header files
INC += -I include

#??
LIBNAME=libcurafft
DYNAMICLIB=lib/$(LIBNAME).so
STATICLIB=lib-static/$(LIBNAME).a

BINDIR=bin

HEADERS = include/curafft_opts.h include/curafft_plan.h include/dataType.h src/utils.h \
	src/FT/conv_invoker.h src/FT/conv.cuh src/FT/matrix.cuh src/FT/nufft.cuh src/FT/visibility.h
#later put some file into the contrib
#CONTRIBOBJS=contrib/dirft2d.o contrib/common.o contrib/spreadinterp.o contrib/utils_fp.o

# We create three collections of objects:
#  Double (_64), Single (_32), and floating point agnostic (no suffix)
# add contrib/legendre_rule_fast.o to curafftobjs later
CURAFFTOBJS=src/utils.o
CUFINUFFTOBJS_64=src/FT/conv_invoker.o src/FT/conv.o

# $(CONTRIBOBJS)
CURAFFTOBJS_32=$(CURAFFTOBJS_64:%.o=%_32.o)


%_32.o: %.cpp $(HEADERS)
	$(CXX) -DSINGLE -c $(CXXFLAGS) $(INC) $< -o $@
%_32.o: %.c $(HEADERS)
	$(CC) -DSINGLE -c $(CFLAGS) $(INC) $< -o $@
%_32.o: %.cu $(HEADERS)
	$(NVCC) -DSINGLE --device-c -c $(NVCCFLAGS) $(INC) $< -o $@
%.o: %.cpp $(HEADERS)
	$(CXX) -c $(CXXFLAGS) $(INC) $< -o $@
%.o: %.c $(HEADERS)
	$(CC) -c $(CFLAGS) $(INC) $< -o $@
%.o: %.cu $(HEADERS)
	$(NVCC) --device-c -c $(NVCCFLAGS) $(INC) $< -o $@

src/utils.o: src/utils.cu $(HEADERS)
	$(NVCC) --device-c -c $(NVCCFLAGS) $(INC) $< -o $@

default: all

# Build all, but run no tests. Note: CI currently uses this default...
all: libtest convtest

# testers for the lib (does not execute)
libtest: lib $(BINDIR)/conv_test 

# low-level (not-library) testers (does not execute)
convtest: $(BINDIR)/conv_test 
#	$(BINDIR)/interp_test

$(BINDIR)/%_32: test/%_32.o $(CURAFFTOBJS_32) $(CURAFFTOBJS)
	mkdir -p $(BINDIR)
	$(NVCC) -DSINGLE $^ $(NVCCFLAGS) $(NVCC_LIBS_PATH) $(LIBS) -o $@

$(BINDIR)/%: test/%.o $(CURAFFTOBJS_64) $(CURAFFTOBJS)
	mkdir -p $(BINDIR)
	$(NVCC) $^ $(NVCCFLAGS) $(NVCC_LIBS_PATH) $(LIBS) -o $@

# user-facing library...
lib: $(STATICLIB) $(DYNAMICLIB)
 # add $(CONTRIBOBJS) to static and dynamic later
$(STATICLIB): $(CURAFFTOBJS) $(CURAFFTOBJS_64) $(CURAFFTOBJS_32)
	mkdir -p lib-static
	ar rcs $(STATICLIB) $^
$(DYNAMICLIB): $(CURAFFTOBJS) $(CURAFFTOBJS_64) $(CURAFFTOBJS_32)
	mkdir -p lib
	$(NVCC) -shared $(NVCCFLAGS) $^ -o $(DYNAMICLIB) $(LIBS)


# --------------------------------------------- start of check tasks ---------
# Check targets: in contrast to the above, these tasks just execute things:
check:
	@echo "Building lib, all testers, and running all tests..."
	$(MAKE) checkconv


checkconv: libtest convtest
	@echo "Running conv/interp only tests..."
	@echo "conv 3D.............................................."
	bin/conv_test 0 1 1024 1024 1024*1024


# --------------------------------------------- end of check tasks ---------


# Cleanup and phony targets

clean:
	rm -f *.o
	rm -f test/*.o
	rm -f src/*.o
	rm -f src/FT/*.o
	rm -f contrib/*.o
	rm -rf $(BINDIR)
	rm -rf lib
	rm -rf lib-static

.PHONY: default all libtest convtest check checkconv
.PHONY: clean
