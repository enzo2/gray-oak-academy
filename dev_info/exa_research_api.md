> ## Documentation Index
> Fetch the complete documentation index at: https://exa.ai/docs/llms.txt
> Use this file to discover all available pages before exploring further.

# Exa Research

> Automate in-depth web research with structured output support.

## How It Works

The Research API is an **asynchronous, multi-step pipeline** that transforms open-ended questions into grounded reports. You provide natural-language instructions (e.g. *"Compare the hardware roadmaps of the top GPU manufacturers"*) and an optional JSON Schema describing the output you want.

Under the hood, Exa agents perform multiple steps:

1. **Planning** – Your natural-language `instructions` are parsed by an LLM that decomposes the task into one or more research steps.

2. **Searching** – Specialized search agents issue semantic queries to Exa's search engine, continuously expanding and refining the result set until they can fulfil the request.

3. **Reasoning & synthesis** – Reasoning models combine facts across sources and return structured JSON (if you provide `outputSchema`) or a detailed markdown report.

Because tasks are **asynchronous**, you submit a request and immediately receive a `researchId`. You can [poll the request](/reference/research/get-a-task) until it is complete or failed, or [list all tasks](/reference/research/list-tasks) to monitor progress in bulk.

## Best Practices

* **Be explicit** – Clear, scoped instructions lead to faster tasks and higher-quality answers. You should describe (1) what information you want (2) how the agent should find that information and (3) how the agent should compose it's final report.
* **Keep schemas small** – 1-5 root fields is the sweet spot. If you need more, create multiple tasks.
* **Use enums** – Tight schema constraints improve accuracy and reduce hallucinations.

## Models

The Research API offers two advanced agentic researcher models that break down your instructions, search the web, extract and reason over facts, and return structured answers with citations.

* **exa-research** (default) adapts to the difficulty of the task, using more or less compute for individual steps. Recommended for most use cases.
* **exa-research-pro** maximizes quality by using the highest reasoning capability for every step. Recommended for the most complex, multi-step research tasks.

Here are typical completion times for each model:

| Model            | p50 (seconds) | p90 (seconds) |
| ---------------- | ------------- | ------------- |
| exa-research     | 45            | 90            |
| exa-research-pro | 90            | 180           |

## Pricing

The Research API now uses **variable usage-based pricing**. You are billed based on how much work and reasoning the research agent does.

<Note>You are ONLY charged for tasks that complete successfully.</Note>

| Operation            | exa-research      | exa-research-pro   | Notes                                                |
| -------------------- | ----------------- | ------------------ | ---------------------------------------------------- |
| **Search**           | \$5/1k searches   | \$5/1k searches    | Each unique search query issued by the agent         |
| **Page read**        | \$5/1k pages read | \$10/1k pages read | One "page" = 1,000 tokens from the web               |
| **Reasoning tokens** | \$5/1M tokens     | \$5/1M tokens      | Specific LLM tokens used for reasoning and synthesis |

**Example:**\
A research task with `exa-research` that performs 6 searches, reads 20 pages of content, and uses 1,000 reasoning tokens would cost:

$$
\begin{array}{rl}
& \$0.03 \text{ (6 searches × \$5/1000)} \\
+ & \$0.10 \text{ (20 pages × \$5/1000)} \\
+ & \$0.005 \text{ (1{,}000 reasoning tokens × \$5/1{,}000{,}000)} \\
\hline
& \$0.135
\end{array}
$$

For `exa-research-pro`, the same task would cost:

$$
\begin{array}{rl}
& \$0.03 \text{ (6 searches × \$5/1000)} \\
+ & \$0.20 \text{ (20 pages × \$10/1000)} \\
+ & \$0.005 \text{ (1{,}000 reasoning tokens × \$5/1{,}000{,}000)} \\
\hline
& \$0.235
\end{array}
$$

## Examples

### Competitive Landscape Table

Compare the current flagship GPUs from NVIDIA, AMD, and Intel and extract pricing, TDP, and release date.

