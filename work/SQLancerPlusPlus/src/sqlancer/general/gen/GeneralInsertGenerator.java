package sqlancer.general.gen;

import java.util.List;
import java.util.stream.Collectors;

import sqlancer.Randomly;
import sqlancer.common.gen.AbstractInsertGenerator;
import sqlancer.common.query.ExpectedErrors;
import sqlancer.common.query.SQLQueryAdapter;
import sqlancer.general.GeneralErrorHandler.GeneratorNode;
import sqlancer.general.GeneralErrors;
import sqlancer.general.GeneralProvider.GeneralGlobalState;
import sqlancer.general.GeneralSchema.GeneralColumn;
import sqlancer.general.GeneralSchema.GeneralCompositeDataType;
import sqlancer.general.GeneralSchema.GeneralTable;
import sqlancer.general.GeneralToStringVisitor;

public class GeneralInsertGenerator extends AbstractInsertGenerator<GeneralColumn> {

    private final GeneralGlobalState globalState;
    private final ExpectedErrors errors = new ExpectedErrors();

    public GeneralInsertGenerator(GeneralGlobalState globalState) {
        this.globalState = globalState;
    }

    public static SQLQueryAdapter getQuery(GeneralGlobalState globalState) {
        return new GeneralInsertGenerator(globalState).generate();
    }

    private SQLQueryAdapter generate() {
        globalState.setCreatingDatabase(true);
        sb.append("INSERT INTO ");
        globalState.getHandler().addScore(GeneratorNode.INSERT);
        GeneralTable table = globalState.getSchema().getRandomTable(t -> !t.isView());
        List<GeneralColumn> columns = table.getRandomNonEmptyColumnSubset();
        sb.append(table.getName());
        sb.append("(");
        sb.append(columns.stream().map(c -> c.getName()).collect(Collectors.joining(", ")));
        sb.append(")");
        sb.append(" VALUES ");
        insertColumns(columns);
        GeneralErrors.addInsertErrors(errors);
        globalState.setCreatingDatabase(false);
        return new SQLQueryAdapter(sb.toString(), errors, false, false);
    }

    @Override
    protected void insertColumns(List<GeneralColumn> columns) {
        for (int nrRows = 0; nrRows < Randomly.smallNumber() + 1; nrRows++) {
            if (nrRows != 0) {
                sb.append(", ");
            }
            sb.append("(");
            for (int nrColumn = 0; nrColumn < columns.size(); nrColumn++) {
                if (nrColumn != 0) {
                    sb.append(", ");
                }
                insertValue(columns.get(nrColumn));
            }
            sb.append(")");
        }
    }

    @Override
    protected void insertValue(GeneralColumn columnGeneral) {
        if (globalState.getHandler().getOption(GeneratorNode.UNTYPE_EXPR)
                || Randomly.getBooleanWithSmallProbability()) {
            sb.append(GeneralToStringVisitor.asString(new GeneralExpressionGenerator(globalState).generateConstant()));
        } else {
            GeneralCompositeDataType columnType = columnGeneral.getType();
            sb.append(GeneralToStringVisitor
                    .asString(new GeneralTypedExpressionGenerator(globalState).generateConstant(columnType)));
        }
    }

}
