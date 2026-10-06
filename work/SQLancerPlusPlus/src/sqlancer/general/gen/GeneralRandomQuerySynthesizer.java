package sqlancer.general.gen;

import java.util.ArrayList;
import java.util.List;
import java.util.stream.Collectors;

import sqlancer.Randomly;
import sqlancer.common.ast.newast.NewAliasNode;
import sqlancer.common.ast.newast.Node;
import sqlancer.common.ast.newast.TableReferenceNode;
import sqlancer.common.gen.ExpressionGenerator;
import sqlancer.general.GeneralErrorHandler.GeneratorNode;
import sqlancer.general.GeneralProvider.GeneralGlobalState;
import sqlancer.general.GeneralSchema.GeneralColumn;
import sqlancer.general.GeneralSchema.GeneralCompositeDataType;
import sqlancer.general.GeneralSchema.GeneralTable;
import sqlancer.general.GeneralSchema.GeneralTables;
import sqlancer.general.ast.GeneralConstant;
import sqlancer.general.ast.GeneralExpression;
import sqlancer.general.ast.GeneralJoin;
import sqlancer.general.ast.GeneralSelect;
import sqlancer.general.ast.GeneralSelect.GeneralSubquery;

public final class GeneralRandomQuerySynthesizer {

    private GeneralRandomQuerySynthesizer() {
    }

    public static GeneralSelect generateSelect(GeneralGlobalState globalState, List<GeneralColumn> columns) {
        GeneralTables targetTables = globalState.getSchema().getRandomTableNonEmptyTables();
        // TODO currently it only support Typed expressions
        GeneralTypedExpressionGenerator gen = new GeneralTypedExpressionGenerator(globalState)
                .setColumns(targetTables.getColumns());
        GeneralSelect select = new GeneralSelect();
        // TODO: distinct
        // select.setDistinct(Randomly.getBoolean());
        // boolean allowAggregates = Randomly.getBooleanWithSmallProbability();
        List<Node<GeneralExpression>> colExpressions = new ArrayList<>();
        for (GeneralColumn c : columns) {
            // if (allowAggregates && Randomly.getBoolean()) {
            Node<GeneralExpression> expression = gen.generateExpression(c.getType());
            colExpressions.add(expression);
            // } else {
            // colExpressions.add(gen());
            // }
        }
        select.setFetchColumns(colExpressions);
        List<GeneralTable> tables = targetTables.getTables();
        List<TableReferenceNode<GeneralExpression, GeneralTable>> tableList = tables.stream()
                .map(t -> new TableReferenceNode<GeneralExpression, GeneralTable>(t)).collect(Collectors.toList());
        List<Node<GeneralExpression>> joins = GeneralJoin.getJoins(tableList, globalState);
        select.setJoinList(joins.stream().collect(Collectors.toList()));
        select.setFromList(tableList.stream().collect(Collectors.toList()));
        if (Randomly.getBoolean()) {
            select.setWhereClause(getExpressionGenerator(globalState, columns).generateExpression());
        }
        if (Randomly.getBoolean()) {
            select.setOrderByExpressions(gen.generateOrderBys());
        }
        if (Randomly.getBoolean()) {
            select.setGroupByExpressions(gen.generateExpressions(Randomly.smallNumber() + 1));
        }

        if (Randomly.getBoolean()) {
            select.setLimitClause(
                    GeneralConstant.createIntConstant(Randomly.getNotCachedInteger(0, Integer.MAX_VALUE)));
        }
        if (Randomly.getBoolean()) {
            select.setOffsetClause(
                    GeneralConstant.createIntConstant(Randomly.getNotCachedInteger(0, Integer.MAX_VALUE)));
        }
        if (Randomly.getBoolean()) {
            select.setHavingClause(gen.generateHavingClause());
        }
        return select;
    }

    public static ExpressionGenerator<Node<GeneralExpression>> getExpressionGenerator(GeneralGlobalState globalState,
            List<GeneralColumn> columns) {
        ExpressionGenerator<Node<GeneralExpression>> gen;
        if (globalState.getHandler().getOption(GeneratorNode.UNTYPE_EXPR)
                || Randomly.getBooleanWithSmallProbability()) {
            gen = new GeneralExpressionGenerator(globalState).setColumns(columns);
            globalState.getHandler().addScore(GeneratorNode.UNTYPE_EXPR);
        } else {
            gen = new GeneralTypedExpressionGenerator(globalState).setColumns(columns);
        }
        return gen;
    }

    public static GeneralSubquery generateSubquery(GeneralGlobalState globalState, String name,
            GeneralTables targetTables) {
        List<Node<GeneralExpression>> columns = new ArrayList<>();
        List<GeneralColumn> colRefs = new ArrayList<>();
        GeneralTypedExpressionGenerator gen = new GeneralTypedExpressionGenerator(globalState)
                .setColumns(targetTables.getColumns());
        for (int i = 0; i < Randomly.smallNumber() + 1; i++) {
            GeneralColumn c = new GeneralColumn(String.format("col%d", i),
                    GeneralCompositeDataType.getRandomWithoutNull(), false, false);
            colRefs.add(c);
            NewAliasNode<GeneralExpression> colExpr = new NewAliasNode<>(gen.generateExpression(c.getType()),
                    c.getName());
            columns.add(colExpr);
        }
        // for (int i = 0; i < Randomly.smallNumber() + 1; i++) {
        // NewAliasNode<GeneralExpression> colExpr = new NewAliasNode<GeneralExpression>(gen.generateExpression(false),
        // String.format("col%d", i));
        // columns.add(colExpr);
        // }
        GeneralSelect select = new GeneralSelect();
        List<TableReferenceNode<GeneralExpression, GeneralTable>> tableList = targetTables.getTables().stream()
                .map(t -> new TableReferenceNode<GeneralExpression, GeneralTable>(t)).collect(Collectors.toList());
        select.setFromList(tableList.stream().collect(Collectors.toList()));
        select.setFetchColumns(columns);
        if (Randomly.getBoolean()) {
            select.setWhereClause(gen.generateExpression());
        }
        GeneralTable newTable = new GeneralTable(name, colRefs, false);
        newTable.getColumns().forEach(c -> c.setTable(newTable));
        return new GeneralSubquery(select, name, newTable);
    }

}
