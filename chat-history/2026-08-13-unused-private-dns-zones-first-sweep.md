# 2026-08-13 — Unused private DNS zones, first sweep review

- **Workspace:** `e:\Repos\Azure`
- **Date:** 2026-08-13
- **Tenant:** Mercyhealth `7d689bf5-26f6-44a2-b080-61689eff65a6`

## User request

Study `Output/2026-08-13-095458-unused-private-dns-zones.json` against `docs/change-plans/2026-08-11-private-dns-zone-cleanup-plan.md`.

## Outcome

First discovery run completed Phases A–C of the plan. **EligibleForDeletion = 0.** No Azure resources were changed.

### Confirmed from the JSON (2026-08-13 04:24:58 UTC)

- Tenant matches the plan.
- 22 subscriptions swept; Stage 2 was performed; 54 ARG candidates; 0 eligible.
- All 54 rows failed Stage 2 (control-plane verification failed or access denied) and Stage 3 (creation time unavailable).
- 53 zones in subscription `818a8b62-…` / `rg-dns-v3nysoeym4kga`, ARG 0 links and 1 record set.
- 1 zone `privatelink.postgres.database.azure.com` in subscription `a0852105-…` / `vitea-mercyhealth-prod-ncus-data-rg`, ARG 0 links and 2 record sets.

### Confirmed from Azure MCP `subscription_list` (same session)

- This identity sees 22 Enabled subscriptions — same count as `SubscriptionsSwept`.
- `818a8b62-…` = `dt-prd-connectivity-oeqrq2jxadm36`
- `a0852105-…` = `dt-prd-vitea-oeqrq2jxadm36`
- Plan’s older connectivity hub id `d93fefb0-…` is not in the current Enabled list.

### Inferences

- Connectivity RG `rg-dns-v3nysoeym4kga` looks like an ALZ/policy private DNS pack. §11 DINE residual risk applies even if a later run marks those zones eligible.
- Vitea postgres zone looks like a spoke duplicate or disconnected PE zone; treat as production.
- ARG `recordSets = 1` on 53 zones supports an SOA-only baseline, but §6a still needs a control-plane calibration.

### Not done

- Plan §6a baseline still blank.
- Phase D soak, Phase E backup, Phase F deletion — not started and not authorized.
- External systems unchanged.

## Artifacts

- Report: `Output/2026-08-13-095458-unused-private-dns-zones.json` (and `.csv`)
- Canvas: `unused-private-dns-zones-review.canvas.tsx`
