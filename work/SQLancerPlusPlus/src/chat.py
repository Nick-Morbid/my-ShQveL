import argparse
import json
import os
import re
import sys
import time
from collections import defaultdict

# WebBaseLoader uses this value for outbound HTTP requests. Respect an explicit caller value while providing a
# descriptive default for local ShQveL runs.
os.environ.setdefault("USER_AGENT", "SQLancerPlusPlus-ShQveL/1.0 (+https://github.com/suyZhong/SQLancerPlusPlus)")

import yaml

from langchain_community.document_loaders import WebBaseLoader
from langchain_community.callbacks.manager import get_openai_callback
from langchain_openai import ChatOpenAI
from langchain_core.prompts import ChatPromptTemplate
try:
    from langchain_classic.chains.combine_documents import create_stuff_documents_chain
except ImportError:
    from langchain.chains.combine_documents import create_stuff_documents_chain

DBMS_MAPPING = defaultdict(lambda: "Unknown", {
    "duckdb" : "DuckDB",
    "postgresql" : "PostgreSQL",
    "postgres" : "PostgreSQL",
    "cedardb" : "CedarDB",
    "cratedb" : "CrateDB",
    "cockroachdb" : "CockroachDB",
    "sqlite" : "SQLite",
    "mysql" : "MySQL",
    "mariadb" : "MariaDB",
    "tidb" : "TiDB",
})

OVERWRITE = True
DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_DIR = os.path.join(DIR, "..", "dbconfigs")
YAML_DIR = CONFIG_DIR + "/url.yml"
DEFAULT_OPENAI_BASE_URL = "https://api.zhizengzeng.com/v1"
DEFAULT_LLM_CONFIG = os.path.join(CONFIG_DIR, "llm.properties")

PROMPTS = {
    "datatype_general" : [("system", "What are the data types in {DBMS} based on the documentation: \\n\\n {context}.\\n\\n Give me example values and definitions in CREATE TABLE statements")],
    "datatype_specific" : [("system", "What are {topic} for {DBMS} based on the documentation: \\n\\n {context}.\\n\\n Give me only names and examples. Please list all the possible values.")],
    "function_general" : [("system", "What are the functions in {DBMS} based on the documentation: \\n\\n {context}.\\n\\n Give me example usage and syntax.")],
    "function_specific" : [("system", "What are {topic} in {DBMS} based on the documentation: \\n\\n {context}.\\n\\n Give me as many example usage and syntax as possible.")],
    "all_specific" : [("system", "What are {topic} in {DBMS} based on the documentation: \\n\\n {context}.\\n\\n Give me example usage and syntax.")],
    "clause_specific" : [("system", "What are {topic} in {DBMS} based on the documentation: \\n\\n {context}.\\n\\n Give me examples usage, syntax and detailed keywords.")],
    "command_specific" : [("system", "What are {topic} in {DBMS} based on the documentation: \\n\\n {context}.\\n\\n Give me exampes.")],
}

def get_docs_by_URLs(urls: list[str]):
    # The ShQveL paper retrieves the top N=3 official documentation pages for a
    # topic and summarizes them together. YAML entries are the deterministic,
    # reproducible equivalent of those search results.
    docs = []
    errors = []
    for url in urls[:3]:
        for attempt in range(2):
            try:
                docs.extend(WebBaseLoader(url, requests_kwargs={"timeout": 20}, raise_for_status=True).load())
                break
            except Exception as error:  # a single unavailable search result must not discard the others
                if attempt == 1:
                    errors.append(f"{url}: {error}")
    for error in errors:
        print(f"Warning: unable to retrieve documentation page {error}", file=sys.stderr)
    if not docs:
        raise RuntimeError("Unable to retrieve any configured documentation page")
    return docs


def resolve_yaml_path(configured_path: str) -> str:
    if not configured_path:
        return YAML_DIR
    if os.path.isabs(configured_path):
        return configured_path
    return os.path.join(CONFIG_DIR, configured_path)

def load_llm_config(path: str) -> dict:
    config = {}
    try:
        with open(path, encoding="utf-8") as config_file:
            for raw_line in config_file:
                line = raw_line.strip()
                if not line or line.startswith(("#", "!")) or "=" not in line:
                    continue
                key, value = line.split("=", 1)
                config[key.strip()] = value.strip()
    except OSError as error:
        raise RuntimeError(f"Cannot read LLM configuration {path}: {error}") from error
    return config

