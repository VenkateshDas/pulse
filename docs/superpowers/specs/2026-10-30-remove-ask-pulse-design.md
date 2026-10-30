# AI-free Pulse

Approved scope: remove Ask Pulse completely from the application, including navigation, chat, provider/model/API-key settings, client, daemon, Python runtime and packaging. Update public feature claims. Keep native monitoring, diagnostics, cleanup and CLI functionality. Preserve AI development on feat/home-ask-pulse. Existing user credentials and conversation data are not deleted.

Validation: make build, make test, make cli-smoke and make bundle, with an artifact inspection confirming no AI runtime or skill is bundled. Navigation regression rejects the removed Agent route. Submit a PR and require green CI plus explicit user visual/functional approval before merge.
