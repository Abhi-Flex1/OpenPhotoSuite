# Taste

## Workflow
- Requires full end-to-end testing/verification before any commit or push — the work is only "done" once the whole thing has been run successfully. Confidence: 0.75
- Wants proof of working results committed alongside the code (e.g. screenshots of the running app), not just a passing build. Confidence: 0.65
- Looks for setup/environment instructions already recorded in the repo's own history (earlier commits' READMEs) before writing new ones. Confidence: 0.5

## Approach to ports / ports to new platforms
- Prefers porting by forking the upstream project and adding the new platform target, rather than reimplementing from scratch. Confidence: 0.7
- Expects 1:1 fidelity in ports: UI, features, and behavior should match the original exactly unless told otherwise. Confidence: 0.7
