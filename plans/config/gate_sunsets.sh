#!/usr/bin/env bash
# Gate sunset dates (YYYY-MM-DD format)
# When current date > sunset date, WARN-only gates promote to blocking

ADVERSARIAL_SUNSET_DATE="2026-04-15"  # ~8 weeks grace period for coverage ramp-up
# Future gates add their sunset dates here
