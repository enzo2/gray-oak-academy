> ## Documentation Index
> Fetch the complete documentation index at: https://exa.ai/docs/llms.txt
> Use this file to discover all available pages before exploring further.

# Answer

> Get an LLM answer to a question informed by Exa search results. `/answer` performs an Exa search and uses an LLM to generate either:
1. A direct answer for specific queries. (i.e. "What is the capital of France?" would return "Paris")
2. A detailed summary with citations for open-ended queries (i.e. "What is the state of ai in healthcare?" would return a summary with citations to relevant sources)

The response includes both the generated answer and the sources used to create it. The endpoint also supports streaming (as `stream=True`), which will return tokens as they are generated.

Alternatively, you can use the OpenAI compatible [chat completions interface](https://docs.exa.ai/reference/chat-completions#answer).


<Card title="Get your Exa API key" icon="key" horizontal href="https://dashboard.exa.ai/api-keys" />

<Info>
  `/answer` supports structured output via the `outputSchema` parameter. Pass a [JSON Schema](https://json-schema.org/draft-07) object and the answer will be returned as structured JSON matching your schema instead of a plain string.
</Info>


## OpenAPI

````yaml post /answer
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
  /answer:
    post:
      summary: Generate an answer from search results
      description: >
        Performs a search based on the query and generates either a direct
        answer or a detailed summary with citations, depending on the query
        type.
      operationId: answer
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required:
                - query
              properties:
                query:
                  type: string
                  description: The question or query to answer.
                  example: What is the latest valuation of SpaceX?
                  default: What is the latest valuation of SpaceX?
                  minLength: 1
                stream:
                  type: boolean
                  default: false
                  description: >-
                    If true, the response is returned as a server-sent events
                    (SSS) stream.
                text:
                  type: boolean
                  default: false
                  description: >-
                    If true, the response includes full text content in the
                    search results
                outputSchema:
                  type: object
                  description: >-
                    A [JSON Schema Draft 7](https://json-schema.org/draft-07)
                    specification for the desired answer structure. When
                    provided, the answer will be returned as a structured object
                    matching the schema instead of a plain string.
                  properties:
                    type:
                      type: string
                      description: The root schema type (typically "object").
                      example: object
                    properties:
                      type: object
                      description: >-
                        An object where each key is a property name and each
                        value is a JSON Schema describing that property (with
                        `type`, `description`, etc).
                    required:
                      type: array
                      items:
                        type: string
                      description: List of required property names.
                    description:
                      type: string
                      description: A description of the schema.
                    additionalProperties:
                      type: boolean
                      description: Whether to allow properties not listed in `properties`.
                      default: false
      responses:
        '200':
          $ref: '#/components/responses/AnswerResponse'
components:
  responses:
    AnswerResponse:
      description: OK
      content:
        application/json:
          schema:
            allOf:
              - $ref: '#/components/schemas/AnswerResult'
              - type: object
                properties:
                  costDollars:
                    $ref: '#/components/schemas/CostDollars'
        text/event-stream:
          schema:
            type: object
            properties:
              answer:
                type: string
                description: Partial answer chunk when streaming is enabled.
              citations:
                type: array
                items:
                  $ref: '#/components/schemas/AnswerCitation'
  schemas:
    AnswerResult:
      type: object
      properties:
        answer:
          oneOf:
            - type: string
            - type: object
              additionalProperties: {}
          description: >-
            The generated answer based on search results. Returns a string by
            default, or a structured object matching the provided outputSchema.
          example: $350 billion.
        citations:
          type: array
          description: Search results used to generate the answer.
          items:
            $ref: '#/components/schemas/AnswerCitation'
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
    AnswerCitation:
      type: object
      properties:
        id:
          type: string
          description: The temporary ID for the document.
          example: >-
            https://www.theguardian.com/science/2024/dec/11/spacex-valued-at-350bn-as-company-agrees-to-buy-shares-from-employees
        url:
          type: string
          format: uri
          description: The URL of the search result.
          example: >-
            https://www.theguardian.com/science/2024/dec/11/spacex-valued-at-350bn-as-company-agrees-to-buy-shares-from-employees
        title:
          type: string
          description: The title of the search result.
          example: SpaceX valued at $350bn as company agrees to buy shares from ...
        author:
          type: string
          nullable: true
          description: If available, the author of the content.
          example: Dan Milmon
        publishedDate:
          type: string
          nullable: true
          description: >-
            An estimate of the creation date, from parsing HTML content. Format
            is YYYY-MM-DD.
          example: '2023-11-16T01:36:32.547Z'
        text:
          type: string
          description: >-
            The full text content of each source. Only present when includeText
            is enabled.
          example: SpaceX valued at $350bn as company agrees to buy shares from ...
        image:
          type: string
          format: uri
          description: >-
            The URL of the image associated with the search result, if
            available.
          example: >-
            https://i.guim.co.uk/img/media/7cfee7e84b24b73c97a079c402642a333ad31e77/0_380_6176_3706/master/6176.jpg?width=1200&height=630&quality=85&auto=format&fit=crop&overlay-align=bottom%2Cleft&overlay-width=100p&overlay-base64=L2ltZy9zdGF0aWMvb3ZlcmxheXMvdGctZGVmYXVsdC5wbmc&enable=upscale&s=71ebb2fbf458c185229d02d380c01530
        favicon:
          type: string
          format: uri
          description: The URL of the favicon for the search result's domain, if available.
          example: >-
            https://assets.guim.co.uk/static/frontend/icons/homescreen/apple-touch-icon.svg
  securitySchemes:
    apikey:
      type: apiKey
      name: x-api-key
      in: header
      description: >-
        API key can be provided either via x-api-key header or Authorization
        header with Bearer scheme

````