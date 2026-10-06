package sqlancer.general;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.json.JSONArray;
import org.json.JSONObject;

import sqlancer.general.GeneralProvider.GeneralGlobalState;
import sqlancer.general.GeneralSchema.GeneralCompositeDataType;
import sqlancer.general.ast.GeneralBinaryOperator;
import sqlancer.general.ast.GeneralFunction;
import sqlancer.general.gen.GeneralIndexGenerator;
import sqlancer.general.gen.GeneralStatementGenerator;
import sqlancer.general.gen.GeneralTableGenerator;
import sqlancer.general.learner.GeneralFragments;
import sqlancer.general.learner.GeneralFragments.GeneralFragmentChoice;

/** Persists the in-memory result of learning without changing learning or generation semantics. */
public final class GeneralLearnedState {
    private static final int FORMAT_VERSION = 1;
    private static String loadedCheckpointKey;

    private GeneralLearnedState() {
    }

    public static synchronized void save(GeneralGlobalState globalState, String fileName) {
        Path target = Path.of(fileName).toAbsolutePath().normalize();
        JSONObject root = new JSONObject();
        root.put("format_version", FORMAT_VERSION);
        root.put("dbms", globalState.getDbmsSpecificOptions().getDatabaseEngineFactory().toString());
        root.put("datatypes", fragmentsToJson(GeneralSchema.getFragments()));
        root.put("function_fragments", fragmentsToJson(GeneralFunction.getFragments()));
        root.put("operator_fragments", fragmentsToJson(GeneralBinaryOperator.getFragments()));
        root.put("statement_fragments", fragmentsToJson(GeneralStatementGenerator.getFragments()));
        root.put("table_fragments", fragmentsToJson(GeneralTableGenerator.getFragments()));
        root.put("index_fragments", fragmentsToJson(GeneralIndexGenerator.getFragments()));
        root.put("functions", new JSONObject(GeneralFunction.getFunctions()));

        JSONObject operators = new JSONObject();
        GeneralBinaryOperator.getOperators().forEach((name, type) -> operators.put(name, type.toString()));
        root.put("operators", operators);
        root.put("type_to_function", stringListsToJson(GeneralSchema.getTypeToFunctionSnapshot()));
        root.put("type_availability", new JSONObject(GeneralSchema.getTypeAvailabilitySnapshot()));

        try {
            Path parent = target.getParent();
            if (parent != null) {
                Files.createDirectories(parent);
            }
            Path temporary = Files.createTempFile(parent, target.getFileName().toString(), ".tmp");
            Files.writeString(temporary, root.toString(2) + System.lineSeparator(), StandardCharsets.UTF_8);
            try {
                Files.move(temporary, target, StandardCopyOption.REPLACE_EXISTING,
                        StandardCopyOption.ATOMIC_MOVE);
            } catch (IOException unsupportedAtomicMove) {
                Files.move(temporary, target, StandardCopyOption.REPLACE_EXISTING);
            }
            System.out.println("Saved learned fragment checkpoint to " + target);
        } catch (IOException e) {
            throw new AssertionError("Could not save learned fragment checkpoint " + target, e);
        }
    }

    public static synchronized void loadOnce(GeneralGlobalState globalState, String fileName,
            boolean learningDisabled) {
        Path source = Path.of(fileName).toAbsolutePath().normalize();
        String checkpointKey = source + ":" + learningDisabled;
        if (checkpointKey.equals(loadedCheckpointKey)) {
            return;
        }
        load(globalState, source, learningDisabled);
        loadedCheckpointKey = checkpointKey;
    }

