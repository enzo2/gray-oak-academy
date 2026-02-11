> ## Documentation Index
> Fetch the complete documentation index at: https://exa.ai/docs/llms.txt
> Use this file to discover all available pages before exploring further.

# Contents

> Get the full page contents, summaries, and metadata for a list of URLs.

Returns instant results from our cache, with automatic live crawling as fallback for uncached pages.

***

<Card title="Get your Exa API key" icon="key" horizontal href="https://dashboard.exa.ai/api-keys" />


## OpenAPI

````yaml post /contents
openapi: 3.1.0
info:
  version: 1.2.0
  title: Exa Search API
  description: >-
    A comprehensive API for internet-scale search, allowing users to perform
    queries and retrieve results from a wide variety of sources using
    embeddings-based and traditional search.
servers:
  - url: https://api.exa.ai
security:
  - apikey: []
paths:
  /contents:
    post:
      summary: Get Contents
      operationId: getContents
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              allOf:
                - type: object
                  properties:
                    urls:
                      type: array
                      description: >-
                        Array of URLs to crawl (backwards compatible with 'ids'
                        parameter).
                      items:
                        type: string
                      example:
                        - https://arxiv.org/pdf/2307.06435
                      default:
                        - https://arxiv.org/pdf/2307.06435
                    ids:
                      type: array
                      description: Array of document IDs obtained from searches.
                      items:
                        type: string
                      example:
                        - https://arxiv.org/pdf/2307.06435
                  required:
                    - urls
                - $ref: '#/components/schemas/ContentsRequest'
      responses:
        '200':
          $ref: '#/components/responses/ContentsResponse'
