package sqlancer.general.learner;

import java.util.HashMap;
import java.util.Map;

import sqlancer.FeatureLearner;
import sqlancer.general.ast.GeneralFunction;

public class GeneralFunctionLearner implements FeatureLearner {
    private static Map<String, Integer> functions = new HashMap<>();

    @Override
    public void learn() {
    }

    @Override
    public void update() {
        GeneralFunction.mergeFunctions(functions);
    }

    public static Map<String, Integer> getFunctions() {
        return functions;
    }
}
