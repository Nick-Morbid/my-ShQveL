package sqlancer.general.gen;

import java.util.ArrayList;
import java.util.List;

import sqlancer.Randomly;
import sqlancer.common.query.ExpectedErrors;
import sqlancer.common.query.SQLQueryAdapter;
import sqlancer.common.schema.TableIndex;
import sqlancer.general.GeneralErrors;
import sqlancer.general.GeneralProvider.GeneralGlobalState;
import sqlancer.general.GeneralSchema.GeneralColumn;
import sqlancer.general.GeneralSchema.GeneralCompositeDataType;
import sqlancer.general.GeneralSchema.GeneralTable;
import sqlancer.general.GeneralToStringVisitor;

public final class GeneralAlterTableGenerator {

    private GeneralAlterTableGenerator() {
    }

    enum Action {
        ADD_COLUMN, ALTER_COLUMN, DROP_COLUMN
    }

    public static SQLQueryAdapter getQuery(GeneralGlobalState globalState) {
        ExpectedErrors errors = new ExpectedErrors();
        GeneralErrors.addExpressionErrors(errors);
        boolean couldAffectSchema = true;
        StringBuilder sb = new StringBuilder("ALTER TABLE ");
        GeneralTable table = globalState.getSchema().getRandomTable(t -> !t.isView());
        List<GeneralColumn> columnsToChange = new ArrayList<>(table.getColumns());
        List<TableIndex> indexes = new ArrayList<>(table.getIndexes());
        GeneralExpressionGenerator gen = new GeneralExpressionGenerator(globalState).setColumns(table.getColumns());
        sb.append(table.getName());
        sb.append(" ");
        Action action = Randomly.fromOptions(Action.values());
        switch (action) {
        case ADD_COLUMN:
            sb.append("ADD COLUMN ");
            String columnName = table.getFreeColumnName();
            sb.append(columnName);
            sb.append(" ");
            GeneralCompositeDataType columnType = GeneralCompositeDataType.getRandomWithoutNull();
            sb.append(columnType.toString());
            columnsToChange.add(new GeneralColumn(columnName, columnType, false, false));
            break;
        case ALTER_COLUMN:
            sb.append("ALTER COLUMN ");
            String columnNameChange = table.getRandomColumn().getName();
            sb.append(columnNameChange);
            sb.append(" SET DATA TYPE ");
            sb.append(GeneralCompositeDataType.getRandomWithoutNull().toString());
            if (Randomly.getBoolean()) {
                sb.append(" USING ");
                sb.append(GeneralToStringVisitor.asString(gen.generateExpression()));
            }
            // no need to change the schema
            couldAffectSchema = false;
            break;
        case DROP_COLUMN:
            sb.append("DROP COLUMN ");
            String columnNameDrop = table.getRandomColumn().getName();
            sb.append(columnNameDrop);
            columnsToChange.removeIf(c -> c.getName().contentEquals(columnNameDrop));
            break;
        default:
            throw new AssertionError(action);
        }
        GeneralTable newTable = new GeneralTable(table.getName(), columnsToChange, indexes, false);
        newTable.getColumns().forEach(c -> c.setTable(newTable));
        globalState.setUpdateTable(newTable);
        return new SQLQueryAdapter(sb.toString(), errors, couldAffectSchema);
    }

}
