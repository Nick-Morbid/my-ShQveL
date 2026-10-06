package sqlancer.general.learner;

import sqlancer.common.ast.newast.Node;
import sqlancer.general.ast.GeneralExpression;

@FunctionalInterface
public interface GeneralVariableGenerator<G> {
    Node<GeneralExpression> generate(G globalState);
}
