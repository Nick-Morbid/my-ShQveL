# Local modifications to the original ShQveL implementation

This document records the changes made during the MySQL/PostgreSQL investigation and controlled ShQveL experiments.
The comparison baseline is upstream commit `1405d4eb5b7af7a639717a47147bd89362558830` from
`https://github.com/suyZhong/SQLancerPlusPlus.git`. The record intentionally does not contain the local API key or the
contents of `dbconfigs/llm.properties`.

## Scope and design rule

The learning sketch, fragment categories, SQL generator, feedback algorithm, candidate validation SQL, and LLM prompt
semantics were left unchanged. The code changes are limited to making the original workflow runnable with an
OpenAI-compatible relay, selecting reproducible documentation, controlling experimental learning passes, supporting
PostgreSQL/MySQL execution, and saving/restoring the learned in-memory state.

There are three execution modes after these changes:

1. Normal online learning: the original ShQveL behavior, with fragments learned and used during fuzzing.
2. Frozen checkpoint fuzzing: load a completed checkpoint, disable every LLM learning path, and only fuzz.
3. Resume learning: load a checkpoint, retain LLM learning, merge another validated topic round, and save a new
   checkpoint.

## LLM relay and local configuration

Files: `.gitignore`, `dbconfigs/llm.properties.example`, `src/chat.py`,
`src/sqlancer/general/learner/GeneralTemplateLearner.java`, and `requirements.txt`.

- Replaced the hard-coded OpenAI endpoint and `OPENAI_API_KEY` dependency with `dbconfigs/llm.properties`.
- Added configurable `api_key`, `base_url`, `fragment_model`, and `summary_model` values.
- Normalized trailing slashes and accepted either an API root or a full `/chat/completions` URL.
- Added HTTP status checking and response-body error reporting in the Java caller.
- Added connection/read timeouts and ensured the HTTP response is closed.
- Added `dbconfigs/llm.properties` to `.gitignore`; only an empty example is tracked.
- Added the `--llm-config` argument to the Python documentation summarizer.
- Added `langchain-classic` and a compatibility import for current LangChain package layouts.
- Added a minimal user turn to documentation-summary prompts while retaining the original system instructions. This
  supports OpenAI-compatible models, including GLM endpoints, that reject a `messages` array containing only a system
  message.
- For model names beginning with `glm-`, added the officially documented `thinking: {"type": "disabled"}` request
  parameter in both Python and Java callers. GLM-5.1 enables Thinking by default; ShQveL's short summarization/CSV tasks
  do not need long-running agentic reasoning. Other model families retain their previous request body.
- Added a bounded timeout and retry count to the Python OpenAI-compatible client so a stalled summary request cannot
  block an entire learning round indefinitely.

The local secret-bearing `dbconfigs/llm.properties` is an experiment input, not a source artifact, and must not be
committed.

## Documentation retrieval and YAML selection

Files: `src/chat.py`, `src/sqlancer/general/GeneralOptions.java`,
`src/sqlancer/general/learner/GeneralTemplateLearner.java`, `dbconfigs/mysql-url.yml`,
`dbconfigs/mysql-url-8.4.yml`, and `dbconfigs/postgresql-url.yml`.

- Added `general --documentation-yaml FILE`; relative files resolve under `dbconfigs`, while absolute paths are kept.
- Forwarded the selected YAML file from Java to `src/chat.py`.
- Added MySQL to the Python DBMS-name mapping.
- Made topic lookup case-insensitive and removed parenthesized qualifiers when looking up a fallback topic name.
- Replaced random selection of one documentation page with deterministic loading of at most three configured pages.
  This matches the paper's RAG `N=3` setting more closely.
- Added per-page retry and timeout behavior; one unavailable page no longer discards other retrieved pages.
- Kept Google search as an optional fallback for topics absent from YAML.
- Added broad official MySQL 9.4, MySQL 8.4 fallback, and PostgreSQL 18 documentation catalogs. These catalogs list
  documentation families rather than leaking the target feature names.

## Fragment response parsing and CSV delimiter fixes

Files: `src/sqlancer/general/learner/GeneralTemplateLearner.java`, `src/sqlancer/general/GeneralSchema.java`, and
`src/sqlancer/general/ast/GeneralFunction.java`.

- Changed built-in fragment examples from comma-separated rows to the semicolon format expected by the parser and
  requested by the prompt.
- Replaced the previous response parser, which blindly dropped the first and last lines, with line filtering that
  removes blank/Markdown-fence lines and retains semicolon-bearing fragment rows.

These changes repair transport/parsing mismatches; they do not alter the sketch placeholders or candidate meaning.

## Controlled datatype-focused experiments

Files: `src/sqlancer/general/GeneralOptions.java`, `src/sqlancer/general/GeneralProvider.java`,
`dbconfigs/postgresql/typegenerator.txt`, and `dbconfigs/postgresql/disabled_options.csv`.