components:
  schemas:
    ContentsRequest:
      type: object
      properties:
        text:
          oneOf:
            - type: boolean
              title: Simple text retrieval
              description: >-
                If true, returns full page text with default settings. If false,
                disables text return.
            - type: object
              title: Advanced text options
              description: >-
                Advanced options for controlling text extraction. Use this when
                you need to limit text length or include HTML structure.
              properties:
                maxCharacters:
                  type: integer
                  description: >-
                    Maximum character limit for the full page text. Useful for
                    controlling response size and API costs.
                  example: 1000
                includeHtmlTags:
                  type: boolean
                  default: false
                  description: >-
                    Include HTML tags in the response, which can help LLMs
                    understand text structure and formatting.
                  example: false
                verbosity:
                  type: string
                  enum:
                    - compact
                    - standard
                    - full
                  default: compact
                  description: >
                    Controls the verbosity level of returned content. Requires
                    livecrawl: "always" to take effect.

                    - compact: Most concise output, main content only (default)

                    - standard: Balanced content with more detail

                    - full: Complete content including all sections
                  example: standard
                includeSections:
                  type: array
                  items:
                    type: string
                    enum:
                      - header
                      - navigation
                      - banner
                      - body
                      - sidebar
                      - footer
                      - metadata
                  description: >
                    Only include content from these semantic page sections.
                    Requires livecrawl: "always" to take effect.
                  example:
                    - body
                    - header
                excludeSections:
                  type: array
                  items:
                    type: string
                    enum:
                      - header
                      - navigation
                      - banner
                      - body
                      - sidebar
                      - footer
                      - metadata
                  description: >
                    Exclude content from these semantic page sections. Requires
                    livecrawl: "always" to take effect.
                  example:
                    - navigation
                    - footer
                    - sidebar
        highlights:
          oneOf:
            - type: boolean
              title: Simple highlights retrieval
              description: >-
                If true, returns highlights with default settings. If false,
                disables highlights.
            - type: object
              title: Advanced highlights options
              description: >-
                Advanced options for controlling highlight extraction. Use this
                when you need to customize the number of sentences, highlights
                per URL, or provide a custom query.
              properties:
                numSentences:
                  type: integer
                  minimum: 1
                  description: The number of sentences to return for each snippet.
                  example: 1
                highlightsPerUrl:
                  type: integer
                  minimum: 1
                  description: The number of snippets to return for each result.
                  example: 1
                query:
                  type: string
                  description: Custom query to direct the LLM's selection of highlights.
                  example: Key advancements
          description: Text snippets the LLM identifies as most relevant from each page.
          properties:
            maxCharacters:
              type: integer
              minimum: 1
              description: >-
                Maximum number of characters to return for highlights. Controls
                the total length of highlight text returned per URL.
              example: 2000
            numSentences:
              type: integer
              minimum: 1
              description: >-
                Deprecated: use maxCharacters instead. The number of sentences
                to return for each snippet.
              example: 1
              deprecated: true
            highlightsPerUrl:
              type: integer
              minimum: 1
              description: >-
                Deprecated: use maxCharacters instead. The number of snippets to
                return for each result.
              deprecated: true
            query:
              type: string
              description: Custom query to direct the LLM's selection of highlights.
              example: Key advancements
        summary:
          type: object
          description: Summary of the webpage
          properties:
            query:
              type: string
              description: Custom query for the LLM-generated summary.
              example: Main developments
            schema:
              type: object
              description: >
                JSON schema for structured output from summary. 

                See https://json-schema.org/overview/what-is-jsonschema for JSON
                Schema documentation.
              example:
                $schema: http://json-schema.org/draft-07/schema#
                title: Title
                type: object
                properties:
                  Property 1:
                    type: string
                    description: Description
                  Property 2:
                    type: string
                    enum:
                      - option 1
                      - option 2
                      - option 3
                    description: Description
                required:
                  - Property 1
        livecrawl:
          type: string
          enum:
            - never
            - fallback
            - preferred
            - always
          deprecated: true
          description: >
            **Deprecated**: Use `maxAgeHours` instead for more precise control
            over content freshness.


            Options for livecrawling pages.

            'never': Disable livecrawling (default for neural search).

            'fallback': Livecrawl when cache is empty.

            'preferred': Always try to livecrawl, but fall back to cache if
            crawling fails.

            'always': Always live-crawl, never use cache. Only use if you cannot
            tolerate any cached content. This option is not recommended unless
            consulted with the Exa team.
          example: preferred
        livecrawlTimeout:
          type: integer
          default: 10000
          description: The timeout for livecrawling in milliseconds.
          example: 1000
        maxAgeHours:
          type: integer
          description: >
            Maximum age of cached content in hours. Controls when livecrawling
            is triggered based on content freshness.

            - Positive value (e.g. 24): Use cached content if it's less than
            this many hours old, otherwise livecrawl.

            - 0: Always livecrawl, never use cache.

            - -1: Never livecrawl, always use cache.

            - Omit (default): Livecrawl as fallback only when no cached content
            exists.
          example: 24
        subpages:
          type: integer
          default: 0
          description: >-
            The number of subpages to crawl. The actual number crawled may be
            limited by system constraints.
          example: 1
        subpageTarget:
          oneOf:
            - type: string
            - type: array
              items:
                type: string
          description: >-
            Term to find specific subpages of search results. Can be a single
            string or an array of strings, comma delimited.
          example: sources
        extras:
          type: object
          description: Extra parameters to pass.
          properties:
            links:
              type: integer
              default: 0
              description: Number of URLs to return from each webpage.
              example: 1
            imageLinks:
              type: integer
              default: 0
              description: Number of images to return for each result.
              example: 1
        context:
          oneOf:
            - type: boolean
              deprecated: true
              description: >-
                Deprecated: Use highlights or text instead. Returns page
                contents as a combined context string.
              example: true
            - type: object
              deprecated: true
              description: >-
                Deprecated: Use highlights or text instead. Returns page
                contents as a combined context string.
              properties:
                maxCharacters:
                  type: integer
                  description: Deprecated. Maximum character limit for the context string.
                  example: 10000
    ResultWithContent:
      allOf:
        - $ref: '#/components/schemas/Result'
        - type: object
          properties:
            text:
              type: string
              description: The full content text of the search result.
              example: >-
                Abstract Large Language Models (LLMs) have recently demonstrated
                remarkable capabilities...
            highlights:
              type: array
              items:
                type: string
              description: Array of highlights extracted from the search result content.
              example:
                - Such requirements have limited their adoption...
            highlightScores:
              type: array
              items:
                type: number
                format: float
              description: Array of cosine similarity scores for each highlighted
              example:
                - 0.4600165784358978
            summary:
              type: string
              description: Summary of the webpage
              example: >-
                This overview paper on Large Language Models (LLMs) highlights
                key developments...
            subpages:
              type: array
              items:
                $ref: '#/components/schemas/ResultWithContent'
              description: Array of subpages for the search result.
              example:
                - id: https://arxiv.org/abs/2303.17580
                  url: https://arxiv.org/pdf/2303.17580.pdf
                  title: >-
                    HuggingGPT: Solving AI Tasks with ChatGPT and its Friends in
                    Hugging Face
                  author: >-
                    Yongliang  Shen, Microsoft Research Asia, Kaitao  Song,
                    Microsoft Research Asia, Xu  Tan, Microsoft Research Asia,
                    Dongsheng  Li, Microsoft Research Asia, Weiming  Lu,
                    Microsoft Research Asia, Yueting  Zhuang, Microsoft Research
                    Asia, yzhuang@zju.edu.cn, Zhejiang  University, Microsoft
                    Research Asia, Microsoft  Research, Microsoft Research Asia
                  publishedDate: '2023-11-16T01:36:20.486Z'
                  text: >-
                    HuggingGPT: Solving AI Tasks with ChatGPT and its Friends in
                    Hugging Face Date Published: 2023-05-25 Authors: Yongliang
                    Shen, Microsoft Research Asia Kaitao Song, Microsoft
                    Research Asia Xu Tan, Microsoft Research Asia Dongsheng Li,
                    Microsoft Research Asia Weiming Lu, Microsoft Research Asia
                    Yueting Zhuang, Microsoft Research Asia, yzhuang@zju.edu.cn
                    Zhejiang University, Microsoft Research Asia Microsoft
                    Research, Microsoft Research Asia Abstract Solving
                    complicated AI tasks with different domains and modalities
                    is a key step toward artificial general intelligence. While
                    there are abundant AI models available for different domains
                    and modalities, they cannot handle complicated AI tasks.
                    Considering large language models (LLMs) have exhibited
                    exceptional ability in language understanding, generation,
                    interaction, and reasoning, we advocate that LLMs could act
                    as a controller to manage existing AI models to solve
                    complicated AI tasks and language could be a generic
                    interface to empower t
                  summary: >-
                    HuggingGPT is a framework using ChatGPT as a central
                    controller to orchestrate various AI models from Hugging
                    Face to solve complex tasks. ChatGPT plans the task, selects
                    appropriate models based on their descriptions, executes
                    subtasks, and summarizes the results. This approach
                    addresses limitations of LLMs by allowing them to handle
                    multimodal data (vision, speech) and coordinate multiple
                    models for complex tasks, paving the way for more advanced
                    AI systems.
                  highlights:
                    - >-
                      2) Recently, some researchers started to investigate the
                      integration of using tools or models in LLMs  .
                  highlightScores:
                    - 0.32679107785224915
            extras:
              type: object
              description: Results from extras.
              properties:
                links:
                  type: array
                  items:
                    type: string
                  description: Array of links from the search result.
                  example: []
    CostDollars:
      type: object
      properties:
        total:
          type: number
          format: float
          description: Total dollar cost for your request
          example: 0.005
        breakDown:
          type: array
          description: Breakdown of costs by operation type
          items:
            type: object
            properties:
              search:
                type: number
                format: float
                description: Cost of your search operations
                example: 0.005
              contents:
                type: number
                format: float
                description: Cost of your content operations
                example: 0
              breakdown:
                type: object
                properties:
                  neuralSearch:
                    type: number
                    format: float
                    description: Cost of your neural search operations
                    example: 0.005
                  deepSearch:
                    type: number
                    format: float
                    description: Cost of your deep search operations
                    example: 0.015
                  contentText:
                    type: number
                    format: float
                    description: Cost of your text content retrieval
                    example: 0
                  contentHighlight:
                    type: number
                    format: float
                    description: Cost of your highlight generation
                    example: 0
                  contentSummary:
                    type: number
                    format: float
                    description: Cost of your summary generation
                    example: 0
        perRequestPrices:
          type: object
          description: Standard price per request for different operations
          properties:
            neuralSearch_1_25_results:
              type: number
              format: float
              description: Standard price for neural search with 1-25 results
              example: 0.005
            neuralSearch_26_100_results:
              type: number
              format: float
              description: Standard price for neural search with 26-100 results
              example: 0.025
            neuralSearch_100_plus_results:
              type: number
              format: float
              description: Standard price for neural search with 100+ results
              example: 1
            deepSearch_1_25_results:
              type: number
              format: float
              description: Standard price for deep search with 1-25 results
              example: 0.015
            deepSearch_26_100_results:
              type: number
              format: float
              description: Standard price for deep search with 26-100 results
              example: 0.075
        perPagePrices:
          type: object
          description: Standard price per page for different content operations
          properties:
            contentText:
              type: number
              format: float
              description: Standard price per page for text content
              example: 0.001
            contentHighlight:
              type: number
              format: float
              description: Standard price per page for highlights
              example: 0.001
            contentSummary:
              type: number
              format: float
              description: Standard price per page for summaries
              example: 0.001
    Result:
      type: object
      properties:
        title:
          type: string
          description: The title of the search result.
          example: A Comprehensive Overview of Large Language Models
        url:
          type: string
          format: uri
          description: The URL of the search result.
          example: https://arxiv.org/pdf/2307.06435.pdf
        publishedDate:
          type: string
          nullable: true
          description: >-
            An estimate of the creation date, from parsing HTML content. Format
            is YYYY-MM-DD.
          example: '2023-11-16T01:36:32.547Z'
        author:
          type: string
          nullable: true
          description: If available, the author of the content.
          example: >-
            Humza  Naveed, University of Engineering and Technology (UET),
            Lahore, Pakistan
        id:
          type: string
          description: The temporary ID for the document. Useful for /contents endpoint.
          example: https://arxiv.org/abs/2307.06435
        image:
          type: string
          format: uri
          description: The URL of an image associated with the search result, if available.
          example: https://arxiv.org/pdf/2307.06435.pdf/page_1.png
        favicon:
          type: string
          format: uri
          description: The URL of the favicon for the search result's domain.
          example: https://arxiv.org/favicon.ico
  responses:
    ContentsResponse:
      description: OK
      content:
        application/json:
          schema:
            type: object
            properties:
              requestId:
                type: string
                description: Unique identifier for the request
                example: e492118ccdedcba5088bfc4357a8a125
              results:
                type: array
                items:
                  $ref: '#/components/schemas/ResultWithContent'
              context:
                type: string
                description: >-
                  Deprecated. Combined context string from search results. Use
                  highlights or text instead.
              statuses:
                type: array
                description: Status information for each requested URL
                items:
                  type: object
                  properties:
                    id:
                      type: string
                      description: The URL that was requested
                      example: https://example.com
                    status:
                      type: string
                      enum:
                        - success
                        - error
                      description: Status of the content fetch operation
                      example: success
                    error:
                      type: object
                      nullable: true
                      description: Error details, only present when status is "error"
                      properties:
                        tag:
                          type: string
                          enum:
                            - CRAWL_NOT_FOUND
                            - CRAWL_TIMEOUT
                            - CRAWL_LIVECRAWL_TIMEOUT
                            - SOURCE_NOT_AVAILABLE
                            - UNSUPPORTED_URL
                            - CRAWL_UNKNOWN_ERROR
                          description: Specific error type
                          example: CRAWL_NOT_FOUND
                        httpStatusCode:
                          type: integer
                          nullable: true
                          description: The corresponding HTTP status code
                          example: 404
              costDollars:
                $ref: '#/components/schemas/CostDollars'
  securitySchemes:
    apikey:
      type: apiKey
      name: x-api-key
      in: header
      description: >-
        API key can be provided either via x-api-key header or Authorization
        header with Bearer scheme