def configure_google_search() -> bool:
    credentials = {
        "GOOGLE_API_KEY": "GOOGLE_API.txt",
        "GOOGLE_CSE_ID": "GOOGLE_CSE.txt",
    }
    for environment_variable, file_name in credentials.items():
        if os.getenv(environment_variable):
            continue
        credential_file = os.path.join(CONFIG_DIR, file_name)
        if os.path.isfile(credential_file):
            with open(credential_file) as credential:
                os.environ[environment_variable] = credential.read().strip()
    return all(os.getenv(environment_variable) for environment_variable in credentials)

def search_google_get_first_link(query: str):
    if not configure_google_search():
        raise RuntimeError(
            "No documentation URL is configured and Google search credentials are unavailable. "
            "Add an official documentation URL to dbconfigs/url.yml, or set GOOGLE_API_KEY and GOOGLE_CSE_ID."
        )

    from langchain_google_community import GoogleSearchAPIWrapper

    search = GoogleSearchAPIWrapper()
    print(f"Search result for {query}:")
    result = search.results(query, 5)
    return result[0]["link"]

def get_urls_from_yaml(dbms: str, feature: str, dir: str, topic: str = "") -> list:
    with open(dir) as f:
        url_yaml = yaml.safe_load(f) or {}

    updated = False
    # get the dict to the level of feature
    try:
        feature_dict = url_yaml[dbms][feature]
    except (KeyError, TypeError):
        url = search_google_get_first_link(f"{dbms} {feature} documentation")
        print(f"Automatically found the URL for {dbms} {feature} documentation: {url}")
        url_yaml.setdefault(dbms, {})[feature] = {"overview": [url]}
        feature_dict = url_yaml[dbms][feature]
        updated = True

    # get the fine-grained urls
    urls = []
    if topic == "" or topic == "overview":
        try:
            urls = feature_dict["overview"]
        except KeyError:
            raise ValueError(f"Please provide a valid feature. Available options are: {list(feature_dict.keys())}")
    else:
        topic_candidates = [topic.casefold()]
        base_topic = re.sub(r"\([^)]*\)", "", topic).strip().casefold()
        if base_topic not in topic_candidates:
            topic_candidates.append(base_topic)
        configured_topics = {str(key).casefold(): key for key in feature_dict}
        matched_topic = next((configured_topics[key] for key in topic_candidates if key in configured_topics), None)
        if matched_topic is not None:
            urls = feature_dict[matched_topic]
        else:
            if configure_google_search():
                url = search_google_get_first_link(f"{dbms} documentation for {topic}")
                print(f"Automatically found the URL for {dbms} documentation for {feature} {topic}: {url}")
                url_yaml[dbms][feature][topic] = [url]
                urls = [url]
                updated = True
            elif feature_dict.get("overview"):
                urls = feature_dict["overview"]
                print(
                    f"No URL configured for {dbms} {feature} {topic}; using the feature overview.",
                    file=sys.stderr,
                )
            else:
                raise RuntimeError(
                    f"No documentation URL configured for {dbms} {feature} {topic}. "
                    "Add one to dbconfigs/url.yml."
                )

    # update the yaml file
    if updated and OVERWRITE:
        with open(dir, "w") as f:
            yaml.dump(url_yaml, f)
    elif updated:
        backup_dir = CONFIG_DIR + "/urls"
        os.makedirs(backup_dir, exist_ok=True)
        timestamp = time.strftime("%Y%m%d-%H%M")
        with open(f"{backup_dir}/url_{timestamp}.yml", "w") as f:
            yaml.dump(url_yaml, f)
    return urls


