# 2026-09-15 — AppDev Node 22 to 24 upgrade check

- Date: 2026-09-15
- Workspace: `C:\Users\hardikdesai\codes\Azure`
- Class: 0 read-only. No Azure, ADO, or Git mutation.

## Request

Check what backend code and Azure DevOps pipelines need to change if App Service stack is moved from Node 22 to Node 24 in subscription `dt-prd-app-oeqrq2jxadm36`. Code lives in AppDev. Apps use Deno as the JavaScript/TypeScript runtime.

## Outcome

Changing the App Service stack is a **host-image** change, not the application runtime. All ten Linux apps in `rg-spoke-appdev-prd-4fhxtyumb5wlq` are `NODE|22-lts` with startup `bash /home/site/wwwroot/setup.sh`, which installs Deno from Key Vault `DENO_VERSION` and runs `bundle.js`. Node 24 LTS is available (`NODE|24-lts`, Active, EOL 2028-04-30). Node 24 images are Ubuntu; Node 22 remains Debian.

AppDev repo is `dts-apps` in org `mercyhealthcare`, project `AppDev`. Production deploys via pipeline `dts-apps (42)` / `azure-pipelines-prod-manual.yml` from feature/prod branches onto VMSS agents. `NODE_VERSION=22.x` is set in pipeline variables and in variable groups `Azure Deployment Configuration Prod Environment` and `Azure Deployment Configuration Test Environment`. Prod/test YAML does not run `NodeTool@0`; agents use the preinstalled Node (image template `BuildAgent_Template_20250710` installs NodeSource `setup_23.x`). `package.json` engines is `node: ">=22"`, which already allows 24. Deno app code does not need a Node 24 rewrite. Main-branch `setup.sh` still hardcodes Debian `bookworm-pgdg`; prod-deploy `setup.sh` does not.

No external system was changed.
