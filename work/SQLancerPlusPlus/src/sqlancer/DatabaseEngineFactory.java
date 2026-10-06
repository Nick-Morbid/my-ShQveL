package sqlancer;

import java.sql.Connection;
import java.sql.SQLException;

public interface DatabaseEngineFactory<G extends GlobalState<?, ?, ?>> {
    String getJDBCString(G globalState);

    Connection cleanOrSetUpDatabase(G globalState, String databaseName) throws SQLException;

    void syncData(G globalState) throws SQLException;

    boolean isNewSchema();
}
