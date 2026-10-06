package sqlancer;

public interface Reproducer<G extends GlobalState<?, ?, ?>> {
    boolean bugStillTriggers(G globalState);

    default String getErrorMessage() {
        return "";
    };
}
