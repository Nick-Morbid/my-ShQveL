package sqlancer.general.gen;

import java.util.List;

import sqlancer.Randomly;
import sqlancer.common.query.ExpectedErrors;
import sqlancer.common.query.SQLQueryAdapter;
import sqlancer.general.GeneralErrors;
import sqlancer.general.GeneralLearningManager.SQLFeature;
import sqlancer.general.GeneralProvider.GeneralGlobalState;
import sqlancer.general.learner.GeneralFragments;
import sqlancer.general.learner.GeneralStringBuilder;

public final class GeneralStatementGenerator {

    private static GeneralStatementFragments fragments = new GeneralStatementFragments();
    private static final String CONFIG_NAME = "dmlgenerator.txt";
    private static final String STATEMENT = "DML";
    private static final SQLFeature FEATURE = SQLFeature.COMMAND;

    private GeneralStatementGenerator() {
    }

    private static final class GeneralStatementFragments extends GeneralFragments {
        GeneralStatementFragments() {
            super();
        }

        @Override
        public synchronized String genLearnStatement(GeneralGlobalState globalState) {
            globalState.updateSchema();
            setLearn(true);
            String stmt = getQuery(globalState).getQueryString();
            setLearn(false);
            if (globalState.getOptions().debugLogs()) {
                System.out.println(stmt);
            }
            return stmt;
        }

        @Override
        public List<String> genValStatements(GeneralGlobalState globalState, String key, String choice,
                String databaseName) {
            return List.of();
        }

        @Override
        public String getConfigName() {
            return CONFIG_NAME;
        }

        @Override
        public String getStatementType() {
            return Randomly.fromList(List.of(STATEMENT, "CONFIGURATION", "SETTING", "ANALYZE"));
        }

        @Override
        public SQLFeature getFeature() {
            return FEATURE;
        }

        @Override
        protected String getExamples() {
            StringBuilder sb = new StringBuilder();
            sb.append("0,ANALYZE\n");
            sb.append("0,REINDEX\n");
            sb.append("1,VACUUM TEST_TABLE\n");
            sb.append("2,SET some_settings\n");
            // sb.append("Note: DO NOT include SQL commands that may create files in
            // OS.\n");
            return sb.toString();
        }

        @Override
        protected void validateFragment(String fmtString, List<GeneralFragmentVariable> vars) {
            if (fmtString.contains("CREATE") || fmtString.contains("DROP") || fmtString.contains("ALTER")) {
                throw new IllegalArgumentException("Should not contain DDL commands. Invalid command: " + fmtString);
            }
            super.validateFragment(fmtString, vars);
        }

        @Override
        protected String preprocessingLine(String line) {
            String newLine = line.replace("TEST_TABLE", "<RANDOM_TABLE>");
            newLine = newLine.replace("TEST_COLUMN", "<RANDOM_COLUMN>");
            return newLine;
        }

    }

    public static SQLQueryAdapter getQuery(GeneralGlobalState globalState) {
        ExpectedErrors errors = new ExpectedErrors();
        GeneralErrors.addExpressionErrors(errors);
        GeneralStringBuilder<GeneralStatementFragments> sb = new GeneralStringBuilder<>(globalState, fragments, false);

        if (fragments.getLearn()) {
            sb.append("CREATE TABLE TEST_TABLE (TEST_COLUMN INT);\n");
            sb.append("INSERT INTO TEST_TABLE VALUES (1);\n");
            sb.append("", 0);
            sb.append("; -- SQL command with concrete string representation\n");
            sb.append("", 1);
            sb.append("; -- SQL command operating on one table\n");
            sb.append("", 2);
            sb.append("; -- Cofiguration SQL statements for query execution and optimization\n");
            sb.append("SELECT * FROM TEST_TABLE;\n");
        } else {
            int option = globalState.getRandomly().getInteger(0, 2);
            sb.append("", option);
            sb.append(";");
        }
        String stmt = sb.toString();
        // if stmt is empty, return null
        if (stmt.equals(";")) {
            stmt = "ANALYZE;";
        }
        return new SQLQueryAdapter(stmt, errors, false, false);
    }

    public static GeneralFragments getFragments() {
        return fragments;
    }

}
