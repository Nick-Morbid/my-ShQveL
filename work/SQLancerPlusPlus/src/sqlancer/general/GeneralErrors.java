package sqlancer.general;

import java.util.regex.Pattern;

import sqlancer.common.query.ExpectedErrors;

public final class GeneralErrors {

    private GeneralErrors() {
    }

    public static void addExpressionErrors(ExpectedErrors errors) {
        errors.addRegex(Pattern.compile(".*", Pattern.DOTALL));
    }

    public static void addInsertErrors(ExpectedErrors errors) {
        errors.addRegex(Pattern.compile(".*", Pattern.DOTALL));
    }

}
