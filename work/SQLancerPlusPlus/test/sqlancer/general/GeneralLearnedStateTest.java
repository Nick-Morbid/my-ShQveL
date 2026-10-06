package sqlancer.general;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;

import org.junit.jupiter.api.Test;

import sqlancer.general.GeneralLearningManager.SQLFeature;
import sqlancer.general.GeneralOptions.GeneralDatabaseEngineFactory;
import sqlancer.general.GeneralProvider.GeneralGlobalState;
import sqlancer.general.ast.GeneralBinaryOperator;
import sqlancer.general.ast.GeneralFunction;

public class GeneralLearnedStateTest {

    @Test
    public void checkpointRoundTripRestoresGeneratorStateAndDisablesLearning() throws Exception {
        GeneralOptions options = new GeneralOptions();
        options.databaseEngine = GeneralDatabaseEngineFactory.POSTGRESQL;
        GeneralGlobalState state = new GeneralGlobalState();
        state.setDbmsSpecificOptions(options);

        GeneralSchema.resetLearnedTypes();
        GeneralSchema.getFragments().loadCheckpointFragment("DATE", "'2024-01-02'");
        GeneralFunction.getFragments().clearFragments();
        GeneralFunction.getFragments().loadCheckpointFragment("1", "date_part");
        GeneralFunction.replaceFunctions(Map.of("DATE_PART", 1));
        GeneralBinaryOperator.getFragments().clearFragments();
        GeneralBinaryOperator.getFragments().loadCheckpointFragment("DATE", "=");
        GeneralBinaryOperator.replaceOperators(Map.of("=", GeneralSchema.GeneralCompositeDataType.getByName("DATE")));
        GeneralSchema.replaceTypeToFunction(Map.of("DATE", List.of("date_part")));
        GeneralSchema.replaceTypeAvailability(Map.of("DATE", true));

        Path checkpoint = Files.createTempFile("shqvel-checkpoint-", ".json");
        GeneralLearnedState.save(state, checkpoint.toString());

        GeneralSchema.resetLearnedTypes();
        GeneralFunction.getFragments().clearFragments();
        GeneralFunction.replaceFunctions(Map.of());
        GeneralBinaryOperator.getFragments().clearFragments();
        GeneralBinaryOperator.replaceOperators(Map.of());

        options.loadLearnedFragments = checkpoint.toString();
        GeneralLearnedState.loadOnce(state, checkpoint.toString(), true);

        assertEquals(1, GeneralSchema.getFragments().getFragments().get("DATE").size());
        assertEquals(Integer.valueOf(1), GeneralFunction.getFunctions().get("DATE_PART"));
        assertEquals(1, GeneralFunction.getFragments().getFragments().get("1").size());
        assertEquals("DATE", GeneralBinaryOperator.getOperators().get("=").toString());
        assertEquals(List.of("date_part"), GeneralSchema.getAvailFunctions("DATE"));
        assertTrue(GeneralSchema.getTypeAvailabilitySnapshot().get("DATE"));
        assertFalse(options.isLearningEnabled(SQLFeature.DATATYPE));
        assertFalse(options.isLearningEnabled(SQLFeature.FUNCTION));
        assertFalse(options.isLearningEnabled(SQLFeature.OPERATOR));

        options.loadLearnedFragments = "";
        options.resumeLearnedFragments = checkpoint.toString();
        assertTrue(options.isLearningEnabled(SQLFeature.DATATYPE));
        assertTrue(options.isLearningEnabled(SQLFeature.FUNCTION));
        assertTrue(options.isLearningEnabled(SQLFeature.OPERATOR));
        GeneralLearnedState.loadOnce(state, checkpoint.toString(), false);
        assertEquals(Integer.valueOf(1), GeneralFunction.getFunctions().get("DATE_PART"));

        options.loadLearnedFragments = checkpoint.toString();
        assertThrows(IllegalArgumentException.class, options::getLearnedFragmentCheckpointInput);

        Files.deleteIfExists(checkpoint);
    }
}
