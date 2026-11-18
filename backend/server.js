const dns = require("dns");
const colo = require("colo");
const path = require("path");

// Load environment variables from backend/.env
require('dotenv').config({ path: path.join(__dirname, '.env') });

dns.setServers(["8.8.8.8", "8.8.4.4"]);

const app = require("./src/app");
const ConnectToMongo = require("./src/db/db");

ConnectToMongo();

const PORT = process.env.PORT || 3000;

app.listen(PORT, '0.0.0.0', () => {
    console.log(colo.green(`Server running on port ${PORT}`));
});
