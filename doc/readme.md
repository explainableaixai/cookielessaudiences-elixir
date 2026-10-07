# cookielessaudiences for Elixir

Turn a URL into an audience profile from Elixir. The library calls the Cookieless Audiences API with OTP's built-in HTTP client and decodes the answer with Jason. Nothing is tracked, and no personal data is read.

## Mix dependency

```elixir
def deps do
  [{:cookielessaudiences, "~> 1.0"}]
end
```

## Usage in iex

```elixir
iex> client = CookielessAudiences.new(System.fetch_env!("COOKIELESS_KEY"))
iex> {:ok, page} = CookielessAudiences.segment(client, "https://example.com/blog")
iex> page["audience_type"]
"b2b"
iex> CookielessAudiences.labels_for(page)
["Technology & Computing", "Computing", "Computer Software"]
```

Every function returns `{:ok, map}` or `{:error, %{status: integer, message: string}}`.

## Functions

- `new(key, timeout: 120_000)`
- `segment(client, url, structured: true)`
- `categorize(client, url, confidence: true, root_fallback: false)`
- `categorize_text(client, text)`
- `vocabularies()`: public, needs no key
- `labels_for(result)`: readable names for the coded values

## Pattern match on failures

```elixir
case CookielessAudiences.segment(client, url) do
  {:ok, page} -> store(url, page)
  {:error, %{status: 403}} -> {:halt, :no_credits}
  {:error, %{status: s}} when s in [410, 411] -> :skip
  {:error, other} -> Logger.warning("segment failed: #{inspect(other)}")
end
```

The `status` is read from the JSON body. HTTP is not used to signal errors.

## Concurrent batch with Task.async_stream

```elixir
urls
|> Task.async_stream(&CookielessAudiences.segment(client, &1), max_concurrency: 8, timeout: 130_000)
|> Enum.zip(urls)
|> Enum.map(fn
  {{:ok, {:ok, page}}, url} -> {url, page["audience_type"]}
  {_, url} -> {url, :failed}
end)
```

Back-pressure is built in. Raise `max_concurrency` once you know your plan.

## Phoenix controller idea

```elixir
def show(conn, %{"url" => url}) do
  case CookielessAudiences.segment(conn.assigns.client, url) do
    {:ok, page} -> json(conn, Map.take(page, ["audience_type", "demographics", "interests"]))
    {:error, e} -> conn |> put_status(502) |> json(e)
  end
end
```

Cache the answer in ETS or Cachex; pages change slowly.

## Where the data is used

Teams building deal packages work from the inventory side. The [ad inventory curation](https://www.cookielessaudiences.com/features/ad-inventory-curation.php) feature page describes how coded interests turn a pile of domains into a package a buyer can understand.

## Questions

**Does it depend on Req or Finch?** No. It uses `:httpc` from OTP, so the only package is Jason.

**Which Elixir?** 1.14 or later. TLS verification uses the OTP trust store.

**License?** MIT. info@alpha-quantum.com
