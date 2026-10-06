package sqlancer.general.ast;

import sqlancer.Randomly;
import sqlancer.common.ast.BinaryOperatorNode.Operator;
import sqlancer.general.GeneralErrorHandler;
import sqlancer.general.GeneralErrorHandler.GeneratorNode;
import sqlancer.general.GeneralSchema.GeneralCompositeDataType;

public enum GeneralUnaryPrefixOperator implements Operator {

    NOT("NOT"), PLUS("+"), MINUS("-"),
    // PostgreSQL
    SQT_ROOT("|/"), ABS_VAL("@"), BIT_NOT("~"), CUBE_ROOT("||/"),;

    private String textRepr;

    GeneralUnaryPrefixOperator(String textRepr) {
        this.textRepr = textRepr;
    }

    @Override
    public String getTextRepresentation() {
        return textRepr;
    }

    public static GeneralUnaryPrefixOperator getRandom() {
        return Randomly.fromOptions(values());
    }

    public static GeneralUnaryPrefixOperator getRandomByOptions(GeneralErrorHandler handler) {
        GeneralUnaryPrefixOperator op;
        GeneratorNode node;
        do {
            op = Randomly.fromOptions(values());
            node = GeneratorNode.valueOf("U" + op.toString());
        } while (!handler.getOption(node) || !Randomly.getBooleanWithSmallProbability());
        handler.addScore(node);
        return op;
    }

    public static GeneralUnaryPrefixOperator getRandomByOptions(GeneralErrorHandler handler,
            GeneralCompositeDataType type) {
        GeneralUnaryPrefixOperator op;
        GeneratorNode node;
        do {
            op = Randomly.fromOptions(values());
            node = GeneratorNode.valueOf("U" + op.toString());
        } while (!handler.getOption(node)
                || !handler.getCompositeOption(node.toString(), type.getPrimitiveDataType().toString())
                || !Randomly.getBooleanWithSmallProbability());
        handler.addScore(node);
        handler.addScore(node.toString() + "-" + type.getPrimitiveDataType().toString());
        return op;
    }
}
