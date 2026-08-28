const databaseName = "forge-campus";
const username = process.env.MONGO_FORGE_CAMPUS_USERNAME;
const password = process.env.MONGO_FORGE_CAMPUS_PASSWORD;
const database = db.getSiblingDB(databaseName);

if (!database.getUser(username)) {
    database.createUser({
        user: username,
        pwd: password,
        roles: [{ role: "readWrite", db: databaseName }]
    });
}

if (!database.getCollectionNames().includes("bootstrap")) {
    database.createCollection("bootstrap");
}
