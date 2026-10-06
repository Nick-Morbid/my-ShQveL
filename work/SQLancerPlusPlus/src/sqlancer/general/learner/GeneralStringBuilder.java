package sqlancer.general.learner;

import sqlancer.Randomly;
import sqlancer.general.GeneralProvider.GeneralGlobalState;

public class GeneralStringBuilder<E extends GeneralFragments> {

    private final StringBuilder sb;
    private final E fragments;
    private final GeneralGlobalState state;
    private final boolean couldRandom;

    public GeneralStringBuilder(GeneralGlobalState globalState, E fragments) {
        this.sb = new StringBuilder();
        this.state = globalState;
        this.fragments = fragments;
        this.couldRandom = true;
    }

    public GeneralStringBuilder(GeneralGlobalState globalState, E fragments, boolean couldRandom) {
        this.sb = new StringBuilder();
        this.state = globalState;
        this.fragments = fragments;
        this.couldRandom = couldRandom;
    }

    public void append(String str) {
        sb.append(str);
    }

    public void append(Object obj) {
        sb.append(obj);
    }

    public void append(Object obj, int index) {
        sb.append(obj);
        if (fragments.getLearn() || !couldRandom || Randomly.getBoolean()) {
            String fragment = fragments.get(index, state);
            fragment = state.replaceTestObject(fragment);
            sb.append(fragment);
        }
    }

    @Override
    public String toString() {
        return sb.toString();
    }
}
