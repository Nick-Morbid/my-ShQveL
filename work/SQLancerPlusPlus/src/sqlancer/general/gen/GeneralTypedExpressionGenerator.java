package sqlancer.general.gen;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.stream.Collectors;

import sqlancer.Randomly;
import sqlancer.common.ast.BinaryOperatorNode.Operator;
import sqlancer.common.ast.newast.NewBetweenOperatorNode;
import sqlancer.common.ast.newast.NewBinaryOperatorNode;
import sqlancer.common.ast.newast.NewCaseOperatorNode;
import sqlancer.common.ast.newast.NewFunctionNode;
import sqlancer.common.ast.newast.NewInOperatorNode;
import sqlancer.common.ast.newast.NewOrderingTerm;
import sqlancer.common.ast.newast.NewOrderingTerm.Ordering;
import sqlancer.common.ast.newast.NewUnaryPostfixOperatorNode;
import sqlancer.common.ast.newast.NewUnaryPrefixOperatorNode;
import sqlancer.common.ast.newast.Node;
import sqlancer.common.gen.TypedExpressionGenerator;
import sqlancer.general.GeneralErrorHandler;
import sqlancer.general.GeneralErrorHandler.GeneratorNode;
import sqlancer.general.GeneralProvider.GeneralGlobalState;
import sqlancer.general.GeneralSchema;
import sqlancer.general.GeneralSchema.GeneralColumn;
import sqlancer.general.GeneralSchema.GeneralCompositeDataType;
import sqlancer.general.GeneralSchema.GeneralDataType;
import sqlancer.general.ast.GeneralBinaryArithmeticOperator;
import sqlancer.general.ast.GeneralBinaryComparisonOperator;
import sqlancer.general.ast.GeneralBinaryLogicalOperator;
import sqlancer.general.ast.GeneralBinaryOperator;
import sqlancer.general.ast.GeneralCast;
import sqlancer.general.ast.GeneralCast.GeneralCastOperator;
import sqlancer.general.ast.GeneralColumnReference;
import sqlancer.general.ast.GeneralConstant;
import sqlancer.general.ast.GeneralExpression;
import sqlancer.general.ast.GeneralFunction;
import sqlancer.general.ast.GeneralUnaryPostfixOperator;
import sqlancer.general.ast.GeneralUnaryPrefixOperator;

