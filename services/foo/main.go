package main

import (
	"log"

	"github.com/gofiber/fiber/v2"
)

func main() {
	app := fiber.New()

	app.Get("/pass", func(c *fiber.Ctx) error {
		return c.SendString("Foo Service!")
	})

	app.Get("/fail", func(c *fiber.Ctx) error {
		return c.SendStatus(fiber.StatusInternalServerError)
	})

	log.Fatal(app.Listen(":3000"))
}
