package sqlancer.general.ast;

import sqlancer.Randomly;
import sqlancer.common.ast.BinaryOperatorNode.Operator;
import sqlancer.common.ast.newast.Node;
import sqlancer.general.GeneralErrorHandler;
import sqlancer.general.GeneralErrorHandler.GeneratorNode;
import sqlancer.general.GeneralSchema.GeneralCompositeDataType;

public class GeneralCast implements Node<GeneralExpression> {

    private final GeneralCompositeDataType type;
    private final Node<GeneralExpression> expr;
    private final GeneralCastOperator op;

    public enum GeneralCastOperator implements Operator {
        FUNC, COLON;

        public static GeneralCastOperator getRandom() {
            return Randomly.fromOptions(values());
        }

        public static GeneralCastOperator getRandomByOptions(GeneralErrorHandler handler) {
            GeneralCastOperator op;
            if (!handler.getOption(GeneratorNode.CAST_FUNC)) {
                op = COLON;
            } else {
                op = FUNC;
            }
            if (Randomly.getBooleanWithSmallProbability()) {
                op = getRandom();
            }
            handler.addScore(GeneratorNode.valueOf("CAST_" + op.toString()));
            return op;
        }

        @Override
        public String getTextRepresentation() {
            return toString();
        }
    }

    public GeneralCast(Node<GeneralExpression> expr, GeneralCompositeDataType type, GeneralCastOperator op) {
        this.expr = expr;
        this.type = type;
        this.op = op;
    }

    public GeneralCompositeDataType getType() {
        return type;
    }

    public Node<GeneralExpression> getExpr() {
        return expr;
    }

    public boolean isFunc() {
        return op == GeneralCastOperator.FUNC;
    }
}