    private static void load(GeneralGlobalState globalState, Path source, boolean learningDisabled) {
        try {
            JSONObject root = new JSONObject(Files.readString(source, StandardCharsets.UTF_8));
            int version = root.getInt("format_version");
            if (version != FORMAT_VERSION) {
                throw new IllegalArgumentException("Unsupported learned-fragment checkpoint version: " + version);
            }
            String expectedDbms = globalState.getDbmsSpecificOptions().getDatabaseEngineFactory().toString();
            String savedDbms = root.getString("dbms");
            if (!expectedDbms.equals(savedDbms)) {
                throw new IllegalArgumentException(
                        "Checkpoint DBMS is " + savedDbms + ", but the selected DBMS is " + expectedDbms);
            }

            GeneralSchema.resetLearnedTypes();
            loadFragments(GeneralSchema.getFragments(), root.getJSONObject("datatypes"));
            GeneralSchema.GeneralDataType.calcWeight();

            GeneralFunction.getFragments().clearFragments();
            loadFragments(GeneralFunction.getFragments(), root.getJSONObject("function_fragments"));
            GeneralFunction.replaceFunctions(jsonToIntegerMap(root.getJSONObject("functions")));

            GeneralBinaryOperator.getFragments().clearFragments();
            loadFragments(GeneralBinaryOperator.getFragments(), root.getJSONObject("operator_fragments"));
            GeneralBinaryOperator.replaceOperators(jsonToOperators(root.getJSONObject("operators")));

            replaceFragments(GeneralStatementGenerator.getFragments(), root.getJSONObject("statement_fragments"));
            replaceFragments(GeneralTableGenerator.getFragments(), root.getJSONObject("table_fragments"));
            replaceFragments(GeneralIndexGenerator.getFragments(), root.getJSONObject("index_fragments"));

            GeneralSchema.replaceTypeToFunction(jsonToStringLists(root.getJSONObject("type_to_function")));
            GeneralSchema.replaceTypeAvailability(jsonToBooleanMap(root.getJSONObject("type_availability")));
            String mode = learningDisabled ? "LLM learning is disabled for this run"
                    : "LLM learning will resume from this state";
            System.out.println("Loaded learned fragment checkpoint from " + source + "; " + mode);
        } catch (IOException e) {
            throw new AssertionError("Could not load learned fragment checkpoint " + source, e);
        }
    }

    private static JSONObject fragmentsToJson(GeneralFragments fragments) {
        JSONObject result = new JSONObject();
        fragments.getFragments().forEach((key, choices) -> {
            JSONArray values = new JSONArray();
            for (GeneralFragmentChoice choice : choices) {
                values.put(choice.getFragmentName());
            }
            result.put(key, values);
        });
        return result;
    }

    private static JSONObject stringListsToJson(Map<String, List<String>> values) {
        JSONObject result = new JSONObject();
        values.forEach((key, list) -> result.put(key, new JSONArray(list)));
        return result;
    }

    private static void loadFragments(GeneralFragments fragments, JSONObject source) {
        for (String key : source.keySet()) {
            JSONArray values = source.getJSONArray(key);
            for (int i = 0; i < values.length(); i++) {
                fragments.loadCheckpointFragment(key, values.getString(i));
            }
        }
    }

    private static void replaceFragments(GeneralFragments fragments, JSONObject source) {
        fragments.clearFragments();
        loadFragments(fragments, source);
    }

    private static Map<String, Integer> jsonToIntegerMap(JSONObject source) {
        Map<String, Integer> result = new LinkedHashMap<>();
        source.keySet().forEach(key -> result.put(key, source.getInt(key)));
        return result;
    }

    private static Map<String, Boolean> jsonToBooleanMap(JSONObject source) {
        Map<String, Boolean> result = new HashMap<>();
        source.keySet().forEach(key -> result.put(key, source.getBoolean(key)));
        return result;
    }

    private static Map<String, List<String>> jsonToStringLists(JSONObject source) {
        Map<String, List<String>> result = new HashMap<>();
        for (String key : source.keySet()) {
            JSONArray values = source.getJSONArray(key);
            List<String> list = new ArrayList<>();
            for (int i = 0; i < values.length(); i++) {
                list.add(values.getString(i));
            }
            result.put(key, list);
        }
        return result;
    }

    private static Map<String, GeneralCompositeDataType> jsonToOperators(JSONObject source) {
        Map<String, GeneralCompositeDataType> result = new LinkedHashMap<>();
        for (String key : source.keySet()) {
            GeneralCompositeDataType type = GeneralCompositeDataType.getByName(source.getString(key));
            if (type == null) {
                throw new IllegalArgumentException("Unknown operator datatype in checkpoint: " + source.getString(key));
            }
            result.put(key, type);
        }
        return result;
    }
}