- Added `--configured-datatypes-only true`. It keeps the preconfigured datatype pool and suppresses the broad datatype
  overview discovery pass while still allowing per-datatype function/operator learning.
- Added `--enable-function-overview-learning false`. It suppresses both startup and runtime broad function-overview
  learning, leaving datatype-focused learning enabled.
- Added a fixed PostgreSQL experiment pool with 15 validated types: `INTEGER`, `BIT`, `BOOLEAN`, `BYTEA`, `CHARACTER`,
  `DATE`, `DOUBLE PRECISION`, `TEXT`, `TIME`, `TIMESTAMP`, `CIDR`, `INET`, `MACADDR`, `MACADDR8`, and `UUID`.
- Added DBMS-specific disabled-option CSV files used by the experimental runs.

## MySQL execution preparation

Files: `src/sqlancer/general/GeneralOptions.java`, `dbconfigs/mysql/disabled_options.csv`,
`dbconfigs/mysql-url.yml`, and `dbconfigs/mysql-url-8.4.yml`.

- Added MySQL cleanup behavior to reuse a server/database safely across generated databases by dropping generated
  views and tables before each run.
- Added MySQL documentation and disabled-option configuration files.

This is execution preparation only; it does not add a MySQL-specific grammar or change ShQveL's sketch.

## Complete learned-state checkpoints

Files: `src/sqlancer/general/GeneralLearnedState.java`, `src/sqlancer/general/GeneralLearningManager.java`,
`src/sqlancer/general/GeneralOptions.java`, `src/sqlancer/general/GeneralProvider.java`,
`src/sqlancer/general/GeneralSchema.java`, `src/sqlancer/general/ast/GeneralFunction.java`,
`src/sqlancer/general/ast/GeneralBinaryOperator.java`, and
`src/sqlancer/general/learner/GeneralFragments.java`.

### Save

`general --save-learned-fragments FILE` atomically writes a versioned JSON checkpoint after a complete datatype-topic
round. It saves:

- datatype fragments and availability;
- function fragments and the effective function-to-arity map;
- operator fragments and the effective operator-to-type map;
- datatype-to-function associations;
- statement, table, and index fragments;
- checkpoint format version and DBMS identity.

Temporary-file plus atomic-move semantics prevent a partially written checkpoint from appearing complete.

### Frozen load

`general --load-learned-fragments FILE` restores the checkpoint before database generation. In this mode
`isLearningEnabled` returns false for every feature class, initialization returns before any learner call, and dynamic
learning is bypassed. It is intended for an independent fuzzing/evaluation phase and does not need API credentials.

### Resume

`general --resume-learned-fragments FILE` restores the same complete state without disabling learning. With global
`--enable-learning`, the normal scheduler starts a new complete topic round, directly validates new candidates, merges
non-duplicate fragments with the restored state, and can write the result via `--save-learned-fragments`.

Frozen load and resume are mutually exclusive. Resume means a new topic round from persisted state; it cannot resume
an interrupted HTTP/LLM request. Use one learning thread for reproducible checkpoint production and save the next round
to a new filename.

Example:

```bash
java -jar target/sqlancer-2.0.0.jar \
  --enable-extra-features --enable-learning --num-threads 1 --num-tries 1000 \
  general --database-engine postgresql --documentation-yaml postgresql-url.yml \
  --configured-datatypes-only true --enable-function-overview-learning false \
  --enable-statement-learning false --enable-datatype-learning true \
  --enable-expression-learning true --enable-clause-learning false \
  --enable-direct-validation true --learning-interval-seconds 0 --oracle FUZZING \
  --resume-learned-fragments logs/postgresql-focused/postgresql-learned.json \
  --save-learned-fragments logs/postgresql-focused/postgresql-learned-round2.json
```

## Tests and analysis tooling

Files: `test/sqlancer/general/GeneralLearnedStateTest.java` and `scripts/analyze_postgresql_round.sh`.

- Added a checkpoint round-trip test covering datatype fragments, function arity, operator type, type/function mapping,
  type availability, frozen-load learning suppression, and resume-mode learning retention.
- Added a standalone analysis script that parses first-round learner logs and can test simple typed compositions against
  the local PostgreSQL container. This script is analysis tooling and is not called by ShQveL.

Targeted test command:

```bash
mvn -q -Djacoco.skip=true -Dtest=GeneralLearnedStateTest test
```

The targeted test and `mvn -DskipTests package` pass. The repository's full test suite currently has unrelated existing
failures involving SQLite command registration, Java-module reflection, and an ExpectedErrors regex; those are not
caused by the checkpoint changes.

## Documentation changes

File: `docs/ShQveL.md`.

- Documented local LLM configuration and relay usage.
- Documented YAML selection, MySQL/PostgreSQL setup, controlled datatype learning, direct validation, checkpoint save,
  frozen fuzzing, and resumed learning commands.

## Experiment environment and generated artifacts

The following are runtime setup/results rather than source-code changes:

- Conda environment: `/usr/local/miniconda3/envs/shqvel`.
- PostgreSQL container: `shqvel-postgres`, PostgreSQL 18, exposed on local port 5433.
- Training/fuzzing artifacts under `logs/postgresql-focused/`, including the first-round checkpoint and raw SQL logs.
- The `logs/` directory remains ignored except for its existing `.gitkeep`; generated logs and checkpoints should be
  archived separately when needed for a paper artifact.

The first saved PostgreSQL checkpoint covered all 15 configured datatypes. A frozen 1,000-query fuzzing run loaded that
checkpoint without learner calls and executed 383 queries successfully (38.3%). This number is an experiment result,
not a hard-coded expectation or implementation change.

## Known limitations intentionally preserved

- Direct validation still uses untyped `NULL` for many functions/operators and can produce false positives.
- Function fragments still encode name and arity, not a full typed signature or return type.
- Operator fragments can contain operands even where the generator expects only an operator token.
- Function validation still directly handles only arities represented by the existing sketch.
- Non-deterministic functions can pass DBMS validation despite the prompt requesting deterministic functions.
- Checkpoint-loaded fragments are used by generation, but the existing `GeneralErrorHandler` fragment-option report does
  not register them, so it can display `Fragment features enabled: 0 / 0`. Generated SQL provides the usage evidence.

These limitations were not fixed because doing so would change the ShQveL learning/representation semantics being
evaluated.

## 24-hour PostgreSQL observability harness (outside the repository)

`/app/my_ShQveL` is a separate experiment harness; it does not change prompts,
fragment sketches, validation, scheduling, or SQL generation. It adds an
isolated PostgreSQL 18.3 coverage build on port 55433, hourly cumulative lcov
snapshots with raw branch data, byte-exact SQL/runtime/PostgreSQL log chunks,
NFS checksum/commit handling, token/response telemetry, server-derived SQL
success metrics, replay extraction, and bounded local-disk cleanup after a
verified upload. PostgreSQL CSV logging is authoritative and recognizes both
simple-protocol `statement:` and JDBC extended-protocol `execute <name>:`
records. The existing PostgreSQL container on port 5433 is not managed by the
harness.

The final harness audit added a separate `final-artifacts` commit so SQL and
checkpoints racing with the 24-hour timeout boundary are not lost. Coverage
sub-checksums are relative paths and can therefore be independently verified
after transfer to NFS.

Further fault-injection audits added content-checking NFS retries, bounded
whole-process-group termination on harness failures, lcov retry/timing data,
per-epoch versus cumulative token metrics, and idempotent replay
reconstruction. These remain outside ShQveL's learning/generation semantics.

## GLM request compatibility

The OpenAI-compatible request paths have small, model-specific transport adaptations; they do not change prompts,
sketch parsing, validation, or generation semantics. A GLM request always includes both a system message and a user
message because the provider rejects a system-only message list. GLM-5.1 uses
`thinking.type=disabled`. GLM-5.3 cannot disable thinking, so both the Python documentation-summary request and the
Java fragment-generation request use `thinking.type=enabled` with top-level `reasoning_effort=low`, as required by
the provider's GLM-5.3 migration documentation. The Python client also uses a 120-second timeout and one retry.

## File inventory relative to upstream

Modified tracked files:

- `.gitignore`
- `docs/ShQveL.md`
- `requirements.txt`
- `src/chat.py`
- `src/sqlancer/general/GeneralLearningManager.java`
- `src/sqlancer/general/GeneralOptions.java`
- `src/sqlancer/general/GeneralProvider.java`
- `src/sqlancer/general/GeneralSchema.java`
- `src/sqlancer/general/ast/GeneralBinaryOperator.java`
- `src/sqlancer/general/ast/GeneralFunction.java`
- `src/sqlancer/general/learner/GeneralFragments.java`
- `src/sqlancer/general/learner/GeneralTemplateLearner.java`

New source/configuration files:

- `docs/ShQveL-local-modifications.md`
- `src/sqlancer/general/GeneralLearnedState.java`
- `test/sqlancer/general/GeneralLearnedStateTest.java`
- `scripts/analyze_postgresql_round.sh`
- `dbconfigs/llm.properties.example`
- `dbconfigs/mysql-url.yml`
- `dbconfigs/mysql-url-8.4.yml`
- `dbconfigs/mysql/disabled_options.csv`
- `dbconfigs/postgresql-url.yml`
- `dbconfigs/postgresql/typegenerator.txt`
- `dbconfigs/postgresql/disabled_options.csv`
- `dbconfigs/mariadb-url-12.2.yml`
- `dbconfigs/mariadb/disabled_options.csv`
- `dbconfigs/tidb-url-8.5.yml`
- `dbconfigs/tidb/disabled_options.csv`

The Python documentation-loader DBMS mapping also contains explicit `mariadb -> MariaDB` and `tidb -> TiDB` entries.
They only select the correct top-level official-documentation YAML key; they do not change prompts, sketch syntax,
validation, scheduling, or SQL generation.
