@echo off
setlocal enabledelayedexpansion
echo =====================================================
echo  AGNI GPU - Industry-Standard RTL Lint (Syntax Check)
echo  Tool: IcarusVerilog v12 (-g2012)
echo  Date: %date% %time%
echo =====================================================
echo.

set IVERILOG=iverilog.exe
set GPU_DIR=%~dp0..
set PASS=0
set FAIL=0
set TOTAL=0
set INCDIR=-I%GPU_DIR%/rtl/include
set YDIRS=-y%GPU_DIR%/rtl/common -y%GPU_DIR%/rtl/compute -y%GPU_DIR%/rtl/sm -y%GPU_DIR%/rtl/memory -y%GPU_DIR%/rtl/noc -y%GPU_DIR%/rtl/power -y%GPU_DIR%/rtl/dft -y%GPU_DIR%/rtl/io -y%GPU_DIR%/rtl/gpc

where /q %IVERILOG%
if !ERRORLEVEL! NEQ 0 (
    set IVERILOG=C:\iverilog\bin\iverilog.exe
    if not exist "!IVERILOG!" (
        echo [FAIL] iverilog not found. Install Icarus Verilog or add it to PATH.
        exit /b 1
    )
)

cd /d %GPU_DIR%

echo [Phase 1] Common Primitives + Package
echo -----------------------------------------------

set /a TOTAL+=1
%IVERILOG% -g2012 -E %INCDIR% rtl/include/agni_pkg.sv >nul 2>nul
if !ERRORLEVEL! EQU 0 (
    echo   [PASS] rtl/include/agni_pkg.sv
    set /a PASS+=1
) else (
    echo   [FAIL] rtl/include/agni_pkg.sv
    %IVERILOG% -g2012 -E %INCDIR% rtl/include/agni_pkg.sv
    set /a FAIL+=1
)

for %%f in (
    rtl/common/fifo.sv
    rtl/common/async_fifo.sv
    rtl/common/ram_sp.sv
    rtl/common/ram_dp.sv
    rtl/common/arbiter_rr.sv
    rtl/common/cdc_sync.sv
    rtl/common/reset_sync.sv
    rtl/common/encoder_onehot.sv
    rtl/common/decoder_onehot.sv
) do (
    set /a TOTAL+=1
    %IVERILOG% -g2012 -t null %INCDIR% %YDIRS% rtl/include/agni_pkg.sv %%f 2>nul
    if !ERRORLEVEL! EQU 0 (
        echo   [PASS] %%f
        set /a PASS+=1
    ) else (
        echo   [FAIL] %%f
        %IVERILOG% -g2012 -t null %INCDIR% %YDIRS% rtl/include/agni_pkg.sv %%f
        set /a FAIL+=1
    )
)

echo.
echo [Phase 2] Compute Units
echo -----------------------------------------------

for %%f in (
    rtl/compute/fma_unit.sv
    rtl/compute/int32_alu.sv
    rtl/compute/sfu.sv
    rtl/compute/tensor_core.sv
) do (
    set /a TOTAL+=1
    %IVERILOG% -g2012 -t null %INCDIR% %YDIRS% rtl/include/agni_pkg.sv %%f 2>nul
    if !ERRORLEVEL! EQU 0 (
        echo   [PASS] %%f
        set /a PASS+=1
    ) else (
        echo   [FAIL] %%f
        %IVERILOG% -g2012 -t null %INCDIR% %YDIRS% rtl/include/agni_pkg.sv %%f
        set /a FAIL+=1
    )
)
set /a TOTAL+=1
%IVERILOG% -g2012 -t null %INCDIR% rtl/include/agni_pkg.sv rtl/compute/fma_unit.sv rtl/compute/fp32_alu.sv 2>nul
if !ERRORLEVEL! EQU 0 (
    echo   [PASS] rtl/compute/fp32_alu.sv
    set /a PASS+=1
) else (
    echo   [FAIL] rtl/compute/fp32_alu.sv
    %IVERILOG% -g2012 -t null %INCDIR% rtl/include/agni_pkg.sv rtl/compute/fma_unit.sv rtl/compute/fp32_alu.sv
    set /a FAIL+=1
)

echo.
echo [Phase 3] SM Core
echo -----------------------------------------------