<CodeGroup>
  ```python Python theme={null}
  import os
  from exa_py import Exa

  exa = Exa(os.environ["EXA_API_KEY"])

  instructions = "Compare the current flagship GPUs from NVIDIA, AMD and Intel. Return a table of model name, MSRP USD, TDP watts, and launch date. Include citations for each cell."
  schema = {
      "type": "object",
      "required": ["gpus"],
      "properties": {
          "gpus": {
              "type": "array",
              "items": {
                  "type": "object",
                  "required": ["manufacturer", "model", "msrpUsd", "tdpWatts", "launchDate"],
                  "properties": {
                      "manufacturer": {"type": "string"},
                      "model": {"type": "string"},
                      "msrpUsd": {"type": "number"},
                      "tdpWatts": {"type": "integer"},
                      "launchDate": {"type": "string"}
                  }
              }
          }
      },
      "additionalProperties": False
  }

  research = exa.research.create(
      model="exa-research",
      instructions=instructions,
      output_schema=schema
  )

  # Poll until completion
  result = exa.research.poll_until_finished(research.researchId)
  print(result)
  ```

  ```javascript JavaScript theme={null}
  import Exa, { ResearchModel } from "exa-js";

  const exa = new Exa(process.env.EXA_API_KEY);

  async function compareGPUs() {
    const research = await exa.research.create({
      model: ResearchModel.exa_research,
      instructions:
        "Compare the current flagship GPUs from NVIDIA, AMD and Intel. Return a table of model name, MSRP USD, TDP watts, and launch date. Include citations for each cell.",
      outputSchema: {
        type: "object",
        required: ["gpus"],
        properties: {
          gpus: {
            type: "array",
            items: {
              type: "object",
              required: [
                "manufacturer",
                "model",
                "msrpUsd",
                "tdpWatts",
                "launchDate",
              ],
              properties: {
                manufacturer: { type: "string" },
                model: { type: "string" },
                msrpUsd: { type: "number" },
                tdpWatts: { type: "integer" },
                launchDate: { type: "string" },
              },
            },
          },
        },
        additionalProperties: false,
      },
    });

    // Poll until completion
    const result = await exa.research.pollUntilFinished(research.researchId);
    console.log("Research result:", result);
  }

  compareGPUs();
  ```

  ```bash Curl theme={null}
  curl -X POST https://api.exa.ai/research/v1 \
    -H "x-api-key: $EXA_API_KEY" \
    -H "Content-Type: application/json" \
    -d '{
      "instructions": "Compare the current flagship GPUs from NVIDIA, AMD and Intel. Return a table of model name, MSRP USD, TDP watts, and launch date. Include citations for each cell.",
      "outputSchema": {
        "type": "object",
        "required": ["gpus"],
        "properties": {
          "gpus": {
            "type": "array",
            "items": {
              "type": "object",
              "required": ["manufacturer", "model", "msrpUsd", "tdpWatts", "launchDate"],
              "properties": {
                "manufacturer": {"type": "string"},
                "model": {"type": "string"},
                "msrpUsd": {"type": "number"},
                "tdpWatts": {"type": "integer"},
                "launchDate": {"type": "string"}
              }
            }
          }
        },
        "additionalProperties": false
      }
    }'
  ```
</CodeGroup>

### Market Size Estimate

Estimate the total global market size (USD) for battery recycling in 2030 with a clear methodology.

<CodeGroup>
  ```python Python theme={null}
  import os
  from exa_py import Exa

  exa = Exa(os.environ["EXA_API_KEY"])

  instructions = "Estimate the global market size for battery recycling in 2030. Provide reasoning steps and cite sources."
  schema = {
      "type": "object",
      "required": ["estimateUsd", "methodology"],
      "properties": {
          "estimateUsd": {"type": "number"},
          "methodology": {"type": "string"}
      },
      "additionalProperties": False
  }

  research = exa.research.create(
      model="exa-research",
      instructions=instructions,
      output_schema=schema
  )

  # Poll until completion
  result = exa.research.poll_until_finished(research.researchId)
  print(result)
  ```

  ```javascript JavaScript theme={null}
  import Exa, { ResearchModel } from "exa-js";

  const exa = new Exa(process.env.EXA_API_KEY);

  async function estimateMarketSize() {
    const research = await exa.research.create({
      model: ResearchModel.exa_research,
      instructions:
        "Estimate the global market size for battery recycling in 2030. Provide reasoning steps and cite sources.",
      outputSchema: {
        type: "object",
        required: ["estimateUsd", "methodology"],
        properties: {
          estimateUsd: { type: "number" },
          methodology: { type: "string" },
        },
        additionalProperties: false,
      },
    });

    // Poll until completion
    const result = await exa.research.pollUntilFinished(research.researchId);
    console.log("Research result:", result);
  }

  estimateMarketSize();
  ```

  ```bash Curl theme={null}
  curl -X POST https://api.exa.ai/research/v1 \
    -H "x-api-key: $EXA_API_KEY" \
    -H "Content-Type: application/json" \
    -d '{
      "instructions": "Estimate the global market size for battery recycling in 2030. Provide reasoning steps and cite sources.",
      "outputSchema": {
        "type": "object",
        "required": ["estimateUsd", "methodology"],
        "properties": {
          "estimateUsd": {"type": "number"},
          "methodology": {"type": "string"}
        },
        "additionalProperties": false
      }
    }'
  ```
