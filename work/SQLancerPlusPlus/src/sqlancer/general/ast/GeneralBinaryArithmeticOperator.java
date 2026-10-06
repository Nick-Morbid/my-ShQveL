package sqlancer.general.ast;

import sqlancer.Randomly;
import sqlancer.common.ast.BinaryOperatorNode.Operator;
import sqlancer.general.GeneralErrorHandler;
import sqlancer.general.GeneralErrorHandler.GeneratorNode;

public enum GeneralBinaryArithmeticOperator implements Operator {
    CONCAT("||"), ADD("+"), SUB("-"), MULT("*"), DIV("/"), MOD("%"), AND("&"), OR("|"), LSHIFT("<<"), RSHIFT(">>"),
    DIV_STR("DIV"), MOD_STR("MOD"),
    // PostgreSQL
    BITWISE_XOR("#");
    // CONCAT("||"), ADD("+"), SUB("-"), MULT("*"), DIV("/"), MOD("%"), AND("&"), OR("|"), LSHIFT("<<"),
    // RSHIFT(">>");

    private String textRepr;

    GeneralBinaryArithmeticOperator(String textRepr) {
        this.textRepr = textRepr;
    }

    public static Operator getRandom() {
        return Randomly.fromOptions(values());
    }

    @Override
    public String getTextRepresentation() {
        return textRepr;
    }

    public static Operator getRandomByOptions(GeneralErrorHandler handler) {
        Operator op;
        GeneratorNode node;
        do {
            op = Randomly.fromOptions(values());
            node = GeneratorNode.valueOf("OP" + op.toString());
        } while (!handler.getOption(node) || !Randomly.getBooleanWithSmallProbability());
        handler.addScore(node);
        return op;
    }

}
