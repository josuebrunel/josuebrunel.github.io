---
title: "Simple Concurrent Web Scraping in Go with Geziyor, GoQuery, and Headless Chrome"
date: 2024-10-17
author: "Josué"
tags: ["golang", "scraping", "web"]
---

Web scraping is a powerful technique for extracting data from websites, and Go provides excellent tools for this task. In this blog post, we'll explore how to use the Geziyor library along with GoQuery and headless Chrome to create efficient, concurrent web scrapers in Go.

We'll use Geziyor for its powerful scraping capabilities and built-in concurrency, GoQuery for HTML parsing, and headless Chrome for JavaScript rendering.

## TLDR: source code

## Installation

To get started, install Geziyor using the following command:

```bash
go get github.com/geziyor/geziyor
```

Geziyor includes GoQuery as a dependency, so it will be installed automatically.

## Scraping a Simple HTML Page

Let's begin with a simple example of scraping a static HTML page. Geziyor uses *exporter* (interface) to export parsed data. We will define a generic type *DataExporter* that will help us export data of any type.

```go
// DataExporter is a generic struct that can export data of any type.
type DataExporter[T any] struct {
	Data []T
}

// Export adds scraped data to the DataExporter's Data slice.
// It receives data through a channel and appends it to the Data slice.
func (de *DataExporter[T]) Export(scraped chan any) error {
	if len(de.Data) == 0 {
		de.Data = []T{}
	}
	for pd := range scraped {
		d := pd.(T)
		de.Data = append(de.Data, d)
	}
	return nil
}
```

Now, let's scrape quotes from http://quotes.toscrape.com/:

```go
// AutherNText represents a quote with its author and text.
type AutherNText struct {
	Author string `json:"author"`
	Text   string `json:"text"`
}

// quotesParse is a parsing function for quote pages.
// It extracts author and text information from each quote on the page,
// exports the data as AutherNText structs, and follows pagination links.
func quotesParse(g *geziyor.Geziyor, r *client.Response) {
	// Find all quote elements and process each one
	r.HTMLDoc.Find("div.quote").Each(func(i int, s *goquery.Selection) {
		// Extract author and text from the quote
		g.Exports <- AutherNText{
			Author: s.Find("small.author").Text(),
			Text:   s.Find("span.text").Text(),
		}
	})

	// Check for a "next" pagination link
	if href, ok := r.HTMLDoc.Find("li.next > a").Attr("href"); ok {
		// If found, follow the link and continue parsing
		g.Get(r.JoinURL(href), quotesParse)
	}
}

func main() {
    exporter := DataExporter[AutherNText]{}
    g := geziyor.NewGeziyor(&geziyor.Options{
        StartURLs: []string{"http://quotes.toscrape.com/"},
        ParseFunc: quotesParse,
        Exporters: []export.Exporter{&exporter},
    })
    g.Start()
    slog.Info("Quotes scraped", "count", len(exporter.Data))
}
```

As you can see, we just need to define:
- A data structure to hold our data
- A function to parse the HTML page
- A Geziyor instance

## Concurrent Scraping

By providing multiple start URLs, we can take advantage of Geziyor's built-in concurrency. Geziyor will scrape these URLs concurrently, significantly speeding up the scraping process when dealing with multiple pages.

