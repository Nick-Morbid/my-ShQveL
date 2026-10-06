package sqlancer.general.ast;

import java.sql.Timestamp;
import java.text.SimpleDateFormat;

import sqlancer.common.ast.newast.Node;

public class GeneralConstant implements Node<GeneralExpression> {

    private GeneralConstant() {
    }

    public static class GeneralNullConstant extends GeneralConstant {

        @Override
        public String toString() {
            return "NULL";
        }

    }

    public static class GeneralIntConstant extends GeneralConstant {

        private final long value;

        public GeneralIntConstant(long value) {
            this.value = value;
        }

        @Override
        public String toString() {
            return String.valueOf(value);
        }

        public long getValue() {
            return value;
        }

    }

    public static class GeneralDoubleConstant extends GeneralConstant {

        private final double value;

        public GeneralDoubleConstant(double value) {
            this.value = value;
        }

        public double getValue() {
            return value;
        }

        @Override
        public String toString() {
            if (value == Double.POSITIVE_INFINITY) {
                return "'+Inf'";
            } else if (value == Double.NEGATIVE_INFINITY) {
                return "'-Inf'";
            }
            return String.valueOf(value);
        }

    }

    public static class GeneralTextConstant extends GeneralConstant {

        private final String value;

        public GeneralTextConstant(String value) {
            this.value = value;
        }

        public String getValue() {
            return value;
        }

        @Override
        public String toString() {
            return "'" + value.replace("'", "''") + "'";
        }

    }

    public static class GeneralBitConstant extends GeneralConstant {

        private final String value;

        public GeneralBitConstant(long value) {
            this.value = Long.toBinaryString(value);
        }

        public String getValue() {
            return value;
        }

        @Override
        public String toString() {
            return "B'" + value + "'";
        }

    }

    public static class GeneralDateConstant extends GeneralConstant {

        public String textRepr;

        public GeneralDateConstant(long val) {
            Timestamp timestamp = new Timestamp(val);
            SimpleDateFormat dateFormat = new SimpleDateFormat("yyyy-MM-dd");
            textRepr = dateFormat.format(timestamp);
        }

        public String getValue() {
            return textRepr;
        }

        @Override
        public String toString() {
            return String.format("DATE '%s'", textRepr);
        }

    }

    public static class GeneralTimestampConstant extends GeneralConstant {

        public String textRepr;

        public GeneralTimestampConstant(long val) {
            Timestamp timestamp = new Timestamp(val);
            SimpleDateFormat dateFormat = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss");
            textRepr = dateFormat.format(timestamp);
        }

        public String getValue() {
            return textRepr;
        }

        @Override
        public String toString() {
            return String.format("TIMESTAMP '%s'", textRepr);
        }

    }

    public static class GeneralBooleanConstant extends GeneralConstant {

        private final boolean value;

        public GeneralBooleanConstant(boolean value) {
            this.value = value;
        }

        public boolean getValue() {
            return value;
        }

        @Override
        public String toString() {
            return String.valueOf(value);
        }

    }

    public static class GeneralVartypeConstant extends GeneralConstant {

        private final String value;

        public GeneralVartypeConstant(String value) {
            this.value = value;
        }

        public String getValue() {
            return value;
        }

        @Override
        public String toString() {
            return value;
        }

    }

    public static Node<GeneralExpression> createStringConstant(String text) {
        return new GeneralTextConstant(text);
    }

    public static Node<GeneralExpression> createFloatConstant(double val) {
        return new GeneralDoubleConstant(val);
    }

    public static Node<GeneralExpression> createIntConstant(long val) {
        return new GeneralIntConstant(val);
    }

    public static Node<GeneralExpression> createNullConstant() {
        return new GeneralNullConstant();
    }

    public static Node<GeneralExpression> createBooleanConstant(boolean val) {
        return new GeneralBooleanConstant(val);
    }

    public static Node<GeneralExpression> createDateConstant(long integer) {
        return new GeneralDateConstant(integer);
    }

    public static Node<GeneralExpression> createTimestampConstant(long integer) {
        return new GeneralTimestampConstant(integer);
    }

    public static Node<GeneralExpression> createVartypeConstant(String text) {
        return new GeneralVartypeConstant(text);
    }

}