public class GeneralTypedExpressionGenerator
        extends TypedExpressionGenerator<Node<GeneralExpression>, GeneralColumn, GeneralCompositeDataType> {

    private final GeneralGlobalState globalState;
    private boolean nullFlag;

    public GeneralTypedExpressionGenerator(GeneralGlobalState globalState) {
        this.globalState = globalState;
    }

    @Override
    public Node<GeneralExpression> generateExpression() {
        return generateExpression(GeneralDataType.BOOLEAN.get());
    }

    @Override
    public Node<GeneralExpression> generateExpression(boolean isTyped) {
        if (isTyped) {
            return generateExpression(GeneralDataType.BOOLEAN.get());
        } else {
            return generateExpression(GeneralCompositeDataType.getRandomWithoutNull(globalState));
        }
    }

    @Override
    public Node<GeneralExpression> generateExpression(GeneralCompositeDataType dataType) {
        return generateExpression(dataType, 0); // To make sure the start not so cold
    }

    // public Node<GeneralExpression> generateAggregate() {
    // return getAggregate(getRandomType());
    // }

    @Override
    public Node<GeneralExpression> generateHavingClause() {
        allowAggregates = true;
        Node<GeneralExpression> expression = generateExpression(GeneralDataType.BOOLEAN.get());
        allowAggregates = false;
        return expression;
    }

    @Override
    public List<Node<GeneralExpression>> generateOrderBys() {
        HashMap<String, Integer> tmpCompositeScore = new HashMap<>(
                globalState.getHandler().getGeneratorInfo().getCompositeGeneratorScore());
        // globalState.getLogger().writeCurrent("-- " + tmpCompositeScore);
        List<Node<GeneralExpression>> expr = super.generateOrderBys();
        List<Node<GeneralExpression>> orderingTerms = new ArrayList<>(expr.size());
        for (Node<GeneralExpression> curExpr : expr) {
            if (Randomly.getBoolean()) {
                curExpr = new NewOrderingTerm<>(curExpr, Ordering.getRandom());
            }
            orderingTerms.add(curExpr);
        }
        globalState.getHandler().loadCompositeScore(tmpCompositeScore);
        // globalState.getLogger().writeCurrent("-- " +
        // globalState.getHandler().getGeneratorInfo().getCompositeGeneratorScore());
        return orderingTerms;
    }

    // public List<GeneralDBFunction> getFunctionsCompatibleWith(GeneralCompositeDataType returnType) {
    // return Stream.of(GeneralDBFunction.values())
    // .filter(f -> globalState.getHandler().getCompositeOption(f.toString(), returnType.toString()))
    // .collect(Collectors.toList());
    // }

    private List<Node<GeneralExpression>> generateFunctionExpressions(GeneralFunction function, int depth,
            GeneralErrorHandler handler) {
        List<Node<GeneralExpression>> args = new ArrayList<>();
        for (int i = 0; i < function.getNrArgs(); i++) {
            final int ind = i;
            // TODO: looks like we could make this invarian out of the loop. Not sure if stronly needed.
            List<GeneralCompositeDataType> availTypes = GeneralCompositeDataType.getSupportedTypes().stream()
                    .filter(t -> handler.getCompositeOptionNullAsFalse(function.toString() + "-" + ind + t.toString()))
                    .collect(Collectors.toList());
            GeneralCompositeDataType type;
            // TODO: make it fully controlled by the handler
            if (availTypes.isEmpty() || Randomly.getBooleanWithRatherLowProbability()) {
                type = getRandomType();
            } else {
                type = Randomly.fromList(availTypes);
            }
            // nullFlag = false;
            Node<GeneralExpression> newExpr = generateExpression(type, depth);
            args.add(newExpr);
            // check if newExpr is a
            if (!nullFlag) {
                String key = function.toString() + "-" + ind + type.toString();
                handler.addScore(key);
            }
            // nullFlag = false;
        }
        return args;
    }

    @Override
    public Node<GeneralExpression> generateExpression(GeneralCompositeDataType type, int depth) {
        // if (allowAggregates && Randomly.getBoolean()) {
        // return getAggregate(type);
        // }
        GeneralErrorHandler handler = globalState.getHandler();
        if (depth >= globalState.getOptions().getMaxExpressionDepth()
                || depth >= globalState.getHandler().getCurDepth(globalState.getDatabaseName())
                || Randomly.getBooleanWithRatherLowProbability()) {
            return generateLeafNode(type);
        } else {
            if (Randomly.getBooleanWithRatherLowProbability() && handler.getOption(GeneratorNode.FUNC)) {
                handler.addScore(GeneratorNode.FUNC);
                List<GeneralFunction> applicableFunctions = new ArrayList<>();
                try {
                    applicableFunctions = GeneralFunction.getRandomCompatibleFunctions(handler, type);
                } catch (Exception e) {
                    // TODO: handle exception
                    System.out.println(e);
                    System.out.println("Error in getting compatible functions for type: " + type);
                }
                if (!applicableFunctions.isEmpty()) {
                    GeneralFunction function = Randomly.fromList(applicableFunctions);
                    nullFlag = false;
                    NewFunctionNode<GeneralExpression, GeneralFunction> functionNode = new NewFunctionNode<>(
                            generateFunctionExpressions(function, depth + 1, handler), function);
                    handler.addScore("FUNCTION-" + function.toString());
                    if (!nullFlag) {
                        handler.addScore(type.toString() + "-" + function.toString());
                    }
                    nullFlag = false;
                    return functionNode;
                }
            }
            if (Randomly.getBooleanWithRatherLowProbability() && handler.getOption(GeneratorNode.CAST)) {
                handler.addScore(GeneratorNode.CAST);
                return new GeneralCast(generateExpression(getRandomType(), depth + 1), type,
                        GeneralCastOperator.getRandomByOptions(handler));
            }
            if (Randomly.getBooleanWithRatherLowProbability() && handler.getOption(GeneratorNode.CASE)) {
                handler.addScore(GeneratorNode.CASE);
                GeneralCompositeDataType condType = getRandomType();
                List<Node<GeneralExpression>> conditions = new ArrayList<>();
                List<Node<GeneralExpression>> cases = new ArrayList<>();
                Node<GeneralExpression> switchCond = generateExpression(condType, depth + 1);
                for (int i = 0; i < Randomly.smallNumber() + 1; i++) {
                    conditions.add(generateExpression(condType, depth + 1));
                    cases.add(generateExpression(type, depth + 1));
                }
                Node<GeneralExpression> elseExpr = null;
                if (Randomly.getBoolean()) {
                    elseExpr = generateExpression(type, depth + 1);
                }
                return new NewCaseOperatorNode<GeneralExpression>(switchCond, conditions, cases, elseExpr);

            }
            if (Randomly.getBooleanWithRatherLowProbability() && handler.getOption(GeneratorNode.BINARY_OPERATOR)) {
                handler.addScore(GeneratorNode.BINARY_OPERATOR);
                Operator op = GeneralBinaryOperator.getRandomByType(globalState.getHandler(), type);
                if (op != null) {
                    List<GeneralCompositeDataType> availTypes = GeneralCompositeDataType.getSupportedTypes().stream()
                            .filter(t -> handler
                                    .getCompositeOptionNullAsFalse("BINOP" + op.toString() + "-" + t.toString()))
                            .collect(Collectors.toList());
                    GeneralCompositeDataType newType;
                    if (availTypes.isEmpty() || Randomly.getBooleanWithRatherLowProbability()) {
                        newType = getRandomType();
                    } else {
                        newType = Randomly.fromList(availTypes);
                    }
                    Node<GeneralExpression> left = generateExpression(newType, depth + 1);
                    Node<GeneralExpression> right = generateExpression(newType, depth + 1);
                    if (!nullFlag) {
                        handler.addScore("BINOP" + op.toString() + "-" + newType.toString());
                    }
                    return new NewBinaryOperatorNode<GeneralExpression>(left, right, op);
                }
            }

            switch (type.getPrimitiveDataType()) {
            case BOOLEAN:
                return generateBooleanExpression(depth);
            case INT:
                double rand = Randomly.getPercentage();
                double threshold = GeneralBinaryArithmeticOperator.values().length
                        / (double) (GeneralBinaryArithmeticOperator.values().length
                                + GeneralBinaryComparisonOperator.values().length);
                if (rand < threshold) {
                    return new NewBinaryOperatorNode<GeneralExpression>(
                            generateExpression(GeneralDataType.INT.get(), depth + 1),
                            generateExpression(GeneralDataType.INT.get(), depth + 1),
                            GeneralBinaryArithmeticOperator.getRandomByOptions(globalState.getHandler()));
                } else {
                    return new NewUnaryPrefixOperatorNode<GeneralExpression>(
                            generateExpression(GeneralDataType.INT.get(), depth + 1), GeneralUnaryPrefixOperator
                                    .getRandomByOptions(globalState.getHandler(), GeneralDataType.INT.get()));
                }
            case STRING:
                // case BYTES: // TODO split
                return generateStringExpression(depth);
            // if (Randomly.getBoolean()) {
            // stringExpr = new CockroachDBCollate(stringExpr, CockroachDBCommon.getRandomCollate());
            // }
            case VARTYPE:
                // TODO maybe learn the function here..
                return generateLeafNode(type);
            // case FLOAT:
            // return generateLeafNode(type); // TODO
            default:
                throw new AssertionError(type);
            }
        }
    }

    // private GeneralExpression getAggregate(GeneralCompositeDataType type) {
    // GeneralAggregateFunction agg = Randomly
    // .fromList(CockroachDBAggregate.GeneralAggregateFunction.getAggregates(type.getPrimitiveDataType()));
    // return generateArgsForAggregate(type, agg);
    // }

    // public CockroachDBAggregate generateArgsForAggregate(GeneralCompositeDataType type,
    // GeneralAggregateFunction agg) {
    // List<GeneralDataType> types = agg.getTypes(type.getPrimitiveDataType());
    // List<GeneralExpression> args = new ArrayList<>();
    // allowAggregates = false; //
    // for (GeneralDataType argType : types) {
    // args.add(generateExpression(argType.get()));
    // }
    // return new CockroachDBAggregate(agg, args);
    // }

    private enum BooleanExpression {
        // NOT, COMPARISON, AND_OR_CHAIN, REGEX, IS_NULL, IS_NAN, IN, BETWEEN, MULTI_VALUED_COMPARISON
        UNARY_PREFIX(GeneralUnaryPrefixOperator.values().length),
        BINARY_COMPARISON(GeneralBinaryComparisonOperator.values().length),
        BINARY_LOGICAL(GeneralBinaryLogicalOperator.values().length),
        BINARY_OPERATOR(GeneralBinaryOperator.getOperators().size()),
        UNARY_POSTFIX(GeneralUnaryPostfixOperator.values().length), IN(1), BETWEEN(1);

        private final int proportion;

        BooleanExpression(int proportion) {
            this.proportion = proportion;
        }

        private static List<BooleanExpression> getOptionsByProportions() {
            List<BooleanExpression> options = new ArrayList<>();
            for (BooleanExpression expr : values()) {
                for (int i = 0; i < expr.proportion; i++) {
                    options.add(expr);
                }
            }
            return options;
        }

        public static BooleanExpression getRandomByOptions(GeneralErrorHandler handler) {
            BooleanExpression expr;
            GeneratorNode node;
            do {
                expr = Randomly.fromList(getOptionsByProportions());
                node = GeneratorNode.valueOf(expr.toString());
            } while (!handler.getOption(node) || !Randomly.getBooleanWithSmallProbability());
            handler.addScore(node);
            return expr;
        }
    }

    private enum StringExpression {
        CONCAT
    }

    private Node<GeneralExpression> generateStringExpression(int depth) {
        StringExpression exprType = Randomly.fromOptions(StringExpression.values());
        switch (exprType) {
        case CONCAT:
            return new NewBinaryOperatorNode<GeneralExpression>(
                    generateExpression(GeneralDataType.STRING.get(), depth + 1),
                    generateExpression(GeneralDataType.STRING.get(), depth + 1),
                    GeneralBinaryArithmeticOperator.CONCAT);
        default:
            throw new AssertionError(exprType);
        }
    }

    private Node<GeneralExpression> generateBooleanExpression(int depth) {
        GeneralErrorHandler handler = globalState.getHandler();
        BooleanExpression exprType = BooleanExpression.getRandomByOptions(handler);
        Node<GeneralExpression> expr;
        switch (exprType) {
        case UNARY_PREFIX:
            return new NewUnaryPrefixOperatorNode<GeneralExpression>(
                    generateExpression(GeneralDataType.BOOLEAN.get(), depth + 1), GeneralUnaryPrefixOperator.NOT);
        case BINARY_COMPARISON:
            return getBinaryComparison(depth);
        case BINARY_LOGICAL:
            return getAndOrChain(depth);
        // case REGEX:
        // return new CockroachDBRegexOperation(generateExpression(GeneralDataType.STRING.get(), depth + 1),
        // generateExpression(GeneralDataType.STRING.get(), depth + 1),
        // CockroachDBRegexOperator.getRandom());
        case UNARY_POSTFIX:
            return new NewUnaryPostfixOperatorNode<GeneralExpression>(generateExpression(getRandomType(), depth + 1),
                    GeneralUnaryPostfixOperator.getRandomByOptions(handler));
        case BINARY_OPERATOR:
            Operator binaryOperator = GeneralBinaryOperator.getRandomByType(globalState.getHandler(),
                    GeneralDataType.BOOLEAN.get());
            if (binaryOperator == null) {
                // Learned masks may temporarily remove every boolean
                // operator.  Do not construct an AST node with a null
                // operator; fall back to a comparison expression.
                return getBinaryComparison(depth);
            }
            return new NewBinaryOperatorNode<GeneralExpression>(generateExpression(getRandomType(), depth + 1),
                    generateExpression(getRandomType(), depth + 1), binaryOperator);
        case IN:
            return getInOperation(depth);
        case BETWEEN:
            GeneralCompositeDataType type = getRandomType();
            expr = generateExpression(type, depth + 1);
            Node<GeneralExpression> left = generateExpression(type, depth + 1);
            Node<GeneralExpression> right = generateExpression(type, depth + 1);
            return new NewBetweenOperatorNode<GeneralExpression>(expr, left, right, Randomly.getBoolean());
        // case MULTI_VALUED_COMPARISON: // TODO other operators
        // type = getRandomType();
        // left = generateExpression(type, depth + 1);
        // List<GeneralExpression> rightList = generateExpressions(type, Randomly.smallNumber() + 2, depth + 1);
        // return new CockroachDBMultiValuedComparison(left, rightList, MultiValuedComparisonType.getRandom(),
        // MultiValuedComparisonOperator.getRandomGenericComparisonOperator());
        default:
            throw new AssertionError(exprType);
        }
    }

    private Node<GeneralExpression> getAndOrChain(int depth) {
        Node<GeneralExpression> left = generateExpression(GeneralDataType.BOOLEAN.get(), depth + 1);
        for (int i = 0; i < Randomly.smallNumber() + 1; i++) {
            Node<GeneralExpression> right = generateExpression(GeneralDataType.BOOLEAN.get(), depth + 1);
            left = new NewBinaryOperatorNode<>(left, right,
                    GeneralBinaryLogicalOperator.getRandomByOptions(globalState.getHandler()));
        }
        return left;
    }

    private Node<GeneralExpression> getInOperation(int depth) {
        GeneralCompositeDataType type = getRandomType();
        return new NewInOperatorNode<GeneralExpression>(generateExpression(type, depth + 1),
                generateExpressions(type, Randomly.smallNumber() + 1, depth + 1), Randomly.getBoolean());
    }

    @Override
    protected GeneralCompositeDataType getRandomType() {
        if (columns.isEmpty() || Randomly.getBooleanWithRatherLowProbability()) {
            return GeneralCompositeDataType.getRandomWithoutNull(globalState);
        } else {
            return Randomly.fromList(columns).getType();
        }
    }

    private Node<GeneralExpression> getBinaryComparison(int depth) {
        GeneralCompositeDataType type = getRandomType();
        Node<GeneralExpression> left = generateExpression(type, depth + 1);
        Node<GeneralExpression> right = generateExpression(type, depth + 1);
        return new NewBinaryOperatorNode<GeneralExpression>(left, right,
                GeneralBinaryComparisonOperator.getRandomByOptions(globalState.getHandler(), type));
    }

    private boolean isTypeCompatible(GeneralCompositeDataType typeA, GeneralCompositeDataType typeB) {
        if (typeA.getPrimitiveDataType() != typeB.getPrimitiveDataType()) {
            return false;
        }
        if (typeA.getPrimitiveDataType() == GeneralDataType.STRING
                && typeB.getPrimitiveDataType() == GeneralDataType.STRING) {
            return true; // STRING is compatible with all VARTYPEs
        }
        return typeA.toString().equals(typeB.toString());
    }

    @Override
    protected boolean canGenerateColumnOfType(GeneralCompositeDataType type) {
        return columns.stream().anyMatch(c -> isTypeCompatible(c.getType(), type));
    }

    @Override
    public Node<GeneralExpression> generateConstant(GeneralCompositeDataType type) {
        if (Randomly.getBooleanWithRatherLowProbability()) {
            nullFlag = true;
            if (Randomly.getBooleanWithSmallProbability()) {
                // generate a function with all-NULL arguments
                GeneralFunction function = GeneralFunction.getRandomByOptions(globalState.getHandler());
                return new NewFunctionNode<>(
                        Collections.nCopies(function.getNrArgs(), GeneralConstant.createNullConstant()), function);
            }
            return GeneralConstant.createNullConstant();
        }
        switch (type.getPrimitiveDataType()) {
        case INT:
            return GeneralConstant.createIntConstant(globalState.getRandomly().getInteger());
        case BOOLEAN:
            return GeneralConstant.createBooleanConstant(Randomly.getBoolean());
        case STRING:
            return GeneralConstant.createStringConstant(globalState.getRandomly().getString());
        case VARTYPE:
            return generateVartypeConstant(type);
        default:
            throw new AssertionError(type);
        }
    }

    @Override
    public Node<GeneralExpression> generateConstant() {
        return generateConstant(GeneralCompositeDataType.getRandomWithoutNull(globalState));
    }

    private Node<GeneralExpression> generateVartypeConstant(GeneralCompositeDataType type) {
        String varString = GeneralSchema.getFragments().get(type.getId(), globalState);
        if (varString == "NULL") {
            nullFlag = true;
        }
        return GeneralConstant.createVartypeConstant(varString);
    }

    public GeneralGlobalState getGlobalState() {
        return globalState;
    }

    @Override
    protected Node<GeneralExpression> generateColumn(GeneralCompositeDataType type) {
        GeneralColumn column = Randomly.fromList(
                columns.stream().filter(c -> isTypeCompatible(c.getType(), type)).collect(Collectors.toList()));
        // if (type.getPrimitiveDataType().equals(GeneralDataType.VARTYPE)) {
        // globalState.getLogger().writeCurrent("-- type " + type);
        // }
        return new GeneralColumnReference(column);
    }

    @Override
    public Node<GeneralExpression> generatePredicate() {
        return generateExpression(GeneralDataType.BOOLEAN.get());
    }

    @Override
    public Node<GeneralExpression> negatePredicate(Node<GeneralExpression> predicate) {
        return new NewUnaryPrefixOperatorNode<GeneralExpression>(predicate, GeneralUnaryPrefixOperator.NOT);
    }

    @Override
    public Node<GeneralExpression> isNull(Node<GeneralExpression> expr) {
        return new NewUnaryPostfixOperatorNode<GeneralExpression>(expr, GeneralUnaryPostfixOperator.IS_NULL);
    }

}
