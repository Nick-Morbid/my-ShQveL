package sqlancer.general.ast;

import sqlancer.Randomly;
import sqlancer.common.ast.BinaryOperatorNode.Operator;
import sqlancer.general.GeneralErrorHandler;
import sqlancer.general.GeneralErrorHandler.GeneratorNode;

public enum GeneralBinaryLogicalOperator implements Operator {

    AND, OR;

    @Override
    public String getTextRepresentation() {
        return toString();
    }

    public static Operator getRandom() {
        return Randomly.fromOptions(values());
    }

    public static Operator getRandomByOptions(GeneralErrorHandler handler) {
        Operator op;
        GeneratorNode node;
        do {
            op = Randomly.fromOptions(values());
            node = GeneratorNode.valueOf("LOP" + op.toString());
        } while (!handler.getOption(node) || !Randomly.getBooleanWithSmallProbability());
        handler.addScore(node);
        return op;
    }
}
