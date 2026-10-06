package sqlancer.general.learner;

import java.io.BufferedReader;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.Reader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.time.Instant;
import java.util.Arrays;
import java.util.List;
import java.util.Properties;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;

import org.json.JSONArray;
import org.json.JSONObject;

import okhttp3.MediaType;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.RequestBody;
import okhttp3.Response;
import sqlancer.FeatureLearner;
import sqlancer.general.GeneralLearningManager.SQLFeature;
import sqlancer.general.GeneralProvider.GeneralGlobalState;

public class GeneralTemplateLearner implements FeatureLearner {

    private static final String LLM_CONFIG_PATH = "dbconfigs/llm.properties";
    private static final String DEFAULT_OPENAI_BASE_URL = "https://api.zhizengzeng.com/v1";
    private static final String DEFAULT_MODEL = "gpt-4o";
    private static final Properties LLM_CONFIG = loadLlmConfig();
    private final String apiKey = getConfigValue("api_key", "");

    private String rawFragments = "";
    private final GeneralGlobalState globalState;
    private final SQLFeature feature;
    private final String template;
    private final String variables;
    private final String systemPrompt;
    private final String topic;

    // optional things
    private String examples = "";

    @Override
    public void learn() {
        String response = "";
        String reference = "";

        // get the documentation reference
        if (globalState.getDbmsSpecificOptions().useRetrievalAugmentation) {
            reference = retrieveSummarization();
        }
        response = getDialectFromReference(reference);

        rawFragments = process(response);
    }

    public GeneralTemplateLearner(GeneralGlobalState globalState, SQLFeature feature, String template, String variables,
            String systemPrompt, String topic) {
        this.globalState = globalState;
        this.feature = feature;
        this.template = template;
        this.variables = variables;
        this.systemPrompt = systemPrompt;
        this.topic = topic;
    }

    @Override
    public void update() {
    }

    public String process(String response) {
        StringBuilder processed = new StringBuilder();
        for (String rawRow : response.split("\\R")) {
            String row = rawRow.trim();
            if (row.isEmpty() || row.startsWith("```") || !row.contains(";")) {
                continue;
            }
            processed.append(row).append('\n');
        }
        System.out.println(processed.toString());
        return processed.toString();
    }

    // private String retrieveURL() {
    // String doc_url = "";
    // String model = "gpt-4o-mini";
    // String system = "This GPT acts as a web crawler and assistant to help users
    // find the correct URL or specific documentation related to Database Management
    // Systems (DBMS). It should efficiently search the web and provide accurate,
    // relevant URLs based on the user's query. The assistant will maintain a
    // professional and formal tone, ensuring that users receive the most pertinent
    // information. If the initial query is too broad or unclear, the assistant will
    // ask for further clarification to narrow down the search. The responses should
    // be concise, returning only the URL without any explanation.";
    // String user = String.format("URL for %s %s",
    // globalState.getDbmsNameForLearning(), stmt_type);
    // try {
    // doc_url = getChatGPTResponse(model, system, user);
    // } catch (IOException e) {
    // e.printStackTrace();
    // }
    // try {
    // doc_url = parseAndGetGPTContent(doc_url);
    // } catch (Exception e) {
    // e.printStackTrace();
    // }
    // return doc_url;
    // }

