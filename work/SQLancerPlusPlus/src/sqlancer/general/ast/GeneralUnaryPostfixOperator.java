package sqlancer.general.ast;

import sqlancer.Randomly;
import sqlancer.common.ast.BinaryOperatorNode.Operator;
import sqlancer.general.GeneralErrorHandler;
import sqlancer.general.GeneralErrorHandler.GeneratorNode;
import sqlancer.general.GeneralSchema.GeneralCompositeDataType;

public enum GeneralUnaryPostfixOperator implements Operator {

    IS_NULL("IS NULL"), IS_NOT_NULL("IS NOT NULL");

    private String textRepr;

    GeneralUnaryPostfixOperator(String textRepr) {
        this.textRepr = textRepr;
    }

    @Override
    public String getTextRepresentation() {
        return textRepr;
    }

    public static Operator getRandom() {
        return Randomly.fromOptions(values());
    }

    public static Operator getRandomByOptions(GeneralErrorHandler handler) {
        Operator op;
        GeneratorNode node;
        do {
            op = Randomly.fromOptions(values());
            node = GeneratorNode.valueOf(op.toString());
        } while (!handler.getOption(node) || !Randomly.getBooleanWithSmallProbability());
        handler.addScore(node);
        return op;
    }

    public static Operator getRandomByOptions(GeneralErrorHandler handler, GeneralCompositeDataType type) {
        Operator op;
        GeneratorNode node;
        do {
            op = Randomly.fromOptions(values());
            node = GeneratorNode.valueOf(op.toString());
        } while (!handler.getOption(node)
                || !handler.getCompositeOption(node.toString(), type.getPrimitiveDataType().toString())
                || !Randomly.getBooleanWithSmallProbability());
        handler.addScore(node);
        handler.addScore(node.toString() + "-" + type.getPrimitiveDataType().toString());
        return op;
    }

}
