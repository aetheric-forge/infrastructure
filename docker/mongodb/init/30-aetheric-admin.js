const maintenanceDatabaseName = "maintenance";
const maintenanceDatabase = db.getSiblingDB(maintenanceDatabaseName);

const maintenanceUsername = process.env.MONGO_MAINTENANCE_USERNAME;
const maintenancePassword = process.env.MONGO_MAINTENANCE_PASSWORD;
if (!maintenanceDatabase.getUser(maintenanceUsername)) {
    maintenanceDatabase.createUser({
        user: maintenanceUsername,
        pwd: maintenancePassword,
        roles: [{ role: "readWrite", db: maintenanceDatabaseName }],
    });
}

// Shared between aetheric-web (creates and reviews Join Campus applications) and
// aetheric-admin (StaleMembershipApplicationsWorker reads/flags them) via the
// aetheric-contracts submodule both apps consume. Same asymmetric-role pattern as
// 20-blackcircuit.js, with the read/write sides swapped: here aetheric-web owns the
// create/review workflow, so it gets readWrite and aetheric-admin gets read.
const membershipDatabaseName = "aetheric-membership";
const membershipDatabase = db.getSiblingDB(membershipDatabaseName);

const membershipWebUsername = process.env.MONGO_AETHERIC_MEMBERSHIP_WEB_USERNAME;
const membershipWebPassword = process.env.MONGO_AETHERIC_MEMBERSHIP_WEB_PASSWORD;
if (!membershipDatabase.getUser(membershipWebUsername)) {
    membershipDatabase.createUser({
        user: membershipWebUsername,
        pwd: membershipWebPassword,
        roles: [{ role: "readWrite", db: membershipDatabaseName }],
    });
}

const membershipAdminUsername = process.env.MONGO_AETHERIC_MEMBERSHIP_ADMIN_USERNAME;
const membershipAdminPassword = process.env.MONGO_AETHERIC_MEMBERSHIP_ADMIN_PASSWORD;
if (!membershipDatabase.getUser(membershipAdminUsername)) {
    membershipDatabase.createUser({
        user: membershipAdminUsername,
        pwd: membershipAdminPassword,
        roles: [{ role: "read", db: membershipDatabaseName }],
    });
}