    private String retrieveSummarization() {
        try {
            // assume that the python environment is set up
            List<String> command = new java.util.ArrayList<>(Arrays.asList("python3", "src/chat.py", "--dbms",
                    globalState.getDbmsNameForLearning(), "--feature", feature.toString(), "--topic", topic, "--learn"));
            String documentationYaml = globalState.getDbmsSpecificOptions().documentationYaml;
            if (documentationYaml != null && !documentationYaml.isBlank()) {
                command.add("--yaml");
                command.add(documentationYaml);
            }
            System.out.println("Execute " + command);
            ProcessBuilder pb = new ProcessBuilder(command);
            pb.redirectErrorStream(true);
            Process p = pb.start();
            BufferedReader reader = new BufferedReader(new java.io.InputStreamReader(p.getInputStream()));
            ExecutorService streamExecutor = Executors.newSingleThreadExecutor();
            // Bound documentation output. A malformed or unexpectedly verbose
            // summarizer response must not accumulate without limit in the Java heap.
            Future<String> output = streamExecutor.submit(() -> {
                StringBuilder bounded = new StringBuilder();
                String line;
                final int maxChars = 4 * 1024 * 1024;
                while ((line = reader.readLine()) != null) {
                    if (bounded.length() < maxChars) {
                        int remaining = maxChars - bounded.length();
                        bounded.append(line, 0, Math.min(line.length(), remaining)).append('\n');
                    }
                }
                if (bounded.length() >= maxChars) {
                    bounded.append("\n[documentation output truncated]\n");
                }
                return bounded.toString();
            });
            boolean exited = p.waitFor(180, TimeUnit.SECONDS);
            if (!exited) {
                p.destroyForcibly();
                output.cancel(true);
                streamExecutor.shutdownNow();
                System.out.println("Documentation learner timed out after 180 seconds: " + topic);
                return null;
            }
            String sb = output.get(5, TimeUnit.SECONDS);
            streamExecutor.shutdownNow();
            int exitCode = p.exitValue();
            if (exitCode != 0) {
                System.out.println("Error: " + exitCode);
                System.err.println(sb.toString());
                return null;
            } else {
                return sb.toString();
            }

        } catch (Exception e) {
            // TODO: handle exception
            e.printStackTrace();
            return null;
        }
    }

    private String getDialectFromReference(String reference) {
        String response = "";
        String model = getConfigValue("fragment_model", DEFAULT_MODEL);
        String system = systemPrompt;
        StringBuilder sb = new StringBuilder();
        sb.append("DBMS: ");
        sb.append(globalState.getDbmsNameForLearning());
        sb.append("\n\n");
        sb.append("Sketch:\n");
        sb.append(template);
        if (variables != "") {
            sb.append("\n");
            sb.append("Available variables and their descriptions:\n");
            sb.append(variables);
        }
        if (examples != "") {
            sb.append("\n");
            sb.append("Examples:\n");
            sb.append(examples);
        }
        sb.append("\n");
        sb.append("Reference: ");
        sb.append(reference);
        // String user = String.format("DBMS: %s\n" + //
        // "Template: %s\n", globalState.getDbmsNameForLearning(), template);
        // if (variables != "") {
        // user += "Available variables and their descriptions:\n" + variables;
        // }
        // if (examples != "") {
        // user += "Examples:\n" + examples;
        // }
        // user += "Reference: " + reference;
        // user += "Note: Please do not call functions in DBMS that would bring
        // randomness to the query. Function calls should be deterministic.";
        String user = sb.toString();
        if (globalState.getOptions().debugLogs()) {
            System.out.println("User prompt:");
            System.out.println(user);
        }
        try {
            response = getChatGPTResponse(model, system, user);
        } catch (IOException e) {
            e.printStackTrace();
        }
        try {
            response = parseAndGetGPTContent(response);
        } catch (Exception e) {
            e.printStackTrace();
        }
        return response;
    }

    private String getChatGPTResponse(String model, String system, String user) throws IOException {
        if (apiKey == null || apiKey.isBlank()) {
            System.err.println("api_key is not set in " + LLM_CONFIG_PATH);
            return "";
        }
        OkHttpClient client = new OkHttpClient.Builder().connectTimeout(60, TimeUnit.SECONDS)
                .readTimeout(60, TimeUnit.SECONDS).build();

        JSONObject json = new JSONObject();

        json.put("model", model);

        if (model.toLowerCase().startsWith("glm-")) {
            JSONObject thinking = new JSONObject();
            boolean isGlm53 = model.toLowerCase().startsWith("glm-5.3");
            thinking.put("type", isGlm53 ? "enabled" : "disabled");
            json.put("thinking", thinking);
            if (isGlm53) {
                json.put("reasoning_effort", "low");
            }
        }

        // manage the messages
        JSONArray messages = new JSONArray();

        JSONObject message1 = new JSONObject();
        message1.put("role", "system");
        message1.put("content", system);

        JSONObject message2 = new JSONObject();
        message2.put("role", "user");
        message2.put("content", user);
        messages.put(message1);
        messages.put(message2);

        json.put("messages", messages);

        RequestBody body = RequestBody.create(json.toString(), MediaType.parse("application/json; charset=utf-8"));

        Request request = new Request.Builder().url(getChatCompletionsUrl()).post(body)
                .addHeader("Content-Type", "application/json").addHeader("Authorization", "Bearer " + apiKey).build();
        long startedNanos = System.nanoTime();
        try (Response response = client.newCall(request).execute()) {
            String responseBody = response.body() == null ? "" : readBounded(response.body().charStream(), 4 * 1024 * 1024);
            if (!response.isSuccessful()) {
                throw new IOException(String.format("OpenAI-compatible API request failed (%d %s): %s",
                        response.code(), response.message(), responseBody));
            }
            appendLlmEvent(model, system, user, responseBody, System.nanoTime() - startedNanos);
            return responseBody;
        }
    }

