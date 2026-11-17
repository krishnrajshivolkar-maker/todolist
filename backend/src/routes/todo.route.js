const express = require("express")
const createlist = require("../controllers/todo.contoller")

const router = express.Router()

router.post("/create", createlist)

module.exports = router