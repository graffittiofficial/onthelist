# Copilot instructions for onthelist

## Repository status

This repository is currently a minimal placeholder: the root contains only a README and Git metadata. There is no application source, framework, test suite, or lint/build configuration present yet.

Treat this as a small, early-stage project until additional code or tooling is added. Prefer minimal, straightforward changes that fit the repository's current size and avoid assuming a larger architecture that is not yet in place.

## Build, test, and lint commands

No build, test, or lint commands are currently defined in this repository.

Before adding or running project tooling, check whether the repository has a package manager or app scaffold; if none exists, do not invent project-specific commands. Keep any new scripts aligned with the minimal state of the repo and document them in the relevant project files.

When the repo grows, prefer the smallest command that checks the changed behavior, for example:

- single test file or test name when a test runner exists
- a focused build step for the changed package or service
- a narrow lint/format command scoped to the touched files

## High-level architecture

At present, there is no established application architecture to navigate. The project is not yet organized into services, packages, or app modules. Future work should preserve a simple structure and avoid introducing unnecessary abstraction before the domain is defined.

When adding code, keep the organization explicit and lightweight:

- prefer the simplest layout that matches the feature being added
- avoid creating a multi-layer architecture before there is enough code to justify it
- keep configuration and app entry points obvious and close to the implementation they serve

## Key conventions

- Keep changes small and easy to follow.
- Do not assume frameworks, libraries, or deployment patterns that are not already present.
- Preserve the repo's minimal state unless a task clearly requires adding structure.
- If a feature or tooling needs to be introduced, document the relevant commands and conventions in the project files that are already present.
- Favor direct, readable implementations over over-engineering or scaffolding that is not required by the task.

## Working style for future sessions

- Prefer surgical edits over wide refactors.
- If the repository is still empty, do not create elaborate project structure without explicit guidance.
- When adding new files, keep names descriptive and consistent with the rest of the repository.
- If a task introduces a new toolchain, add only the minimal config needed to support the intended workflow.
