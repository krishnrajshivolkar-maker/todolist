const Todo = require("../models/todo.model")

async function createlist(req, res) {
    try {

        const { title, description } = req.body

        const data = await Todo.create({
            title: title,
            description: description
        })

        return res.status(201).json({
            message: "Listed Success",
            sucess: true,
            data
        })

    } catch (error) {
        return res.status(404).json({
            message: "Error in creating list",
            sucess: false
        })
    }
}

module.exports = createlist