````

> 

# Contents Best Practices

> Best practices for using Exa's Contents API

The Contents API extracts clean, LLM-ready content from any URL—handling JavaScript-rendered pages, PDFs, and complex layouts automatically. Get full page text, targeted highlights, structured summaries, or crawl entire site sections in a single request.

## Key Benefits

* **Clean markdown extraction**: Automatically filters out navigation, ads, and boilerplate to return only the main content, formatted as clean markdown.
* **Flexible content modes**: Choose between full text, query-relevant highlights, or LLM-generated summaries—or combine them in one request.
* **Subpage crawling**: Automatically discover and extract content from linked pages within a site, with targeted filtering to focus on specific sections.

## Request Fields

The `ids` parameter (list of URLs) is required. All other fields are optional. See the [API Reference](/reference/get-contents) for complete parameter specifications.

| Field            | Type      | Notes                                                                                                                                   | Example                                                         |
| ---------------- | --------- | --------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------- |
| ids              | string\[] | List of URLs to extract content from.                                                                                                   | \["[https://example.com/article](https://example.com/article)"] |
| text             | bool/obj  | Return full page text as markdown. Can specify `maxCharacters` and `includeHtmlTags`.                                                   | `true` or `{"maxCharacters": 5000}`                             |
| highlights       | bool/obj  | Return key excerpts most relevant to a query. Can specify `maxCharacters` and custom `query`.                                           | `{"query": "main findings", "maxCharacters": 2000}`             |
| highlights       | bool      | Return key excerpts most relevant to your query.                                                                                        | `true`                                                          |
| maxAgeHours      | int       | Maximum age of indexed content in hours. If older, fetches with livecrawl. `0` = always livecrawl, `-1` = never livecrawl (cache only). | 24                                                              |
| livecrawlTimeout | int       | Timeout in milliseconds for live crawling. Recommended: 10000-15000.                                                                    | 12000                                                           |
| subpages         | int       | Maximum number of subpages to crawl from each URL.                                                                                      | 5                                                               |
| subpageTarget    | string\[] | Keywords to prioritize when selecting subpages.                                                                                         | \["docs", "about", "pricing"]                                   |
| summary          | bool/obj  | Return LLM-generated summary. Can specify custom `query` and JSON `schema` for structured extraction.                                   | `{"query": "Key takeaways"}`                                    |
| context          | bool/obj  | **Deprecated.** Use `highlights` or `text` instead. Returns all results combined into a single string. Can specify `maxCharacters`.     | `true` or `{"maxCharacters": 10000}`                            |

