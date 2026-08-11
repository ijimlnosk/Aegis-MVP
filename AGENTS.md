# AGENTS.md

## Project Overview

- This project is a personal AI assistant for voice interaction and safe local automation.
- Build the smallest working flow first: user request, tool selection, approval, execution, and result.
- Keep AI reasoning, tool execution, memory, and UI clearly separated.

## Architecture

- Follow Feature-Sliced Design for application UI.
- Put feature-specific code in `features`.
- Put reusable UI components in `shared/ui`.
- Put domain models and business entities in `entities`.
- Put page-level composition in `app`, `pages`, or `views` according to the framework.
- Put API clients, utilities, configuration, and shared types in `shared`.
- Keep agent logic, tools, memory, and contracts in separate modules or packages.
- Keep server-only secrets and system operations out of client code.

## Code Rules

- Use TypeScript with strict type checking.
- Keep files under 100 lines when practical.
- Split files by responsibility when they grow beyond 100 lines.
- Keep functions small and focused on one task.
- Prefer explicit types and clear names over clever abstractions.
- Avoid duplicate logic and unnecessary dependencies.
- Add comments only when the reason is not obvious from the code.

## Safety Rules

- Read-only tools may run automatically.
- File changes, commands, and other mutations require user approval.
- Deletion, payments, messages, and external publishing always require explicit approval.
- Never allow the model to execute arbitrary shell commands.
- Validate tool inputs and restrict file access to registered project roots.
- Never expose API keys, tokens, environment variables, or private data to the client.

## Development Workflow

- Inspect the existing structure before changing code.
- Preserve existing behavior unless the task explicitly changes it.
- Make the smallest complete change that solves the request.
- Run type checking, linting, tests, and a production build when relevant.
- Do not hide failures; report the cause and any unverified behavior clearly.

## UI Rules

- Keep the interface simple, responsive, and accessible.
- Show clear states for listening, thinking, waiting for approval, working, success, and failure.
- Require a visible confirmation before any approved action runs.
- Keep mobile and desktop behavior consistent while adapting layout to each screen size.
