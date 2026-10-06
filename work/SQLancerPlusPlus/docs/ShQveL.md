# ShQveL component

ShQveL augments SQLancer++'s dialect-agnostic generator with SQL fragments synthesized for the target DBMS. The learned fragments are loaded into the existing statement, schema, expression, and clause generators; ShQveL does not replace those generators.

Two global options enable the integration:

- `--enable-extra-features`: enable the external feature fragments
- `--enable-learning`: enable the learning of the feature fragments

The `general` command provides finer controls. Statement, data-type, expression, and clause learning are enabled by default and can be switched off independently with `--enable-statement-learning`, `--enable-datatype-learning`, `--enable-expression-learning`, and `--enable-clause-learning`. `--learning-interval-seconds` controls the minimum interval between dynamic learning requests and defaults to 60 seconds; setting it to 0 disables throttling.

`--enable-direct-validation true` executes validation SQL through the target DBMS's JDBC driver before retaining newly learned fragments. Validation uses a separate native connection and removes candidates rejected by the DBMS. Fragment kinds without a safe validation statement remain available without direct validation.

Requirements:

- An API key for an OpenAI-compatible service
- Python 3.12 or above

ShQveL reads its API settings from `dbconfigs/llm.properties`. Copy the example
configuration before the first run, then edit the local file and set `api_key`:

```properties
api_key=YOUR_ZHIZENGZENG_KEY
base_url=https://api.zhizengzeng.com/v1
fragment_model=gpt-4o
summary_model=gpt-4o-mini
```

Both the Java fragment synthesizer and the Python documentation summarizer use
this configuration. The real `dbconfigs/llm.properties` file is ignored by Git
to prevent accidentally committing a key; `dbconfigs/llm.properties.example`
is the tracked template.

Documentation retrieval first uses the official URLs in `dbconfigs/url.yml`, so a search API is not required for the configured DBMS and feature. Google search credentials remain an optional fallback for missing mappings and can be supplied through `GOOGLE_API_KEY` and `GOOGLE_CSE_ID` environment variables or the legacy files under `dbconfigs/`. This fallback additionally requires `langchain-google-community`.

Use `general --documentation-yaml FILE` to select another URL configuration. Relative paths are resolved under
`dbconfigs`; absolute paths are also accepted. Up to three configured URLs for a topic are fetched and summarized
together, matching the paper's RAG setting. For example, MySQL's open-ended configuration is selected with
`--documentation-yaml mysql-url.yml`. Its entries are broad official documentation categories rather than a target
feature list, so evaluation features are not leaked into learning.

`mysql-url.yml` points to the requested MySQL 9.4 manual. If `dev.mysql.com` blocks automated retrieval,
`mysql-url-8.4.yml` is a runnable fallback using Oracle's official MySQL 8.4 archive; results obtained with that
fallback must be labeled as 8.4-documentation training even when the validation server is MySQL 9.4.

For PostgreSQL 18, `postgresql-url.yml` provides open-ended, datatype-oriented official documentation inputs without
including the evaluation feature catalog. A local validation target can be started and selected as follows:

```bash
docker run -d --name shqvel-postgres -p 127.0.0.1:5433:5432 \
  -e POSTGRES_PASSWORD=shqvel-postgres -e POSTGRES_DB=shqvel postgres:18

SQLANCER_POSTGRESQL_URL='jdbc:postgresql://127.0.0.1:5433/shqvel?user=postgres&password=shqvel-postgres' \
java -jar target/sqlancer-2.0.0.jar \
  --enable-extra-features --enable-learning --num-threads 1 --num-tries 200 \
  general --database-engine postgresql --documentation-yaml postgresql-url.yml \
  --enable-statement-learning false --enable-datatype-learning true \
  --enable-expression-learning true --enable-clause-learning false \
  --enable-direct-validation true --learning-interval-seconds 0 --oracle FUZZING
```

For a controlled comparison over only the datatypes preloaded in
`dbconfigs/postgresql/typegenerator.txt`, add `--configured-datatypes-only true`. Keep
`--enable-datatype-learning true`: it drives datatype-focused expression learning, while the new option suppresses
the datatype-overview discovery pass. Add `--enable-function-overview-learning false` to suppress the broad startup
function pass, ensuring that learned functions come only from the selected datatype topics.