for %%f in (
    rtl/sm/warp_scheduler.sv
    rtl/sm/dispatch_unit.sv
    rtl/sm/operand_collector.sv
    rtl/sm/simt_stack.sv
    rtl/sm/icache.sv
    rtl/sm/fetch_unit.sv
    rtl/sm/mem_coalescer.sv
    rtl/sm/atomic_unit.sv
    rtl/sm/register_mapper.sv
    rtl/sm/lsu.sv
) do (
    set /a TOTAL+=1
    %IVERILOG% -g2012 -t null %INCDIR% %YDIRS% rtl/include/agni_pkg.sv %%f 2>nul
    if !ERRORLEVEL! EQU 0 (
        echo   [PASS] %%f
        set /a PASS+=1
    ) else (
        echo   [FAIL] %%f
        %IVERILOG% -g2012 -t null %INCDIR% %YDIRS% rtl/include/agni_pkg.sv %%f
        set /a FAIL+=1
    )
)
set /a TOTAL+=1
%IVERILOG% -g2012 -t null %INCDIR% rtl/include/agni_pkg.sv rtl/common/ram_sp.sv rtl/sm/register_file.sv 2>nul
if !ERRORLEVEL! EQU 0 (
    echo   [PASS] rtl/sm/register_file.sv
    set /a PASS+=1
) else (
    echo   [FAIL] rtl/sm/register_file.sv
    %IVERILOG% -g2012 -t null %INCDIR% rtl/include/agni_pkg.sv rtl/common/ram_sp.sv rtl/sm/register_file.sv
    set /a FAIL+=1
)

echo.
echo [Phase 4] Memory Subsystem
echo -----------------------------------------------

for %%f in (
    rtl/memory/ecc_encoder.sv
    rtl/memory/ecc_decoder.sv
    rtl/memory/chipkill_ecc.sv
    rtl/memory/tag_array.sv
    rtl/memory/tlb.sv
    rtl/memory/page_table_walker.sv
    rtl/memory/coherence_controller.sv
    rtl/memory/coherence_directory.sv
) do (
    set /a TOTAL+=1
    %IVERILOG% -g2012 -t null %INCDIR% %YDIRS% rtl/include/agni_pkg.sv %%f 2>nul
    if !ERRORLEVEL! EQU 0 (
        echo   [PASS] %%f
        set /a PASS+=1
    ) else (
        echo   [FAIL] %%f
        %IVERILOG% -g2012 -t null %INCDIR% %YDIRS% rtl/include/agni_pkg.sv %%f
        set /a FAIL+=1
    )
)
set /a TOTAL+=1
%IVERILOG% -g2012 -t null %INCDIR% rtl/include/agni_pkg.sv rtl/memory/ecc_encoder.sv rtl/memory/ecc_decoder.sv rtl/memory/tag_array.sv rtl/memory/l1_cache.sv 2>nul
if !ERRORLEVEL! EQU 0 (
    echo   [PASS] rtl/memory/l1_cache.sv
    set /a PASS+=1
) else (
    echo   [FAIL] rtl/memory/l1_cache.sv
    %IVERILOG% -g2012 -t null %INCDIR% rtl/include/agni_pkg.sv rtl/memory/ecc_encoder.sv rtl/memory/ecc_decoder.sv rtl/memory/tag_array.sv rtl/memory/l1_cache.sv
    set /a FAIL+=1
)
set /a TOTAL+=1
%IVERILOG% -g2012 -t null %INCDIR% rtl/include/agni_pkg.sv rtl/memory/tag_array.sv rtl/memory/l2_cache_slice.sv 2>nul
if !ERRORLEVEL! EQU 0 (
    echo   [PASS] rtl/memory/l2_cache_slice.sv
    set /a PASS+=1
) else (
    echo   [FAIL] rtl/memory/l2_cache_slice.sv
    %IVERILOG% -g2012 -t null %INCDIR% rtl/include/agni_pkg.sv rtl/memory/tag_array.sv rtl/memory/l2_cache_slice.sv
    set /a FAIL+=1
)
set /a TOTAL+=1
%IVERILOG% -g2012 -t null %INCDIR% rtl/include/agni_pkg.sv rtl/memory/ecc_encoder.sv rtl/memory/ecc_decoder.sv rtl/memory/chipkill_ecc.sv rtl/memory/hbm4_controller.sv 2>nul
if !ERRORLEVEL! EQU 0 (
    echo   [PASS] rtl/memory/hbm4_controller.sv
    set /a PASS+=1
) else (
    echo   [FAIL] rtl/memory/hbm4_controller.sv
    %IVERILOG% -g2012 -t null %INCDIR% rtl/include/agni_pkg.sv rtl/memory/ecc_encoder.sv rtl/memory/ecc_decoder.sv rtl/memory/chipkill_ecc.sv rtl/memory/hbm4_controller.sv
    set /a FAIL+=1
)

echo.
echo [Phase 5] NoC
echo -----------------------------------------------

