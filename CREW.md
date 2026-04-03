# Ikeru Agent Crew Configuration

## Overview

Agent team for systematic development following BMAD methodology.
All agents MUST use BMAD commands — no ad-hoc implementation.

## Crew Composition

### Lead Orchestrator (1)
- **Role**: Manages epic/story pipeline, creates story files, dispatches work
- **Command**: `/bmad-create-story` to generate story specs
- **Responsibilities**:
  - Create story files in order (epic by epic, story by story)
  - Dispatch dev agents with full context
  - Track progress across all epics/stories
  - Handle dependencies between stories
  - Ping user only when blocked or needing decisions

### Dev Agents (max 5 parallel)
- **Role**: Implement stories following specs
- **Command**: `/bmad-dev-story` for each story implementation
- **Responsibilities**:
  - Read story file completely before coding
  - Follow architecture and design system specs
  - Write tests (80%+ coverage target)
  - Commit when story is complete
- **Parallelism Rules**:
  - Stories within the same epic: sequential (dependencies)
  - First stories across different epics: parallelizable
  - Max 5 concurrent dev agents to avoid rate limits

### Review Agents (2)
- **Role**: Adversarial code review on every completed story
- **Command**: `/bmad-code-review` on each story's changes
- **Responsibilities**:
  - Review ALL severity levels (CRITICAL, HIGH, MEDIUM, LOW)
  - Fix ALL issues found — no "optional" passes
  - Security review on auth, API, user data code
  - Verify test coverage meets 80% minimum
  - Verify no secrets, API keys, or personal info in code (public repo)

## Pipeline Flow

```
Lead creates story file
    -> Dev agent implements (/bmad-dev-story)
        -> Review agent 1: code quality + security (/bmad-code-review)
        -> Review agent 2: adversarial edge cases (/bmad-code-review)
            -> Fixes applied
                -> Commit & push
                    -> Next story
```

## Constraints

- **Zero paid APIs**: local models + free tiers + existing Claude subscription only
- **Public repo**: never commit secrets, API keys, personal info
- **No versioning/MVP**: full feature set from day one
- **BMAD commands only**: no ad-hoc coding outside story specs

## Epic Execution Order

1. Epic 1: Foundation (sequential, all stories depend on previous)
2. Epics 2-6: First stories parallelizable, then sequential within each
3. Epics 7-10: After core epics complete

## Context Management

- **Auto-compact at ~200k tokens**: When context window approaches ~200k tokens, compact the conversation before continuing
- Before compacting, update CREW.md "Current Status" section with latest progress
- After compacting, re-read CREW.md and story specs to restore context
- This prevents degraded output quality in the last 20% of context window

## Current Status

- Epic 1 (Stories 1.1-1.7): DONE, committed
- Story 5.1 (Adaptive Planner): DONE, committed
- Story 2.1 (Kanji Knowledge Graph): DONE, committed + reviewed
- Story 2.2 (Kanji Study & Radical Decomposition): DONE, committed + reviewed
- Story 3.1 (Stroke Order & Tracing): DONE, committed + reviewed
- Story 3.2 (Handwritten Kanji Recognition): DONE, committed + reviewed
- Story 4.1 (Audio & Listening): DONE, committed + reviewed
- Story 4.2 (Shadowing Exercises): DONE, committed + reviewed
- Story 5.2 (Immersive Session Transitions): DONE, committed + reviewed
- Story 6.1 (AI Router & Providers): DONE, committed + reviewed
- Story 2.3 (AI Mnemonic Generation): DONE, committed + reviewed
- Story 3.3 (Sentence Construction): DONE, committed + reviewed
- Story 4.3 (Pitch Accent Analysis): DONE, committed + reviewed
- Story 5.3 (Time & Context Adaptation): DONE, committed + reviewed
- Next: Stories 2.4, 2.5, 3.4, 4.4, 5.4 (remaining stories in epics 2-5)
- Epic 6: Only 6.1 done, 6.2-6.5 NOT STARTED
- Remaining epics 7-10: NOT STARTED
