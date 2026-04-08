#!/bin/bash
echo "=========================================="
echo " AGNI GPU - Running All Tests"
echo "=========================================="
echo ""

IVERILOG="iverilog"
VVP="vvp"
PASS=0
FAIL=0

cd $(dirname $0)/..

echo "[1/3] Compiling minimal test..."
$IVERILOG -g2012 -o sim/test1.vvp tb/tb_minimal.v 2>&1
if [ $? -ne 0 ]; then
    echo "[FAIL] Minimal compile failed"
    FAIL=$((FAIL+1))
else
    echo "[OK] Compiled. Running..."
    $VVP sim/test1.vvp
    if [ $? -ne 0 ]; then FAIL=$((FAIL+1)); else PASS=$((PASS+1)); fi
fi

echo ""
echo "[2/3] Compiling FIFO test..."
$IVERILOG -g2012 -o sim/test2.vvp rtl/common/fifo.sv tb/tb_fifo.sv 2>&1
if [ $? -ne 0 ]; then
    echo "[FAIL] FIFO compile failed"
    FAIL=$((FAIL+1))
else
    echo "[OK] Compiled. Running..."
    $VVP sim/test2.vvp
    if [ $? -ne 0 ]; then FAIL=$((FAIL+1)); else PASS=$((PASS+1)); fi
fi

echo ""
echo "[3/3] Compiling INT32 ALU test..."
$IVERILOG -g2012 -I rtl/include -o sim/test3.vvp rtl/include/agni_pkg.sv rtl/compute/int32_alu.sv tb/tb_int32_alu.sv 2>&1
if [ $? -ne 0 ]; then
    echo "[FAIL] INT32 ALU compile failed"
    FAIL=$((FAIL+1))
else
    echo "[OK] Compiled. Running..."
    $VVP sim/test3.vvp
    if [ $? -ne 0 ]; then FAIL=$((FAIL+1)); else PASS=$((PASS+1)); fi
fi

echo ""
echo "=========================================="
echo " Test Summary: PASS=$PASS FAIL=$FAIL"
echo "=========================================="

if [ $FAIL -gt 0 ]; then exit 1; else exit 0; fi
