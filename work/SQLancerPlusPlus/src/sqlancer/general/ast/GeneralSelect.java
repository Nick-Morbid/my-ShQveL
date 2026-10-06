package sqlancer.general.ast;

import sqlancer.common.ast.SelectBase;
import sqlancer.common.ast.newast.Node;
import sqlancer.general.GeneralSchema.GeneralTable;

public class GeneralSelect extends SelectBase<Node<GeneralExpression>> implements Node<GeneralExpression> {

    private boolean isDistinct;

    public void setDistinct(boolean isDistinct) {
        this.isDistinct = isDistinct;
    }

    public boolean isDistinct() {
        return isDistinct;
    }

    public static class GeneralSubquery implements Node<GeneralExpression> {

        private final GeneralSelect select;
        private final String name;
        private final GeneralTable targetTable;

        public GeneralSubquery(GeneralSelect select, String name, GeneralTable targetTable) {
            this.select = select;
            this.name = name;
            this.targetTable = targetTable;
        }

        public GeneralSelect getSelect() {
            return select;
        }

        public String getName() {
            return name;
        }

        public GeneralTable getTable() {
            return targetTable;
        }

    }

}
