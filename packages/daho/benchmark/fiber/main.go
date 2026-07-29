// Go Fiber equivalent of packages/daho/example/daho_example.dart — same
// /json route, same response body, no logging/extra middleware, used purely
// as a comparison point in .github/workflows/benchmark.yml.
//
// Prefork: true enables Fiber's built-in multi-process clustering (forks one
// OS process per core, sharing the listening socket via SO_REUSEPORT) —
// matches Daho's default one-worker-Isolate-per-core model, and shelf's
// manual shared:true isolate clustering in the sibling benchmark, so none of
// the three is unfairly stuck on a single core.
//
// Run:  go run main.go
// Test: curl http://127.0.0.1:8083/json
package main

import "github.com/gofiber/fiber/v2"

func main() {
	app := fiber.New(fiber.Config{DisableStartupMessage: true, Prefork: true})

	app.Get("/json", func(c *fiber.Ctx) error {
		return c.JSON(fiber.Map{
			"status": "ok",
			"items":  []int{1, 2, 3},
		})
	})

	println("Fiber running at http://127.0.0.1:8083")
	if err := app.Listen(":8083"); err != nil {
		panic(err)
	}
}