</CodeGroup>

### Timeline of Key Events

Build a timeline of major OpenAI product releases from 2015 – 2023.

<CodeGroup>
  ```python Python theme={null}
  import os
  from exa_py import Exa

  exa = Exa(os.environ["EXA_API_KEY"])

  instructions = "Create a chronological timeline (year, month, brief description) of major OpenAI product releases from 2015 to 2023."
  schema = {
      "type": "object",
      "required": ["events"],
      "properties": {
          "events": {
              "type": "array",
              "items": {
                  "type": "object",
                  "required": ["date", "description"],
                  "properties": {
                      "date": {"type": "string"},
                      "description": {"type": "string"}
                  }
              }
          }
      },
      "additionalProperties": False
  }

  research = exa.research.create(
      model="exa-research",
      instructions=instructions,
      output_schema=schema
  )

  # Poll until completion
  result = exa.research.poll_until_finished(research.researchId)
  print(result)
  ```

  ```javascript JavaScript theme={null}
  import Exa, { ResearchModel } from "exa-js";

  const exa = new Exa(process.env.EXA_API_KEY);

  async function createTimeline() {
    const research = await exa.research.create({
      model: ResearchModel.exa_research,
      instructions:
        "Create a chronological timeline (year, month, brief description) of major OpenAI product releases from 2015 to 2023.",
      outputSchema: {
        type: "object",
        required: ["events"],
        properties: {
          events: {
            type: "array",
            items: {
              type: "object",
              required: ["date", "description"],
              properties: {
                date: { type: "string" },
                description: { type: "string" },
              },
            },
          },
        },
        additionalProperties: false,
      },
    });

    // Poll until completion
    const result = await exa.research.pollUntilFinished(research.researchId);
    console.log("Research result:", result);
  }

  createTimeline();
  ```

  ```bash Curl theme={null}
  curl -X POST https://api.exa.ai/research/v1 \
    -H "x-api-key: $EXA_API_KEY" \
    -H "Content-Type: application/json" \
    -d '{
      "instructions": "Create a chronological timeline (year, month, brief description) of major OpenAI product releases from 2015 to 2023.",
      "outputSchema": {
        "type": "object",
        "required": ["events"],
        "properties": {
          "events": {
            "type": "array",
            "items": {
              "type": "object",
              "required": ["date", "description"],
              "properties": {
                "date": {"type": "string"},
                "description": {"type": "string"}
              }
            }
          }
        },
        "additionalProperties": false
      }
    }'
  ```
</CodeGroup>

## FAQs

<AccordionGroup>
  <Accordion title="Who is the Research API for?">
    Product teams, analysts, researchers, and anyone who needs **structured answers** that require reading multiple web sources — without having to build their own search + scraping + LLM pipeline.
  </Accordion>

  <Accordion title="How is this different from the /answer endpoint?">
    `/answer` is designed for **single-shot Q\&A**. The Research API handles
    **long-running, multi-step investigations**. It's suitable for tasks that
    require complex reasoning over web data.
  </Accordion>

  <Accordion title="How long do tasks take?">
    Tasks generally complete in 20–40 seconds. Simple tasks that can be solved
    with few searches complete faster, while complex schema's targeting niche
    subjects may take longer.
  </Accordion>

  <Accordion title="What are best practices for writing instructions?">
    Be explicit about the objective and any constraints - Specify the **time
    range** or **types of sources** to consult if important - Use imperative verbs
    ("Compare", "List", "Summarize") - Keep it under 4096 characters
  </Accordion>

  <Accordion title="How large can my output schema be?">
    You must have ≤ 8 root fields. It must not be more than 5 fields deep.
  </Accordion>

  <Accordion title="What happens if my schema validation fails?">
    If your schema is not valid, an error will surface *before the task is
    created* with a message about what is invalid. You will not be charged for
    such requests.
  </Accordion>
</AccordionGroup>
