# Decisions

- 2026-09-05: Scope application reporting to discovered web apps, function apps and static web apps in the explicitly requested subscription. Include hosting-plan utilization separately from application resource consumption.
- Use a fixed UTC 24-hour window and Azure-provided daily averages. Label peaks as highest five-minute averages; retain empty telemetry as missing rather than zero.
- Use existing Azure CLI authentication. Do not install the missing log-query extension or change Conditional Access. Record the blocked documented Logs Query API attempt as a coverage limitation.
- Preserve sanitized output locally without committing, pushing or changing Azure resources. **Superseded 2026-09-06.**
- 2026-09-06: Commit the sanitized reports, summaries, handoff files and reusable query to `main`. Exclude the two bulk raw Azure Monitor metric exports (`Output/2026-09-05-111000-dt-prd-app-performance-24h-data.json`, 8.1 MB; `Output/2026-09-05-app-service-memory-sizing-7d.json`, 2.6 MB) via `.gitignore`; their `*-summary.json` companions carry the analyzable content and stay tracked. The raw files remain on disk locally. Not pushed. No Azure resource was changed.
