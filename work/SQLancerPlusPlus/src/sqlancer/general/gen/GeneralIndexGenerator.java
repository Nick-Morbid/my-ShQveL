package sqlancer.general.gen;

import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import sqlancer.Randomly;
import sqlancer.common.ast.newast.Node;
import sqlancer.common.query.ExpectedErrors;
import sqlancer.common.query.SQLQueryAdapter;
import sqlancer.common.schema.TableIndex;
import sqlancer.general.GeneralErrorHandler.GeneratorNode;
import sqlancer.general.GeneralLearningManager.SQLFeature;
import sqlancer.general.GeneralProvider.GeneralGlobalState;
import sqlancer.general.GeneralSchema.GeneralColumn;
import sqlancer.general.GeneralSchema.GeneralTable;
import sqlancer.general.GeneralToStringVisitor;
import sqlancer.general.ast.GeneralExpression;
import sqlancer.general.learner.GeneralFragments;
import sqlancer.general.learner.GeneralStringBuilder;

public final class GeneralIndexGenerator {

    private static GeneralIndexFragments fragments = new GeneralIndexFragments();
    private static final String CONFIG_NAME = "indexgenerator.txt";
    private static final String STATEMENT = "CREATE_INDEX";
    private static final SQLFeature FEATURE = SQLFeature.CLAUSE;

    private GeneralIndexGenerator() {
    }

    private static final class GeneralIndexFragments extends GeneralFragments {
        GeneralIndexFragments() {
            super();
        }

        @Override
        public synchronized String genLearnStatement(GeneralGlobalState globalState) {
            GeneralTableGenerator.getQuery(globalState);
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
            List<String> queries = new ArrayList<>();
            String sketchTable;
            if (currentSketch != null) {
                sketchTable = currentSketch;
            } else {
                sketchTable = genLearnStatement(globalState);
            }
            Matcher matcher = Pattern.compile("\\{(\\d+)\\}").matcher(sketchTable);
            StringBuffer result = new StringBuffer();

            while (matcher.find()) {
                String index = matcher.group(1);
                String replacement = "";
                if (index.equals(key)) {
                    replacement = choice;
                }
                matcher.appendReplacement(result, replacement);
            }
            matcher.appendTail(result);
            queries.add(result.toString());
            return queries;
        }

        @Override
        public String getConfigName() {
            return CONFIG_NAME;
        }

        @Override
        public String getStatementType() {
            return STATEMENT;
        }

        @Override
        public SQLFeature getFeature() {
            return FEATURE;
        }
    }

    public static SQLQueryAdapter getQuery(GeneralGlobalState globalState) {
        ExpectedErrors errors = new ExpectedErrors();
        // StringBuilder sb = new StringBuilder();
        GeneralStringBuilder<GeneralIndexFragments> sb = new GeneralStringBuilder<>(globalState, fragments);
        globalState.getHandler().addScore(GeneratorNode.CREATE_INDEX);
        sb.append("CREATE ");
        if (Randomly.getBoolean()) {
            errors.add("Cant create unique index, table contains duplicate data on indexed column(s)");
            globalState.getHandler().addScore(GeneratorNode.UNIQUE_INDEX);
            sb.append("UNIQUE ");
        }
        sb.append("INDEX ");
        GeneralTable table = globalState.getSchema().getRandomTable(t -> !t.isView());
        // String indexName = table.getName() + Randomly.fromOptions("i0", "i1", "i2",
        // "i3", "i4");
        // TODO: make it schema aware
        String tableName = table.getName();
        if (fragments.getLearn()) {
            tableName = "TEST_TABLE";
        } else {
            globalState.setTestObject("TEST_TABLE", tableName);
        }
        String indexName = tableName + (table.getIndexes().isEmpty() ? "i0" : "i" + table.getIndexes().size());
        sb.append(indexName);
        sb.append(" ON ");
        sb.append(tableName + " ", 0);
        sb.append("(");
        List<GeneralColumn> columns = table.getRandomNonEmptyColumnSubset();
        for (int i = 0; i < columns.size(); i++) {
            globalState.setTestObject("TEST_COLUMN" + i, columns.get(i).getName());
        }
        for (int i = 0; i < columns.size(); i++) {
            if (i != 0) {
                sb.append(", ");
            }
            String colName = columns.get(i).getName();
            if (fragments.getLearn()) {
                colName = "TEST_COLUMN" + i;
            }
            sb.append(colName);
            sb.append(" ", 1);
            // if (Randomly.getBooleanWithRatherLowProbability()) {
            // sb.append(Randomly.fromOptions("ASC", "DESC"));
            // }
        }
        sb.append(") ", 2);
        if (Randomly.getBooleanWithRatherLowProbability() && !fragments.getLearn()) {
            sb.append(" WHERE ");
            Node<GeneralExpression> expr = new GeneralExpressionGenerator(globalState).setColumns(table.getColumns())
                    .generateExpression();
            sb.append(GeneralToStringVisitor.asString(expr));
        }
        errors.add("already exists!");
        errors.add("Syntax");
        errors.addRegex(Pattern.compile(".*", Pattern.DOTALL));
        // Update the indexes of the table
        List<TableIndex> indexes = new ArrayList<>(table.getIndexes());
        TableIndex index = TableIndex.create(indexName);
        // append the index
        indexes.add(index);

        SQLQueryAdapter q = new SQLQueryAdapter(sb.toString(), errors, true, false);
        globalState.setUpdateTable(new GeneralTable(table.getName(), table.getColumns(), indexes, false));
        return q;
    }

    public static GeneralFragments getFragments() {
        return fragments;
    }

}