## Content Extraction Options

### Text

Returns the full page content as clean markdown.

```json  theme={null}
{
  "ids": ["https://arxiv.org/abs/2301.07041"],
  "text": true
}
```

With character limit and HTML preservation:

```json  theme={null}
{
  "ids": ["https://arxiv.org/abs/2301.07041"],
  "text": {
    "maxCharacters": 8000,
    "includeHtmlTags": true
  }
}
```

### Highlights

Returns key excerpts from the page that are most relevant to your query. These are extractive (pulled directly from the source), not generated.

```json  theme={null}
{
  "ids": ["https://example.com/research-paper"],
  "highlights": {
    "query": "methodology and results",
    "maxCharacters": 2000
  }
}
```

### Summary

Returns an LLM-generated abstract tailored to your specific query. Supports JSON schema for structured extraction.

```json  theme={null}
{
  "ids": ["https://example.com/company-page"],
  "summary": {
    "query": "Extract company information",
    "schema": {
      "type": "object",
      "properties": {
        "name": { "type": "string" },
        "industry": { "type": "string" },
        "founded": { "type": "number" }
      },
      "required": ["name", "industry"]
    }
  }
}
```

## Token Efficiency

Choosing the right content mode can significantly reduce token usage while maintaining answer quality.

| Mode       | Best For                                                                 |
| ---------- | ------------------------------------------------------------------------ |
| text       | Deep analysis, when you need full context, comprehensive research        |
| highlights | Factual questions, specific lookups, multi-step agent workflows          |
| summary    | Quick overviews, structured extraction, when you control the output size |

