#!/bin/bash

#export PATH=/compilerpath/:${PATH}

OBJDUMP=`which riscv32-unknown-elf-objdump`
OBJCOPY=`which riscv32-unknown-elf-objcopy`

COMPILER=`which riscv32-unknown-elf-gcc`
RANLIB=`which riscv32-unknown-elf-ranlib`

VSIM=`which vsim`

TARGET_C_FLAGS="-O3 -m32 -g"
#TARGET_C_FLAGS="-O2 -g -falign-functions=16  -funroll-all-loops"

# if you want to have compressed instructions, set this to 1
RVC=0

# if you are using zero-riscy, set this to 1
USE_ZERO_RISCY=1

# if you are using klessydra-t0-2th (The three pipeline version of klessydra t0), set this to 1
USE_KLESSYDRA_T0_2TH=0

# if you are using klessydra-t0-3th (The four pipeline version of klessydra t0), set this to 1
USE_KLESSYDRA_T0_3TH=0

# if you are using klessydra-t1-3th (The four pipeline version of klessydra t0), set this to 1
USE_KLESSYDRA_T1_3TH=0

# set this to 1 if you are using the Floating Point extensions for riscy only
RISCY_RV32F=0

# zeroriscy with the multiplier
ZERO_RV32M=0
# zeroriscy with only 16 registers
ZERO_RV32E=1

# riscy with PULPextensions, it is assumed you use the ETH GCC Compiler
GCC_MARCH="RV32I"
#compile arduino lib
ARDUINO_LIB=1

PULP_GIT_DIRECTORY=../../
SIM_DIRECTORY="$PULP_GIT_DIRECTORY/vsim"
#insert here your post-layout netlist if you are using IMPERIO
PL_NETLIST=""

cmake "$PULP_GIT_DIRECTORY"/sw/ \
    -DPULP_MODELSIM_DIRECTORY="$SIM_DIRECTORY" \
    -DCMAKE_C_COMPILER="$COMPILER" \
    -DVSIM="$VSIM" \
    -DRVC="$RVC" \
    -DRISCY_RV32F="$RISCY_RV32F" \
    -DUSE_KLESSYDRA_T0_2TH="$USE_KLESSYDRA_T0_2TH" \
    -DUSE_KLESSYDRA_T0_3TH="$USE_KLESSYDRA_T0_3TH" \
    -DUSE_KLESSYDRA_T1_3TH="$USE_KLESSYDRA_T1_3TH" \
    -DUSE_ZERO_RISCY="$USE_ZERO_RISCY" \
    -DZERO_RV32M="$ZERO_RV32M" \
    -DZERO_RV32E="$ZERO_RV32E" \
    -DGCC_MARCH="$GCC_MARCH" \
    -DARDUINO_LIB="$ARDUINO_LIB" \
    -DPL_NETLIST="$PL_NETLIST" \
    -DCMAKE_C_FLAGS="$TARGET_C_FLAGS" \
    -DCMAKE_OBJCOPY="$OBJCOPY" \
    -DCMAKE_OBJDUMP="$OBJDUMP"

# Add -G "Ninja" to the cmake call above to use ninja instead of make
