package sqlancer.general.gen;

import java.util.List;

import sqlancer.Randomly;
import sqlancer.common.ast.newast.Node;
import sqlancer.common.gen.AbstractUpdateGenerator;
import sqlancer.common.gen.ExpressionGenerator;
import sqlancer.common.query.SQLQueryAdapter;
import sqlancer.general.GeneralErrorHandler.GeneratorNode;
import sqlancer.general.GeneralErrors;
import sqlancer.general.GeneralProvider.GeneralGlobalState;
import sqlancer.general.GeneralSchema.GeneralColumn;
import sqlancer.general.GeneralSchema.GeneralTable;
import sqlancer.general.GeneralToStringVisitor;
import sqlancer.general.ast.GeneralExpression;

public final class GeneralUpdateGenerator extends AbstractUpdateGenerator<GeneralColumn> {

    private final GeneralGlobalState globalState;
    private ExpressionGenerator<Node<GeneralExpression>> gen;

    private GeneralUpdateGenerator(GeneralGlobalState globalState) {
        this.globalState = globalState;
    }

    public static SQLQueryAdapter getQuery(GeneralGlobalState globalState) {
        return new GeneralUpdateGenerator(globalState).generate();
    }

    private SQLQueryAdapter generate() {
        GeneralTable table = globalState.getSchema().getRandomTable(t -> !t.isView());
        List<GeneralColumn> columns = table.getRandomNonEmptyColumnSubset();
        gen = GeneralRandomQuerySynthesizer.getExpressionGenerator(globalState, columns);
        GeneralErrors.addInsertErrors(errors);
        sb.append("UPDATE ");
        sb.append(table.getName());
        sb.append(" SET ");
        updateColumns(columns);
        if (globalState.getHandler().getOption(GeneratorNode.UPDATE_WHERE) && Randomly.getBoolean()) {
            sb.append(" WHERE ");
            sb.append(GeneralToStringVisitor.asString(gen.generateExpression()));
            globalState.getHandler().addScore(GeneratorNode.UPDATE_WHERE);
        }

        return new SQLQueryAdapter(sb.toString(), errors);
    }

    @Override
    protected void updateValue(GeneralColumn column) {
        Node<GeneralExpression> expr;
        if (gen instanceof GeneralTypedExpressionGenerator) {
            GeneralTypedExpressionGenerator typedGen = (GeneralTypedExpressionGenerator) gen;
            if (Randomly.getBooleanWithRatherLowProbability()) {
                expr = typedGen.generateExpression(column.getType());
                GeneralErrors.addExpressionErrors(errors);
            } else {
                expr = typedGen.generateConstant(column.getType());
            }
        } else {
            if (Randomly.getBooleanWithRatherLowProbability()) {
                expr = gen.generateExpression();
                GeneralErrors.addExpressionErrors(errors);
            } else {
                expr = gen.generateConstant();
            }
        }
        sb.append(GeneralToStringVisitor.asString(expr));
    }

}
