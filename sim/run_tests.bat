@echo off
echo ==========================================
echo  AGNI GPU - Running All Tests
echo ==========================================
echo.

set IVERILOG=iverilog.exe
set VVP=vvp.exe
set GPU_DIR=%~dp0..
set PASS=0
set FAIL=0

where /q %IVERILOG%
if %ERRORLEVEL% NEQ 0 (
    set IVERILOG=C:\iverilog\bin\iverilog.exe
    if not exist "%IVERILOG%" (
        echo [FAIL] iverilog not found. Install Icarus Verilog or add it to PATH.
        exit /b 1
    )
)

where /q %VVP%
if %ERRORLEVEL% NEQ 0 (
    set VVP=C:\iverilog\bin\vvp.exe
    if not exist "%VVP%" (
        echo [FAIL] vvp not found. Install Icarus Verilog runtime or add it to PATH.
        exit /b 1
    )
)

cd /d %GPU_DIR%

echo [1/3] Compiling minimal test...
"%IVERILOG%" -g2012 -o sim/test1.vvp tb/tb_minimal.v 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [FAIL] Minimal compile failed
    set /a FAIL+=1
    goto test2
)
echo [OK] Compiled. Running...
"%VVP%" sim/test1.vvp
if %ERRORLEVEL% NEQ 0 set /a FAIL+=1
set /a PASS+=1

:test2
echo.
echo [2/3] Compiling FIFO test...
"%IVERILOG%" -g2012 -o sim/test2.vvp rtl/common/fifo.sv tb/tb_fifo.sv 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [FAIL] FIFO compile failed
    set /a FAIL+=1
    goto test3
)
echo [OK] Compiled. Running...
"%VVP%" sim/test2.vvp
if %ERRORLEVEL% NEQ 0 set /a FAIL+=1
set /a PASS+=1

:test3
echo.
echo [3/3] Compiling INT32 ALU test...
"%IVERILOG%" -g2012 -I rtl/include -o sim/test3.vvp rtl/include/agni_pkg.sv rtl/compute/int32_alu.sv tb/tb_int32_alu.sv 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [FAIL] INT32 ALU compile failed
    set /a FAIL+=1
    goto done
)
echo [OK] Compiled. Running...
"%VVP%" sim/test3.vvp
if %ERRORLEVEL% NEQ 0 set /a FAIL+=1
set /a PASS+=1

:done
echo.
echo ==========================================
echo  Test Summary: PASS=%PASS% FAIL=%FAIL%
echo ==========================================
