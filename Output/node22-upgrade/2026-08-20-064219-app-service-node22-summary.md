# App Service Node.js 22 inventory

- Observed at (UTC): 2026-08-20T01:07:31.4395574Z
- Tenant: 7d689bf5-26f6-44a2-b080-61689eff65a6
- Signed in as: hdesai@mhemail.org
- Subscriptions swept: 22
- Advisory tracking id: 9Z2G-WGG
- Stage 2 CLI verification: True
- ARG Node 22 candidates: 26
- ARG all sites/slots: 33
- Confirmed or classified Node major 22: 26

This inventory reports **configured** runtime (linuxFxVersion / WEBSITE_NODE_DEFAULT_VERSION), not live `node -v`.

## Node 22 by subscription

| Subscription | Node 22 rows |
|---|---|
| dt-dev-app-oeqrq2jxadm36 | 10 |
| dt-prd-app-oeqrq2jxadm36 | 7 |
| dt-tst-app-oeqrq2jxadm36 | 9 |

## Microsoft notice seed list

| App name | Found | Node major | Notes |
|---|---|---|---|
| app-hand-hygiene-dev-ncus | Yes | 22 |  |
| app-notification-service-dev-ncus | Yes | 22 |  |
| app-audit-log-dev-ncus | Yes | 22 |  |
| app-ora-dev-ncus | Yes | 22 |  |
| app-portal-dev-ncus | Yes | 22 |  |
| app-pmm-dev-ncus | Yes | 22 |  |
| app-hhs-dev-ncus | Yes | 22 |  |
| app-labor-pool-dev-ncus | Yes | 22 |  |

## Notice mismatches (in email, not Node 22 after verification)

_None._

## Windows apps with unverified Node runtime (manual review)

- `app-tpa-dev-backend-ncus` (dt-dev-tpa-oeqrq2jxadm36) — Windows app has no WEBSITE_NODE_DEFAULT_VERSION / nodeVersion; inherited platform default is unverified
- `app-tpa-dev-frontend-ncus` (dt-dev-tpa-oeqrq2jxadm36) — Windows app has no WEBSITE_NODE_DEFAULT_VERSION / nodeVersion; inherited platform default is unverified
- `app-tpa-prod-backend-ncus` (dt-prd-tpa-oeqrq2jxadm36) — Windows app has no WEBSITE_NODE_DEFAULT_VERSION / nodeVersion; inherited platform default is unverified
- `app-tpa-prod-frontend-ncus` (dt-prd-tpa-oeqrq2jxadm36) — Windows app has no WEBSITE_NODE_DEFAULT_VERSION / nodeVersion; inherited platform default is unverified
- `app-tpa-test-backend-ncus` (dt-tst-tpa-oeqrq2jxadm36) — Windows app has no WEBSITE_NODE_DEFAULT_VERSION / nodeVersion; inherited platform default is unverified
- `app-tpa-test-frontend-ncus` (dt-tst-tpa-oeqrq2jxadm36) — Windows app has no WEBSITE_NODE_DEFAULT_VERSION / nodeVersion; inherited platform default is unverified

## Node 22 apps not named in the Microsoft email

- `app-legacy-docs-dev-ncus` (dt-dev-app-oeqrq2jxadm36 / rg-spoke-appdev-dev-g3kmeu7yyl24w) runtime=`NODE|22-lts`
- `app-medicaid-dev-ncus` (dt-dev-app-oeqrq2jxadm36 / rg-spoke-appdev-dev-g3kmeu7yyl24w) runtime=`NODE|22-lts`
- `app-audit-log-prod-ncus` (dt-prd-app-oeqrq2jxadm36 / rg-spoke-appdev-prd-4fhxtyumb5wlq) runtime=`NODE|22-lts`
- `app-hand-hygiene-prod-ncus` (dt-prd-app-oeqrq2jxadm36 / rg-spoke-appdev-prd-4fhxtyumb5wlq) runtime=`NODE|22-lts`
- `app-HHS-prod-ncus` (dt-prd-app-oeqrq2jxadm36 / rg-spoke-appdev-prd-4fhxtyumb5wlq) runtime=`NODE|22-lts`
- `app-labor-pool-prod-ncus` (dt-prd-app-oeqrq2jxadm36 / rg-spoke-appdev-prd-4fhxtyumb5wlq) runtime=`NODE|22-lts`
- `app-notification-service-prod-ncus` (dt-prd-app-oeqrq2jxadm36 / rg-spoke-appdev-prd-4fhxtyumb5wlq) runtime=`NODE|22-lts`
- `app-PMM-prod-ncus` (dt-prd-app-oeqrq2jxadm36 / rg-spoke-appdev-prd-4fhxtyumb5wlq) runtime=`NODE|22-lts`
- `app-portal-prod-ncus` (dt-prd-app-oeqrq2jxadm36 / rg-spoke-appdev-prd-4fhxtyumb5wlq) runtime=`NODE|22-lts`
- `app-audit-log-test-ncus` (dt-tst-app-oeqrq2jxadm36 / rg-spoke-appdev-tst-wuy2zthjccmbo) runtime=`NODE|22-lts`
- `app-hand-hygiene-test-ncus` (dt-tst-app-oeqrq2jxadm36 / rg-spoke-appdev-tst-wuy2zthjccmbo) runtime=`NODE|22-lts`
- `app-HHS-test-ncus` (dt-tst-app-oeqrq2jxadm36 / rg-spoke-appdev-tst-wuy2zthjccmbo) runtime=`NODE|22-lts`
- `app-labor-pool-test-ncus` (dt-tst-app-oeqrq2jxadm36 / rg-spoke-appdev-tst-wuy2zthjccmbo) runtime=`NODE|22-lts`
- `app-legacy-docs-test-ncus` (dt-tst-app-oeqrq2jxadm36 / rg-spoke-appdev-tst-wuy2zthjccmbo) runtime=`NODE|22-lts`
- `app-notification-service-test-ncus` (dt-tst-app-oeqrq2jxadm36 / rg-spoke-appdev-tst-wuy2zthjccmbo) runtime=`NODE|22-lts`
- `app-ORA-test-ncus` (dt-tst-app-oeqrq2jxadm36 / rg-spoke-appdev-tst-wuy2zthjccmbo) runtime=`NODE|22-lts`
- `app-PMM-test-ncus` (dt-tst-app-oeqrq2jxadm36 / rg-spoke-appdev-tst-wuy2zthjccmbo) runtime=`NODE|22-lts`
- `app-portal-test-ncus` (dt-tst-app-oeqrq2jxadm36 / rg-spoke-appdev-tst-wuy2zthjccmbo) runtime=`NODE|22-lts`

## Coverage warnings

- Tenant sweep covers only subscriptions this identity can read (22 found). An empty result does not prove no Node 22 app exists elsewhere.

## Files

- CSV (Node 22 only): C:\codes\azure-architect-workspace\output\2026-08-20-064219-app-service-node22-inventory.csv
- CSV (full review set): C:\codes\azure-architect-workspace\output\2026-08-20-064219-app-service-node22-review-set.csv
- JSON: C:\codes\azure-architect-workspace\output\2026-08-20-064219-app-service-node22-inventory.json