for %%f in (
    rtl/noc/noc_router.sv
) do (
    set /a TOTAL+=1
    %IVERILOG% -g2012 -t null %INCDIR% %YDIRS% rtl/include/agni_pkg.sv %%f 2>nul
    if !ERRORLEVEL! EQU 0 (
        echo   [PASS] %%f
        set /a PASS+=1
    ) else (
        echo   [FAIL] %%f
        %IVERILOG% -g2012 -t null %INCDIR% %YDIRS% rtl/include/agni_pkg.sv %%f
        set /a FAIL+=1
    )
)
set /a TOTAL+=1
%IVERILOG% -g2012 -t null %INCDIR% rtl/include/agni_pkg.sv rtl/noc/noc_router.sv rtl/noc/noc_mesh.sv 2>nul
if !ERRORLEVEL! EQU 0 (
    echo   [PASS] rtl/noc/noc_mesh.sv
    set /a PASS+=1
) else (
    echo   [FAIL] rtl/noc/noc_mesh.sv
    %IVERILOG% -g2012 -t null %INCDIR% rtl/include/agni_pkg.sv rtl/noc/noc_router.sv rtl/noc/noc_mesh.sv
    set /a FAIL+=1
)

echo.
echo [Phase 6] Power + Clock
echo -----------------------------------------------

for %%f in (
    rtl/power/clock_gate.sv
    rtl/power/dvfs_controller.sv
    rtl/power/thermal_monitor.sv
    rtl/power/pll_model.sv
    rtl/power/clock_divider.sv
) do (
    set /a TOTAL+=1
    %IVERILOG% -g2012 -t null %INCDIR% %YDIRS% rtl/include/agni_pkg.sv %%f 2>nul
    if !ERRORLEVEL! EQU 0 (
        echo   [PASS] %%f
        set /a PASS+=1
    ) else (
        echo   [FAIL] %%f
        %IVERILOG% -g2012 -t null %INCDIR% %YDIRS% rtl/include/agni_pkg.sv %%f
        set /a FAIL+=1
    )
)

echo.
echo [Phase 7] DFT + I/O PHY
echo -----------------------------------------------

for %%f in (
    rtl/dft/scan_wrapper.sv
    rtl/io/pcie_gen6_phy.sv
    rtl/io/nvlink_phy.sv
    rtl/io/hbm_phy.sv
) do (
    set /a TOTAL+=1
    %IVERILOG% -g2012 -t null %INCDIR% %YDIRS% rtl/include/agni_pkg.sv %%f 2>nul
    if !ERRORLEVEL! EQU 0 (
        echo   [PASS] %%f
        set /a PASS+=1
    ) else (
        echo   [FAIL] %%f
        %IVERILOG% -g2012 -t null %INCDIR% %YDIRS% rtl/include/agni_pkg.sv %%f
        set /a FAIL+=1
    )
)

echo.
echo [Phase 8] Top-Level Integration
echo -----------------------------------------------

set /a TOTAL+=1
%IVERILOG% -g2012 -t null %INCDIR% rtl/include/agni_pkg.sv rtl/common/fifo.sv rtl/common/arbiter_rr.sv rtl/common/ram_sp.sv rtl/common/ram_dp.sv rtl/common/encoder_onehot.sv rtl/common/decoder_onehot.sv rtl/memory/ecc_encoder.sv rtl/memory/ecc_decoder.sv rtl/memory/tag_array.sv rtl/compute/fma_unit.sv rtl/compute/fp32_alu.sv rtl/compute/int32_alu.sv rtl/compute/sfu.sv rtl/compute/tensor_core.sv rtl/sm/warp_scheduler.sv rtl/sm/register_file.sv rtl/sm/dispatch_unit.sv rtl/sm/operand_collector.sv rtl/memory/l1_cache.sv rtl/sm/streaming_multiprocessor.sv rtl/gpc/gpc.sv 2>nul
if !ERRORLEVEL! EQU 0 (
    echo   [PASS] gpc.sv (with dependencies^)
    set /a PASS+=1
) else (
    echo   [FAIL] gpc.sv (with dependencies^)
    %IVERILOG% -g2012 -t null %INCDIR% rtl/include/agni_pkg.sv rtl/common/fifo.sv rtl/common/arbiter_rr.sv rtl/common/ram_sp.sv rtl/common/ram_dp.sv rtl/common/encoder_onehot.sv rtl/common/decoder_onehot.sv rtl/memory/ecc_encoder.sv rtl/memory/ecc_decoder.sv rtl/memory/tag_array.sv rtl/compute/fma_unit.sv rtl/compute/fp32_alu.sv rtl/compute/int32_alu.sv rtl/compute/sfu.sv rtl/compute/tensor_core.sv rtl/sm/warp_scheduler.sv rtl/sm/register_file.sv rtl/sm/dispatch_unit.sv rtl/sm/operand_collector.sv rtl/memory/l1_cache.sv rtl/sm/streaming_multiprocessor.sv rtl/gpc/gpc.sv
    set /a FAIL+=1
)

echo.
echo =====================================================
echo  LINT RESULTS: %PASS% PASS / %FAIL% FAIL / %TOTAL% TOTAL
echo =====================================================
if %FAIL% EQU 0 (
    echo  ALL MODULES PASSED LINT
) else (
    echo  %FAIL% MODULES NEED FIXING
)
echo.
