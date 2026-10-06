package sqlancer.general.ast;

import sqlancer.common.ast.BinaryOperatorNode.Operator;
import sqlancer.general.gen.GeneralTableGenerator;

public final class GeneralCollate implements Operator {

    private final String textRepr;

    private GeneralCollate(String textRepr) {
        this.textRepr = textRepr;
    }

    @Override
    public String getTextRepresentation() {
        return "COLLATE " + textRepr;
    }

    public static GeneralCollate getRandom() {
        return new GeneralCollate(GeneralTableGenerator.getRandomCollate());
    }

}