**Use highlights for agentic workflows**: When building multi-step agents that make repeated content extraction calls, highlights provide the most relevant excerpts without flooding context windows. Configure with `maxCharacters` to control output size.

```json  theme={null}
{
  "ids": ["https://example.com/article"],
  "highlights": {
    "query": "key findings",
    "maxCharacters": 2000
  }
}
```

**Use full text for deep analysis**: When the task requires comprehensive understanding or when you're unsure which parts of the page matter, request full text. Use `maxCharacters` to cap token usage.

```json  theme={null}
{
  "ids": ["https://arxiv.org/abs/2301.07041"],
  "text": { "maxCharacters": 20000 }
}
```

**Combine modes strategically**: You can request multiple content types together—use highlights for quick answers and include full text only when deeper analysis is needed.

## Content Freshness

Control whether to return cached content (faster) or fetch fresh content from the source using `maxAgeHours`.

| Value    | Behavior                                                    | Best For                                        |
| -------- | ----------------------------------------------------------- | ----------------------------------------------- |
| `24`     | Use cache if less than 24 hours old, otherwise livecrawl    | Daily-fresh content                             |
| `1`      | Use cache if less than 1 hour old, otherwise livecrawl      | Near real-time data                             |
| `0`      | Always livecrawl (ignore cache entirely)                    | Real-time data where cached content is unusable |
| `-1`     | Never livecrawl (cache only)                                | Maximum speed, historical/static content        |
| *(omit)* | Default behavior (livecrawl as fallback if no cache exists) | **Recommended** — balanced speed and freshness  |