```go
// Turtle represents a turtle species with its name, description, and image URL.
type Turtle struct {
	Name        string `json:"name"`
	Description string `json:"description"`
	Image       string `json:"image"`
}

// turtleScraper is a parsing function for turtle family pages.
// It extracts the turtle's name, description, and image URL from the HTML
// and exports the data as a Turtle struct.
func turtleScraper(g *geziyor.Geziyor, r *client.Response) {
	g.Exports <- Turtle{
		Name:        r.HTMLDoc.Find(".turtle-family-detail > h3").Text(),
		Description: r.HTMLDoc.Find(".turtle-family-detail > p").Text(),
		Image:       r.HTMLDoc.Find(".turtle-family-detail > img").AttrOr("src", ""),
	}
}

func main() {
    turtleExporter := DataExporter[Turtle]{}
    urls := []string{
        "https://www.scrapethissite.com/pages/frames/?frame=i&family=Cheloniidae",
        "https://www.scrapethissite.com/pages/frames/?frame=i&family=Chelydridae",
        "https://www.scrapethissite.com/pages/frames/?frame=i&family=Carettochelyidae",
    }
    
    g := geziyor.NewGeziyor(&geziyor.Options{
        StartURLs: urls,
        ParseFunc: turtleScraper,
        Exporters: []export.Exporter{&turtleExporter},
    })
    g.Start()
    
    slog.Info("Turtle information scraped", "count", len(turtleExporter.Data))
}
```

In this code, the only new *Option* is the *StartURLS* one. The *parsing function* will be concurrently called for each URL in *StartURLS*.

## Scraping JavaScript-Rendered Pages

In this final part, we'll tackle the challenge of scraping JavaScript-rendered content from AliExpress. This example demonstrates how to use Geziyor with a headless Chrome browser to scrape dynamic web pages. We will need to have a headless Chrome instance running:

```bash
docker run -d -p 9222:9222 --rm --name headless-shell chromedp/headless-shell
```

Here's an example of how to use a headless browser and manage JS rendered pages:

```go
// AliExpressProduct represents a product from AliExpress with its name and price.
type AliExpressProduct struct {
	Name  string `json:"name"`
	Price string `json:"price"`
}

// aliexpressProduct is a parsing function for AliExpress product pages.
// It extracts the product title and price from the rendered HTML and exports
// the data as an AliExpressProduct struct.
// Note: This function uses JavaScript rendering to access dynamic content.
func aliexpressProduct(g *geziyor.Geziyor, r *client.Response) {
	// Extract the product title from the h1 element with data-pl="product-title"
	title := r.HTMLDoc.Find("h1[data-pl=product-title]").Text()

	// Extract the product price from the span element with class "product-price-value"
	price := r.HTMLDoc.Find("span.product-price-value").Text()

	// Export the extracted data as an AliExpressProduct struct
	g.Exports <- AliExpressProduct{Name: title, Price: price}
}

func main() {
    aliExport := DataExporter[AliExpressProduct]{}
    urls := []string{
        "https://www.aliexpress.com/item/1005006959851087.html",
        "https://www.aliexpress.com/item/1005007265735821.html",
    }
    
    g := geziyor.NewGeziyor(&geziyor.Options{
        StartRequestsFunc: func(g *geziyor.Geziyor) {
            var wg sync.WaitGroup
            for _, url := range urls {
                wg.Add(1)
                go func(url string) {
                    defer wg.Done()
                    g.GetRendered(url, aliexpressProduct)
                }(url)
            }
            wg.Wait()
        },
        Exporters:       []export.Exporter{&aliExport},
        BrowserEndpoint: "ws://127.0.0.1:9222",
    })
    g.Start()
    
    slog.Info("AliExpress products scraped", "count", len(aliExport.Data))
}
```

## Key Points

- **Headless Chrome**: By setting the `BrowserEndpoint` option, we tell Geziyor to use our headless Chrome instance for rendering JavaScript.
- **GetRendered**: Instead of the regular `Get` method, we use `GetRendered` to ensure JavaScript is executed before scraping.
- **Manual Concurrency**: We implement manual concurrency using goroutines and a WaitGroup. This gives us fine-grained control over the scraping process.
- **Error Handling**: In a production environment, you'd want to add error handling and potentially implement retries for failed requests.

## Conclusion

Geziyor, combined with GoQuery and headless Chrome, provides a powerful toolkit for web scraping in Go. From simple static pages to complex, JavaScript-rendered content, these tools can handle a wide range of scraping tasks efficiently and concurrently.

Remember to use web scraping responsibly and ethically, respecting the terms of service of the websites you're scraping and considering the load your scraper puts on their servers.

Happy scraping!