    private static String readBounded(Reader reader, int maxChars) throws IOException {
        StringBuilder result = new StringBuilder();
        char[] buffer = new char[8192];
        int remaining = maxChars;
        int read;
        while (remaining > 0 && (read = reader.read(buffer, 0, Math.min(buffer.length, remaining))) != -1) {
            result.append(buffer, 0, read);
            remaining -= read;
        }
        if (remaining == 0) {
            result.append("\n[LLM response truncated]\n");
        }
        return result.toString();
    }

    private void appendLlmEvent(String model, String system, String user, String responseBody, long elapsedNanos) {
        String eventFile = System.getenv("SHQVEL_JAVA_LLM_EVENT_LOG");
        if (eventFile == null || eventFile.isBlank()) {
            return;
        }
        try {
            JSONObject responseJson = new JSONObject(responseBody);
            JSONObject event = new JSONObject();
            event.put("timestamp", Instant.now().toString());
            event.put("kind", "fragment_synthesis");
            event.put("model", model);
            event.put("dbms", globalState.getDbmsNameForLearning());
            event.put("feature", feature.toString());
            event.put("topic", topic);
            event.put("elapsed_seconds", elapsedNanos / 1_000_000_000.0);
            event.put("system_prompt_chars", system.length());
            event.put("user_prompt_chars", user.length());
            event.put("usage", responseJson.optJSONObject("usage"));
            event.put("response", responseJson);
            synchronized (GeneralTemplateLearner.class) {
                Path path = Path.of(eventFile);
                if (path.getParent() != null) {
                    Files.createDirectories(path.getParent());
                }
                Files.writeString(path, event.toString() + System.lineSeparator(), StandardCharsets.UTF_8,
                        StandardOpenOption.CREATE, StandardOpenOption.APPEND);
            }
        } catch (Exception e) {
            System.err.println("Unable to append LLM usage event: " + e.getMessage());
        }
    }

    static String getChatCompletionsUrl() {
        String baseUrl = getConfigValue("base_url", DEFAULT_OPENAI_BASE_URL);
        baseUrl = baseUrl.replaceAll("/+$", "");
        if (baseUrl.endsWith("/chat/completions")) {
            return baseUrl;
        }
        return baseUrl + "/chat/completions";
    }

    private static Properties loadLlmConfig() {
        Properties properties = new Properties();
        try (FileInputStream input = new FileInputStream(LLM_CONFIG_PATH)) {
            properties.load(input);
        } catch (IOException e) {
            System.err.println("Cannot read " + LLM_CONFIG_PATH + ": " + e.getMessage());
        }
        return properties;
    }

    private static String getConfigValue(String name, String defaultValue) {
        String value = LLM_CONFIG.getProperty(name);
        return value == null || value.isBlank() ? defaultValue : value.trim();
    }

    private String parseAndGetGPTContent(String response) {
        JSONObject json = new JSONObject(response);
        JSONArray choices = json.getJSONArray("choices");
        JSONObject choice = choices.getJSONObject(0);
        JSONObject message = choice.getJSONObject("message");
        return message.getString("content");
    }

    public String getFragments() {
        return rawFragments;
    }

    public void setExamples(String examples) {
        this.examples = examples;
    }

    public String getExamples() {
        return examples;
    }
}
