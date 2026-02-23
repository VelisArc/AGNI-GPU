#!/bin/bash
# ============================================================================
# Project AGNI — Lint Automation Script
# File: lint/lint_run.sh
# Description: Runs Verilator lint with waiver file and generates report.
# Usage: cd GPU && bash lint/lint_run.sh
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LINT_CONFIG="${SCRIPT_DIR}/lint_config.vlt"
FILELIST="${PROJECT_DIR}/sim/filelist.f"
REPORT_DIR="${SCRIPT_DIR}/reports"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo " Project AGNI — Lint Check"
echo "=========================================="
echo " Project:  ${PROJECT_DIR}"
echo " Config:   ${LINT_CONFIG}"
echo " Filelist: ${FILELIST}"
echo ""

# Create report directory
mkdir -p "${REPORT_DIR}"

# Timestamp
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
REPORT_FILE="${REPORT_DIR}/lint_report_${TIMESTAMP}.log"

echo "Running Verilator lint..."
echo ""

cd "${PROJECT_DIR}"

# Run lint
if verilator --lint-only \
    -Wall \
    --timing \
    -f sim/filelist.f \
    "${LINT_CONFIG}" \
    2>&1 | tee "${REPORT_FILE}"; then
    echo ""
    echo -e "${GREEN}✅ LINT PASSED — No errors${NC}"
    echo "Report: ${REPORT_FILE}"
    EXIT_CODE=0
else
    echo ""
    echo -e "${RED}❌ LINT FAILED — See report above${NC}"
    echo "Report: ${REPORT_FILE}"
    EXIT_CODE=1
fi

# Count warnings/errors in report
WARNINGS=$(grep -c "Warning" "${REPORT_FILE}" 2>/dev/null || true)
ERRORS=$(grep -c "Error" "${REPORT_FILE}" 2>/dev/null || true)

echo ""
echo "=========================================="
echo " Summary"
echo "=========================================="
echo " Errors:   ${ERRORS}"
echo " Warnings: ${WARNINGS}"
echo " Report:   ${REPORT_FILE}"
echo "=========================================="

exit ${EXIT_CODE}
