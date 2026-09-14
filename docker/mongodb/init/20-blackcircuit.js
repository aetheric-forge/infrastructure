const databaseName = "blackcircuit";
const database = db.getSiblingDB(databaseName);

const webUsername = process.env.MONGO_BLACKCIRCUIT_WEB_USERNAME;
const webPassword = process.env.MONGO_BLACKCIRCUIT_WEB_PASSWORD;
if (!database.getUser(webUsername)) {
    database.createUser({
        user: webUsername,
        pwd: webPassword,
        roles: [{ role: "read", db: databaseName }],
    });
}

const adminUsername = process.env.MONGO_BLACKCIRCUIT_ADMIN_USERNAME;
const adminPassword = process.env.MONGO_BLACKCIRCUIT_ADMIN_PASSWORD;
if (!database.getUser(adminUsername)) {
    database.createUser({
        user: adminUsername,
        pwd: adminPassword,
        roles: [{ role: "readWrite", db: databaseName }],
    });
}
