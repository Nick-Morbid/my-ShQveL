package sqlancer.general.ast;

import sqlancer.common.ast.newast.Node;
import sqlancer.general.GeneralSchema.GeneralColumn;

public class GeneralColumnReference implements Node<GeneralExpression> {

    private final GeneralColumn c;

    public GeneralColumnReference(GeneralColumn c) {
        this.c = c;
    }

    public GeneralColumn getColumn() {
        return c;
    }

}
