# Ralph Workflow Map

## Overview
The Ralph workflow is a fail-closed, iterative loop designed to implement stories from a PRD (`plans/prd.json`) while strictly adhering to a Trading Contract (`CONTRACT.md`). It uses a harness (`plans/ralph.sh`) to orchestrate an AI agent, ensuring that every change is verified, contract-aligned, and tracked.

## Actors & Components

| Actor | Type | Implementation | Responsibility |
|-------|------|----------------|----------------|
| **Ralph Harness** | Orchestrator | `plans/ralph.sh` | Main loop, gate enforcement, agent invocation, state management. |
| **Agent** | AI/Tool | `claude` (configurable) | Implements stories, updates code, writes ideas/notes. |
| **Verifier** | Gatekeeper | `plans/verify.sh` | Runs tests, linters, and validations. Single source of truth for "green". |
| **Contract Checker** | Auditor | `plans/contract_check.sh` | Deterministic check of contract alignment (refs, scope, commit count). |
| **Schema Validator** | Validator | `plans/prd_schema_check.sh` | Ensures `prd.json` structure is valid. |
| **Task Updater** | Helper | `plans/update_task.sh` | Safely updates `passes=true` in `prd.json`. |
| **Story Cutter** | Generator | `plans/cut_prd.sh` | Generates/Refines `prd.json` from Plan & Contract. |
| **Human** | Supervisor | N/A | Resolves `needs_human_decision`, unblocks the harness. |

## Workflow Diagram

```mermaid
graph TD
    Start([Start]) --> Lock{Acquire Lock}
    Lock -- Fail --> ExitBlocked([Exit: Blocked])
    Lock -- Success --> Preflight

    subgraph Preflight
        Preflight[Check Tools & Git Status] --> CheckPRD{Check PRD Schema}
        CheckPRD -- Invalid --> ExitBlocked
        CheckPRD -- Valid --> InitEnv[Run init.sh]
    end

    InitEnv --> LoopStart

    subgraph Iteration Loop
        LoopStart([Iteration Start]) --> Rotate[Rotate Progress Log]
        Rotate --> Select{Select Story}
        Select -- Agent Selection --> AgentSelect[Agent Picks Item]
        Select -- Harness Selection --> HarnessSelect[Harness Picks Item]
        
        AgentSelect --> ValidateSelection{Validate Selection}
        HarnessSelect --> ValidateSelection
        
        ValidateSelection -- Invalid --> ExitBlocked
        ValidateSelection -- Needs Human --> ExitBlocked
        ValidateSelection -- Valid --> VerifyPre
        
        VerifyPre[Run Verify (Baseline)] --> PreCheck{Green?}
        PreCheck -- No --> SelfHeal{Self Heal Enabled?}
        SelfHeal -- Yes --> Revert[Revert to Last Good] --> VerifyPre
        SelfHeal -- No --> ExitBlocked
        
        PreCheck -- Yes --> PromptAgent[Construct Prompt]
        PromptAgent --> RunAgent[Run Agent]
        RunAgent --> AgentOutput[Agent Work / Output]
        
        AgentOutput --> Gates
        
        subgraph Gates
            Gates[Check Gates] --> CheckScope{Scope Violation?}
            CheckScope -- Yes --> ExitBlocked
            CheckScope -- No --> CheckCheat{Cheating?}
            CheckCheat -- Yes --> ExitBlocked
            CheckCheat -- No --> CheckHarnessMod{Harness Modified?}
            CheckHarnessMod -- Yes --> ExitBlocked
            CheckHarnessMod -- No --> VerifyPost
        end
        
        VerifyPost[Run Verify (Post-Work)] --> PostCheck{Green?}
        PostCheck -- No --> RevertPost[Revert / Block] --> ExitBlocked
        PostCheck -- Yes --> ContractReview
        
        ContractReview[Run Contract Check] --> ReviewCheck{Pass?}
        ReviewCheck -- No --> ExitBlocked
        ReviewCheck -- Yes --> UpdateTask[Update PRD: passes=true]
        
        UpdateTask --> Commit[Git Commit]
        Commit --> ProgressCheck{Progress Logged?}
        ProgressCheck -- No --> ExitBlocked
        ProgressCheck -- Yes --> CompletionCheck
        
        CompletionCheck{All Done?} -- Yes --> Success([Success: All Stories Passed])
        CompletionCheck -- No --> LoopStart
    end
```

## Detailed Flow

1.  **Initialization**:
    - Harness acquires a filesystem lock (`.ralph/lock`) to prevent concurrent runs.
    - Validates environment: `git`, `jq`, agents.
    - Validates `prd.json` schema using `plans/prd_schema_check.sh`.
    - Checks for dirty working tree (fail-closed).

2.  **Selection**:
    - Identifies the active slice (lowest slice with incomplete items).
    - Selects the highest priority incomplete item in that slice.
    - **Gate**: If `needs_human_decision=true`, execution stops with a block artifact.

3.  **Baseline Verification (`verify_pre`)**:
    - Runs `plans/verify.sh` to ensure the repo is green before starting.
    - **Self-Heal**: If enabled (`RPH_SELF_HEAL=1`), Ralph attempts to `git reset --hard` to the last known good state if baseline fails.

4.  **Execution**:
    - Constructs a prompt including: `prd.json`, `progress.txt`, `AGENTS.md`, and the selected story.
    - Invokes the agent (`claude` etc.) to implement *only* the selected story.
    - Agent is expected to: read context, implement code, verify locally, and append to `progress.txt`.

5.  **Post-Execution Gating**:
    - **Mark Pass Check**: Ensures the agent output the correct `<mark_pass>ID</mark_pass>` tag.
    - **PRD Integrity**: Checks that the agent did not modify `prd.json` directly (unless allowed).
    - **Harness Integrity**: Checks that `ralph.sh`, `verify.sh`, etc., were not modified.
    - **Scope Check**: Verifies changed files match `scope.touch` and do not match `scope.avoid`.
    - **Cheat Detection**: Scans for deleted tests, added skips, or removed assertions.

6.  **Verification (`verify_post`)**:
    - Runs `plans/verify.sh` again.
    - If failed, the iteration is blocked (or rolled back if self-heal is on).

7.  **Contract Review**:
    - Runs `plans/contract_check.sh`.
    - Produces `contract_review.json`.
    - Validates the review artifact schema.
    - **Gate**: If decision is not `PASS`, the task is *not* marked as complete.

8.  **Finalization**:
    - If all gates pass, `plans/update_task.sh` is called to flip `passes=true` in `prd.json`.
    - Changes are committed to git.
    - `progress.txt` is checked for a valid append-only entry.

9.  **Completion**:
    - Ralph checks if all items in `prd.json` are passed.
    - If so, runs a final verify and exits successfully.