def append_llm_event(event: dict):
    event_path = os.environ.get("SHQVEL_PYTHON_LLM_EVENT_LOG")
    if not event_path:
        return
    event["timestamp"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    payload = json.dumps(event, ensure_ascii=False, separators=(",", ":")) + "\n"
    fd = os.open(event_path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    try:
        os.write(fd, payload.encode("utf-8"))
    finally:
        os.close(fd)


def invoke_with_usage(chain, values: dict, metadata: dict):
    started = time.monotonic()
    with get_openai_callback() as usage:
        result = chain.invoke(values)
    append_llm_event({
        **metadata,
        "kind": "documentation_summary",
        "elapsed_seconds": round(time.monotonic() - started, 6),
        "prompt_tokens": usage.prompt_tokens,
        "completion_tokens": usage.completion_tokens,
        "total_tokens": usage.total_tokens,
        "total_cost": usage.total_cost,
        "output_chars": len(result),
        "output": result,
    })
    return result


def learn_reference(docs, dbms: str, chain, metadata: dict):
    result = invoke_with_usage(chain, {"context": docs, "DBMS": dbms}, metadata)
    print(result)


def learn_reference_with_topic(docs, dbms: str, chain, topic: str, metadata: dict):
    result = invoke_with_usage(chain, {"context": docs, "DBMS": dbms, "topic": topic}, metadata)
    print(result)

if __name__ == "__main__":
    argparser = argparse.ArgumentParser()
    argparser.add_argument("--model", type=str, default="gpt-4o-mini")
    argparser.add_argument("--dbms", type=str, default="")
    argparser.add_argument("--feature", type=str, default="", choices=["datatype", "function", "command", "clause"])
    argparser.add_argument("--topic", type=str, default="")
    argparser.add_argument("--learn", action="store_true")
    argparser.add_argument("--debug", action="store_true")
    argparser.add_argument("--yaml", type=str, default="")
    argparser.add_argument("--llm-config", type=str, default=DEFAULT_LLM_CONFIG)
    args = argparser.parse_args()

    avail_dbms = list(DBMS_MAPPING.keys())
    dbms = DBMS_MAPPING[args.dbms.lower()]
    if dbms == "Unknown":
        raise ValueError(f"Please provide an existing DBMS name. Available options are: {avail_dbms}")

    if args.topic == "overview":
        prompt_tag = f"{args.feature}_general"
    else:
        prompt_tag = f"{args.feature}_specific"

    yaml_dir = resolve_yaml_path(args.yaml)

    # Get the URL and the docs
    urls = get_urls_from_yaml(dbms, args.feature, yaml_dir, args.topic)
    docs = get_docs_by_URLs(urls)
    if args.debug:
        print(docs[0].page_content)

    if not args.learn:
        print("Skip to learn the reference.")
        exit()

    # Creating the chain
    llm_config = load_llm_config(args.llm_config)
    api_key = llm_config.get("api_key")
    if not api_key:
        raise RuntimeError(f"api_key is not set in {args.llm_config}")
    base_url = llm_config.get("base_url") or DEFAULT_OPENAI_BASE_URL
    model = llm_config.get("summary_model") or args.model
    if model.casefold().startswith("glm-5.3"):
        glm_options = {
            "thinking": {"type": "enabled"},
            "reasoning_effort": "low",
        }
    elif model.casefold().startswith("glm-"):
        glm_options = {"thinking": {"type": "disabled"}}
    else:
        glm_options = None
    llm = ChatOpenAI(model=model, api_key=api_key, base_url=base_url,
                     timeout=120, max_retries=1, extra_body=glm_options)
    default_prompt = [("system", "Summarize the {DBMS} documentation: \\n\\n {context}.\\n\\n Give me example values and definitions.")]
    prompts = defaultdict(lambda: default_prompt, PROMPTS)
    prompt_messages = list(prompts[prompt_tag])
    # Some OpenAI-compatible models reject requests containing only a system
    # message. Keep the original instructions and add an explicit user turn.
    if not any(role in ("human", "user") for role, _ in prompt_messages):
        prompt_messages.append(("human", "Perform the requested documentation analysis."))
    prompt = ChatPromptTemplate.from_messages(prompt_messages)
    chain = create_stuff_documents_chain(llm, prompt)
    event_metadata = {"model": model, "dbms": dbms, "feature": args.feature,
                      "topic": args.topic, "urls": urls}

    # Learning the reference
    if prompt_tag.endswith("general"):
        learn_reference(docs, dbms, chain, event_metadata)
    elif prompt_tag.endswith("specific"):
        learn_reference_with_topic(docs, dbms, chain, args.topic, event_metadata)
