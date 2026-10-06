package sqlancer.general.gen;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;

import sqlancer.Randomly;
import sqlancer.common.query.ExpectedErrors;
import sqlancer.common.query.SQLQueryAdapter;
import sqlancer.general.GeneralErrorHandler.GeneratorNode;
import sqlancer.general.GeneralErrors;
import sqlancer.general.GeneralProvider.GeneralGlobalState;
import sqlancer.general.GeneralSchema.GeneralColumn;
import sqlancer.general.GeneralSchema.GeneralCompositeDataType;
import sqlancer.general.GeneralSchema.GeneralTable;
import sqlancer.general.GeneralToStringVisitor;
import sqlancer.general.ast.GeneralSelect;

public final class GeneralViewGenerator {

    private GeneralViewGenerator() {
    }

    public static SQLQueryAdapter generate(GeneralGlobalState globalState) {
        int nrColumns = Randomly.smallNumber() + 1;
        StringBuilder sb = new StringBuilder("CREATE ");
        sb.append("VIEW ");
        String viewName = globalState.getSchema().getFreeViewName();
        viewName = globalState.getHandler().getOption(GeneratorNode.CREATE_DATABASE) ? viewName
                : globalState.getDatabaseName() + globalState.getDbmsSpecificOptions().dbTableDelim + viewName;
        sb.append(viewName);
        List<GeneralColumn> columns = new ArrayList<>();

        sb.append("(");
        for (int i = 0; i < nrColumns; i++) {
            if (i != 0) {
                sb.append(", ");
            }
            sb.append("c");
            sb.append(i);
            columns.add(new GeneralColumn("c" + i, GeneralCompositeDataType.getRandomWithoutNull(), false, false));
        }
        sb.append(") AS ");
        HashMap<String, Integer> tmpCompositeScore = new HashMap<>(
                globalState.getHandler().getGeneratorInfo().getCompositeGeneratorScore());
        GeneralSelect select = GeneralRandomQuerySynthesizer.generateSelect(globalState, columns);
        sb.append(GeneralToStringVisitor.asString(select));
        GeneralTable newTable = new GeneralTable(viewName, columns, true);
        newTable.getColumns().forEach(c -> c.setTable(newTable));
        globalState.setUpdateTable(newTable);
        ExpectedErrors errors = new ExpectedErrors();
        GeneralErrors.addExpressionErrors(errors);
        globalState.getHandler().loadCompositeScore(tmpCompositeScore);
        return new SQLQueryAdapter(sb.toString(), errors, true);
    }

}
