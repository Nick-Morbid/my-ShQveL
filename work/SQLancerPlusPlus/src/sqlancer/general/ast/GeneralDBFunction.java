package sqlancer.general.ast;

import java.util.List;

import sqlancer.Randomly;
import sqlancer.general.GeneralErrorHandler;
import sqlancer.general.GeneralErrorHandler.GeneratorNode;

public enum GeneralDBFunction {
    // trigonometric functions
    ACOS(1), //
    ASIN(1), //
    ATAN(1), //
    COS(1), //
    SIN(1), //
    TAN(1), //
    COT(1), //
    ATAN2(1), //
    // math functions
    ABS(1), //
    CEIL(1), //
    CEILING(1), //
    FLOOR(1), //
    LOG(1), //
    LOG10(1), LOG2(1), //
    LN(1), //
    PI(0), //
    SQRT(1), //
    POWER(1), //
    CBRT(1), //
    ROUND(2), //
    SIGN(1), //
    DEGREES(1), //
    RADIANS(1), //
    MOD(2), //
    XOR(2), //
    // string functions
    LENGTH(1), //
    LOWER(1), //
    UPPER(1), //
    SUBSTRING(3), //
    REVERSE(1), //
    CONCAT(1, true), //
    CONCAT_WS(1, true), CONTAINS(2), //
    PREFIX(2), //
    SUFFIX(2), //
    INSTR(2), //
    PRINTF(1, true), //
    // REGEXP_MATCHES(2), //
    // REGEXP_REPLACE(3), //
    STRIP_ACCENTS(1), //

    // date functions
    DATE_PART(2), AGE(2),

    COALESCE(3), NULLIF(2),

    // LPAD(3),
    // RPAD(3),
    LTRIM(1), RTRIM(1),
    // LEFT(2), https://github.com/cwida/general/issues/633
    // REPEAT(2),
    REPLACE(3), UNICODE(1),

    BIT_COUNT(1), BIT_LENGTH(1), LAST_DAY(1), MONTHNAME(1), DAYNAME(1), YEARWEEK(1), DAYOFMONTH(1), WEEKDAY(1),
    WEEKOFYEAR(1),

    IFNULL(2), IF(3);

    private int nrArgs;
    private boolean isVariadic;

    private static final List<GeneralDBFunction> BOOLEAN_FUNCTIONS = List.of(CONTAINS, PREFIX, SUFFIX, NULLIF, IFNULL,
            IF, COALESCE);

    private static final List<GeneralDBFunction> STRING_FUNCTIONS = List.of(LENGTH, LOWER, UPPER, SUBSTRING, REVERSE,
            CONCAT, CONCAT_WS, INSTR, PRINTF, STRIP_ACCENTS, LTRIM, RTRIM, REPLACE, UNICODE, BIT_COUNT, BIT_LENGTH,
            LAST_DAY, MONTHNAME, DAYNAME, YEARWEEK, DAYOFMONTH, WEEKDAY, WEEKOFYEAR, DATE_PART, AGE);

    private static final List<GeneralDBFunction> NUMERIC_FUNCTIONS = List.of(ABS, CEIL, CEILING, FLOOR, LOG, LOG10,
            LOG2, LN, SQRT, POWER, CBRT, ROUND, SIGN, DEGREES, RADIANS, MOD, XOR, ACOS, ASIN, ATAN, COS, SIN, TAN, COT,
            ATAN2, PI);

    GeneralDBFunction(int nrArgs) {
        this(nrArgs, false);
    }

    GeneralDBFunction(int nrArgs, boolean isVariadic) {
        this.nrArgs = nrArgs;
        this.isVariadic = isVariadic;
    }

    public static GeneralDBFunction getRandom() {
        return Randomly.fromOptions(values());
    }

    public static GeneralDBFunction getRandomByOptions(GeneralErrorHandler handler) {
        GeneralDBFunction op;
        GeneratorNode node;
        do {
            op = Randomly.fromOptions(values());
            node = GeneratorNode.valueOf(op.toString());
        } while (!handler.getOption(node) || !Randomly.getBooleanWithSmallProbability());
        handler.addScore(node);
        return op;
    }

    public int getVarArgs() {
        return isVariadic ? -nrArgs : nrArgs;
    }

    public int getNrArgs() {
        if (isVariadic) {
            return Randomly.smallNumber() + nrArgs;
        } else {
            return nrArgs;
        }
    }

    public static List<GeneralDBFunction> getBooleanFunctions() {
        return BOOLEAN_FUNCTIONS;
    }

    public static List<GeneralDBFunction> getStringFunctions() {
        return STRING_FUNCTIONS;
    }

    public static List<GeneralDBFunction> getNumericFunctions() {
        return NUMERIC_FUNCTIONS;
    }
}