## Separating learning from fuzzing

`general --save-learned-fragments FILE` writes an atomic JSON checkpoint when all datatype topics have completed a
learning round. The checkpoint contains datatype, function, operator, statement, table, and index fragments, function
arities, operator types, datatype-to-function associations, and datatype availability. Use one learning thread when
creating a checkpoint.

```bash
SQLANCER_POSTGRESQL_URL='jdbc:postgresql://127.0.0.1:5433/shqvel?user=postgres&password=shqvel-postgres' \
java -jar target/sqlancer-2.0.0.jar \
  --enable-extra-features --enable-learning --num-threads 1 --num-tries 1000 \
  general --database-engine postgresql --documentation-yaml postgresql-url.yml \
  --configured-datatypes-only true --enable-function-overview-learning false \
  --enable-statement-learning false --enable-datatype-learning true \
  --enable-expression-learning true --enable-clause-learning false \
  --enable-direct-validation true --learning-interval-seconds 0 --oracle FUZZING \
  --save-learned-fragments logs/postgresql-focused/postgresql-learned.json
```

After the log reports that the checkpoint was saved, stop the training process. A separate fuzzing run loads that
checkpoint with `general --load-learned-fragments FILE`. Loading a checkpoint disables every LLM learning path for the
run, even if `--enable-learning` was supplied accidentally. The global learning flag should normally be omitted so the
standard fuzzing execution path is used:

```bash
SQLANCER_POSTGRESQL_URL='jdbc:postgresql://127.0.0.1:5433/shqvel?user=postgres&password=shqvel-postgres' \
java -jar target/sqlancer-2.0.0.jar \
  --num-threads 1 --num-tries 1000 --log-each-select \
  general --database-engine postgresql --oracle FUZZING \
  --load-learned-fragments logs/postgresql-focused/postgresql-learned.json
```

The load path does not read `dbconfigs/llm.properties`, invoke `src/chat.py`, or contact an LLM service. SQLancer's
normal `successful statements` counter therefore measures only fuzzing with the frozen checkpoint. Use a fixed random
seed, query/database budget, and timeout when comparing multiple generators.

To continue learning from an existing checkpoint instead of freezing it, use
`general --resume-learned-fragments INPUT` together with global `--enable-learning`. New validated fragments are merged
with the restored state and duplicates are ignored. Save the next completed round to a different file so that the
input remains reproducible:

```bash
SQLANCER_POSTGRESQL_URL='jdbc:postgresql://127.0.0.1:5433/shqvel?user=postgres&password=shqvel-postgres' \
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

`--load-learned-fragments` and `--resume-learned-fragments` are mutually exclusive. Resume starts a new complete topic
round from the restored state; it does not continue an interrupted LLM request.

```bash
# Install the requirements for documentation retrieval
pip install -r requirements.txt
```

For example, to test DuckDB with learning, native validation, and extra features enabled, run:

```bash
java -jar target/sqlancer-2.0.0.jar \
  --use-reducer --enable-extra-features --enable-learning --num-threads 1 --num-tries 200 \
  general --database-engine duckdb --oracle WHERE --enable-direct-validation true
```

For an isolated MySQL 9.4 target:

```bash
docker run -d --name shqvel-mysql -p 127.0.0.1:3307:3306 \
  -e MYSQL_ROOT_PASSWORD=shqvel-root -e MYSQL_DATABASE=shqvel mysql:9.4

SQLANCER_MYSQL_URL='jdbc:mysql://127.0.0.1:3307/shqvel?user=root&password=shqvel-root' \
java -jar target/sqlancer-2.0.0.jar \
  --enable-extra-features --enable-learning --num-threads 1 --num-tries 200 \
  general --database-engine mysql --documentation-yaml mysql-url.yml \
  --enable-statement-learning false --enable-datatype-learning true \
  --enable-expression-learning true --enable-clause-learning false \
  --enable-direct-validation true --learning-interval-seconds 0 --oracle FUZZING
```
