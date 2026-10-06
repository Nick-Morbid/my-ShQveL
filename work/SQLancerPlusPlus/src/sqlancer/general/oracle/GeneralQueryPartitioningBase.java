package sqlancer.general.oracle;

import java.sql.SQLException;
import java.util.ArrayList;
import java.util.List;
import java.util.stream.Collectors;

import sqlancer.Randomly;
import sqlancer.common.ast.newast.ColumnReferenceNode;
import sqlancer.common.ast.newast.Node;
import sqlancer.common.ast.newast.TableReferenceNode;
import sqlancer.common.gen.ExpressionGenerator;
import sqlancer.common.oracle.TernaryLogicPartitioningOracleBase;
import sqlancer.common.oracle.TestOracle;
import sqlancer.general.GeneralErrorHandler.GeneratorNode;
import sqlancer.general.GeneralErrors;
import sqlancer.general.GeneralProvider.GeneralGlobalState;
import sqlancer.general.GeneralSchema;
import sqlancer.general.GeneralSchema.GeneralColumn;
import sqlancer.general.GeneralSchema.GeneralTable;
import sqlancer.general.GeneralSchema.GeneralTables;
import sqlancer.general.ast.GeneralExpression;
import sqlancer.general.ast.GeneralJoin;
import sqlancer.general.ast.GeneralSelect;
import sqlancer.general.gen.GeneralRandomQuerySynthesizer;

public class GeneralQueryPartitioningBase
        extends TernaryLogicPartitioningOracleBase<Node<GeneralExpression>, GeneralGlobalState>
        implements TestOracle<GeneralGlobalState> {

    GeneralSchema s;
    GeneralTables targetTables;
    ExpressionGenerator<Node<GeneralExpression>> gen;
    GeneralSelect select;

    public GeneralQueryPartitioningBase(GeneralGlobalState state) {
        super(state);
        GeneralErrors.addExpressionErrors(errors);
    }

    @Override
    public void check() throws SQLException {
        s = state.getSchema();
        targetTables = s.getRandomTableNonEmptyTables();
        gen = GeneralRandomQuerySynthesizer.getExpressionGenerator(state, targetTables.getColumns());
        // gen = new
        // GeneralExpressionGenerator(state).setColumns(targetTables.getColumns());
        initializeTernaryPredicateVariants();
        select = new GeneralSelect();
        select.setFetchColumns(generateFetchColumns());
        List<GeneralTable> tables = targetTables.getTables();
        List<TableReferenceNode<GeneralExpression, GeneralTable>> tableList = tables.stream()
                .map(t -> new TableReferenceNode<GeneralExpression, GeneralTable>(t)).collect(Collectors.toList());
        List<Node<GeneralExpression>> joins;
        if (Randomly.getBoolean() || !state.getHandler().getOption(GeneratorNode.SUBQUERY)) {
            joins = GeneralJoin.getJoins(tableList, state);
        } else {
            joins = GeneralJoin.getJoinsWithSubquery(tableList, state);
        }
        select.setJoinList(joins.stream().collect(Collectors.toList()));
        select.setFromList(tableList.stream().collect(Collectors.toList()));
        select.setWhereClause(null);
    }

    List<Node<GeneralExpression>> generateFetchColumns() {
        List<Node<GeneralExpression>> columns = new ArrayList<>();
        if (Randomly.getBoolean()) {
            columns.add(new ColumnReferenceNode<>(new GeneralColumn("*", null, false, false)));
        } else {
            columns = Randomly.nonEmptySubset(targetTables.getColumns()).stream()
                    .map(c -> new ColumnReferenceNode<GeneralExpression, GeneralColumn>(c))
                    .collect(Collectors.toList());
        }
        return columns;
    }

    @Override
    protected ExpressionGenerator<Node<GeneralExpression>> getGen() {
        return gen;
    }

}
