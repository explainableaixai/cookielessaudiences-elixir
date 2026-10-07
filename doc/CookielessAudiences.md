# `CookielessAudiences`
[🔗](https://github.com/explainableaixai/cookielessaudiences-elixir/blob/main/lib/cookielessaudiences.ex#L1)

Client for the Cookieless Audiences API: page-level audience segmentation
and IAB content categorization. No cookies, no personal data.

    client = CookielessAudiences.new(System.fetch_env!("COOKIELESS_KEY"))
    {:ok, page} = CookielessAudiences.segment(client, "https://example.com/blog")

# `t`

```elixir
@type t() :: %CookielessAudiences{api_key: String.t(), timeout: pos_integer()}
```

# `categorize`

IAB content categories for a URL.

# `categorize_text`

IAB content categories for plain text.

# `labels_for`

Readable names for the INT.* and PI.* codes of a structured response.

# `new`

Builds a client.

# `segment`

Structured audience profile for a URL. Pass `structured: false` for the legacy shape.

# `vocabularies`

Public vocabularies, no key needed.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
