<div align="center">

# 🛂 StaffOS

### The trust, review, and documentation layer for AI-assisted engineering

StaffOS turns every Claude Code session into a verified engineering record —
**intent, files touched, tests run, risks found, decisions made, and the human
review required.**

<br/>

[![CI](https://github.com/rajgurung/staffOS/actions/workflows/ci.yml/badge.svg)](https://github.com/rajgurung/staffOS/actions/workflows/ci.yml)
[![Deploy](https://github.com/rajgurung/staffOS/actions/workflows/deploy.yml/badge.svg)](https://github.com/rajgurung/staffOS/actions/workflows/deploy.yml)
[![Coverage](https://img.shields.io/badge/coverage-72%25-green)](https://github.com/rajgurung/staffOS/actions/workflows/ci.yml)
[![Tests](https://img.shields.io/badge/tests-34_passing-success)](test/)

[![Ruby](https://img.shields.io/badge/Ruby-3.4-CC342D?logo=ruby&logoColor=white)](.ruby-version)
[![Rails](https://img.shields.io/badge/Rails-8.1-CC0000?logo=rubyonrails&logoColor=white)](Gemfile)
[![Code Style](https://img.shields.io/badge/code_style-RuboCop_Omakase-6E4A7E?logo=rubocop&logoColor=white)](.rubocop.yml)
[![Security](https://img.shields.io/badge/security-Brakeman-FB9A41)](https://brakemanscanner.org/)
[![AI](https://img.shields.io/badge/reviewers-Claude_Opus_4.8-D97757?logo=anthropic&logoColor=white)](app/services/llm_client.rb)

</div>

---

## Why StaffOS

AI coding agents are becoming the worker. The hard part is no longer *writing*
code — it's **trusting, reviewing, governing, and remembering** what the agent did.

A normal dashboard says *"Claude Code ran."*
StaffOS says *"Claude Code made **this** change, with **this** risk level, **these**
tests, **these** missing checks, and **this** documentation requirement."*

## The Run Passport

Every session on a branch produces a living **Run Passport** — a structured,
versioned record that answers the questions a reviewer actually asks:

| | |
|---|---|
| 🎯 **Intent** | What was the goal? |
| 📂 **Files touched** | What was inspected and changed? |
| 🧪 **Test evidence** | What passed, what failed, what wasn't run? |
| ⚠️ **Risk score** | Deterministic rules — auth/payments/infra = high |
| ✅ **Missing checks** | The gaps to close before merge |
| 👤 **Human review** | Is sign-off required? |
| 📝 **Documentation** | ADRs, decision logs, and PR summaries to save |

Passports **mutate** as work continues and capture **immutable version snapshots**
at each milestone, giving a clear timeline of how a change matured.

## AI review, three modes

StaffOS is deliberate about when it spends tokens (configurable, see below):

| Mode | What it does | Model |
|------|--------------|-------|
| **Passive** | Records events, builds the timeline. No LLM call. | — |
| **Smart Summary** | Summarises the session and extracts review gaps. | Claude Haiku 4.5 |
| **Full Council** | Six personas (Staff Eng, SRE, Security, PM, Devil's Advocate, Writing Coach) review the change. | Claude Opus 4.8 |

> Risk **level** always stays deterministic (spec §15). The LLM enriches the
> narrative and findings; it never overrides the rules. **Only metadata is sent**
> — file paths, categories, test summaries — never your source code.
> No API key? Every mode degrades gracefully to deterministic heuristics.

## Architecture

```
Claude Code ─▶ Claude Code hooks ─▶ StaffOS connector ─▶ Ingestion API
     │                                                         │
     │                                                         ▼
     │                                                  Run event store
     │                                                         │
     ▼                                                         ▼
 Web dashboard ◀─ Documentation engine ◀─ Passport generator ◀─ Risk engine
```

Everything is scoped to a **Project** (a repo) → **Workstream** (a branch) →
sessions, events, passport, council reviews, documents, and memory. On merge,
knowledge promotes to the project's permanent knowledge base. Zero cross-project
leaking.

## Quick start

```bash
# 1. Install dependencies and prepare the database
bin/setup            # or: bundle install && bin/rails db:prepare db:seed

# 2. Run the app
bin/dev              # http://localhost:3000

# 3. (optional) Enable AI reviewers
export ANTHROPIC_API_KEY=sk-ant-...
```

### Install the CLI

```bash
brew install rajgurung/tap/staffos
```

No Homebrew? The CLI is a single, dependency-free Ruby script — grab it from the
[latest release](https://github.com/rajgurung/staffOS/releases) or run
`cli/staffos` straight from a checkout.

### Connect a repo with the CLI

```bash
staffos login        # enter your endpoint + project token
staffos init         # writes .staffos.yml and installs Claude Code hooks
# ...use Claude Code normally — events are captured automatically...
staffos passport     # see the latest passport for your branch
staffos disconnect   # remove credentials and hooks
```

`init` installs HTTP hooks (`SessionStart`, `UserPromptSubmit`, pre/post tool
use, `Stop`) into `.claude/settings.json`. Claude Code POSTs each event to
StaffOS, which routes it to the right Workstream by branch.

## Configuration

| Environment variable | Purpose | Default |
|----------------------|---------|---------|
| `ANTHROPIC_API_KEY` | Enables Smart Summary + Full Council. Unset → heuristics. | — |
| `STAFFOS_SUMMARY_MODEL` | Model for smart summaries | `claude-haiku-4-5` |
| `STAFFOS_COUNCIL_MODEL` | Model for council reviews | `claude-opus-4-8` |

The key can also live in Rails encrypted credentials under `anthropic.api_key`.

## Testing

```bash
bin/rails test                 # full suite (Minitest)
COVERAGE=false bin/rails test  # skip coverage instrumentation
```

The suite covers the risk engine, passport generation, the AI council's
heuristic fallback, the document generator, the model layer, the Claude Code
hook ingestion API, and the authenticated UI flows. Coverage is measured with
SimpleCov and reported in CI.

## CI/CD

| Workflow | Runs | Does |
|----------|------|------|
| **CI** (`ci.yml`) | every push & PR | Minitest + coverage, RuboCop (Omakase), Brakeman, bundler-audit, importmap audit |
| **Deploy** (`deploy.yml`) | push to `main` | Kamal deploy, gated on `KAMAL_REGISTRY_PASSWORD` — skips cleanly until you wire a server |

## Tech stack

**Rails 8.1** · **Hotwire** (Turbo + Stimulus) · **Tailwind CSS** ·
**PostgreSQL** · **Solid** Queue/Cache/Cable · **Devise** ·
**Anthropic Ruby SDK** · **Kamal** · **Minitest + SimpleCov**

## Project layout

```
app/services/        risk_scorer · passport_generator · council_runner
                     document_generator · llm_client
app/controllers/api/ Claude Code hook ingestion (v1)
cli/staffos          local connector CLI
db/                  schema, migrations, seed data
test/                services · models · integration (API + UI)
SPEC.md              the full product brief
```

---

<div align="center">
<sub>Built to make AI-assisted engineering <strong>trustworthy</strong>, <strong>reviewable</strong>, and <strong>remembered</strong>.</sub>
</div>