Most use cases work well with the default (omit `maxAgeHours`). Only set it when you have specific freshness requirements. If you do, pair with an explicit `livecrawlTimeout` (10000-15000ms).

```json  theme={null}
{
  "ids": ["https://www.apple.com/newsroom/"],
  "maxAgeHours": 24,
  "livecrawlTimeout": 6000,
  "text": true
}
```

## Subpage Crawling

Automatically discover and extract content from linked pages within a website.

```json  theme={null}
{
  "ids": ["https://docs.example.com"],
  "subpages": 10,
  "subpageTarget": ["api", "reference", "guide"],
  "text": true
}
```

**Parameters**:

* `subpages`: Maximum number of subpages to crawl per URL
* `subpageTarget`: Keywords to prioritize when selecting which subpages to crawl

**Best practices**:

1. Start with a smaller `subpages` value (5-10) and increase if needed
2. Use specific `subpageTarget` terms to focus on relevant sections
3. Combine with `maxAgeHours` for fresh results

### Example: Documentation Crawling

```json  theme={null}
{
  "ids": ["https://platform.openai.com/docs"],
  "subpages": 15,
  "subpageTarget": ["api", "models", "embeddings"],
  "maxAgeHours": 24,
  "livecrawlTimeout": 15000,
  "text": { "maxCharacters": 5000 }
}
```

### Example: Company Research

```json  theme={null}
{
  "ids": ["https://stripe.com"],
  "subpages": 8,
  "subpageTarget": ["about", "careers", "press", "blog"],
  "summary": { "query": "Company overview, culture, and recent news" }
}
```

## Error Handling

The Contents API returns detailed status information for each URL in the `statuses` field. The endpoint only returns an error for internal issues—individual URL failures are reported per-URL.

```json  theme={null}
{
  "results": [...],
  "statuses": [
    {
      "id": "https://example.com",
      "status": "success"
    },
    {
      "id": "https://example.com/broken",
      "status": "error",
      "error": {
        "tag": "CRAWL_NOT_FOUND",
        "httpStatusCode": 404
      }
    }
  ]
}
```

**Error tags**:

* `CRAWL_NOT_FOUND`: Content not found (404)
* `CRAWL_TIMEOUT`: Target page timed out (408)
* `CRAWL_LIVECRAWL_TIMEOUT`: `livecrawlTimeout` limit reached
* `SOURCE_NOT_AVAILABLE`: Access forbidden (403)
* `CRAWL_UNKNOWN_ERROR`: Other errors (500+)

Always check the `statuses` array to handle failures gracefully:

```python  theme={null}
result = exa.get_contents(["https://example.com", "https://example.com/maybe-broken"])
for status in result.statuses:
    if status.status == "error":
        print(f"Failed: {status.id} - {status.error.tag}")
```
