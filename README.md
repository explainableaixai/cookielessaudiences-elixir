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

<!--expanded-->
## OTP patterns that suit this API

Elixir programs are built from processes, and a good integration uses them. The client itself is a plain struct with functions, which is the right foundation. Around it you can add a cache process, a rate limiter and a supervisor, each small and each testable.

A cache is the first one most teams need. Audience profiles change slowly, so a GenServer holding recent answers saves credits and time:

```elixir
defmodule MyApp.AudienceCache do
  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def fetch(url) do
    GenServer.call(__MODULE__, {:fetch, url}, 130_000)
  end

  @impl true
  def init(opts), do: {:ok, %{client: CookielessAudiences.new(opts[:key]), table: %{}}}

  @impl true
  def handle_call({:fetch, url}, _from, state) do
    key = url |> String.trim() |> String.downcase()

    case Map.fetch(state.table, key) do
      {:ok, {stored_at, page}} when stored_at > System.system_time(:second) - 14 * 86_400 ->
        {:reply, {:ok, page}, state}

      _ ->
        case CookielessAudiences.segment(state.client, url) do
          {:ok, page} ->
            table = Map.put(state.table, key, {System.system_time(:second), page})
            {:reply, {:ok, page}, %{state | table: table}}

          error ->
            {:reply, error, state}
        end
    end
  end
end
```

For production traffic, move the table into ETS so that reads do not serialize through one process. Keep writes in the GenServer so that two callers asking for the same URL do not both pay for it.

## Supervision

Put the cache under your application supervisor. If it crashes, it restarts empty and the next calls refill it. That is a safe failure mode, because the data can always be fetched again. Put long running batch work under a `Task.Supervisor` so a single bad URL cannot take down the rest of the run.

## Rate limiting

The service tolerates many parallel requests, but you should still protect your own budget. A simple token bucket process that hands out permits at a fixed rate is enough. Wrap each call in a permit request, and let the bucket slow you down instead of letting the service return errors. A rate limiter you control is more predictable than backoff after the fact.

## Telemetry

The BEAM has a strong convention for instrumentation, and it is worth following. Emit a telemetry event around each call with the duration and the outcome, then attach handlers that feed your metrics system. Useful tags are the status code and whether the answer came from the cache. With those two tags, a dashboard can show hit rate, error rate and latency without any further code.

## Livebook for exploration

Livebook is a pleasant way to explore audience data. Install the dependency in a notebook, paste a list of URLs, call `Task.async_stream` and render the results as a table. Analysts who do not write Elixir every day can still adjust the list and re-run cells. Keep the key in a Livebook secret instead of in the notebook text, and the file stays safe to share.

## Using the output in Phoenix

A Phoenix application can show an audience summary beside any page you store. Fetch the profile in a background job when a page is added, store the whole map in a `jsonb` column, and index `audience_type` and the interest codes. Queries such as "all pages whose tier one interests include technology and whose income band is upper middle" then become ordinary SQL. The coded vocabularies are what make this practical, because a code means the same thing every time.

## Related reading

The [guide to contextual versus behavioral targeting](https://www.cookielessaudiences.com/features/contextual-vs-behavioral-targeting.php) explains why reading the page is a sound basis for audience work and how it compares with following users.

The same company runs other APIs that Elixir teams often meet in the same project. The [job title normalization endpoint](https://www.resumereaderapi.com/normalization/job-titles.php) turns messy role names into canonical titles with a seniority level and a job function, which is handy when you join audience data with account lists. For go to market teams the [B2B growth team guide](https://www.acquisitionuniverse.com/for/b2b-gtm-teams.php) describes how an ideal customer profile can be screened across the whole web.

## Troubleshooting

**`{:error, %{status: 403}}`.** The key is not active, or the credits are used up.

**`{:error, %{status: 0, message: ...}}`.** A transport problem, such as a timeout or a TLS failure. Retry with backoff.

**Certificate errors.** The client uses the OTP certificate store. Make sure your runtime has current OTP and system certificates.

**`Jason.DecodeError`.** The server returned something that was not JSON. Log the raw body once to see what a proxy did.

## Compatibility

The library needs Elixir 1.14 or later. It relies on `:httpc` and `:public_key` from OTP and on Jason for JSON. It starts no processes of its own.

<!--extra-->
## Operations checklist

Run this short list before an Elixir service built on the library goes live. Is the key loaded at runtime from the environment? Does every batch set both a concurrency limit and a timeout? Do you handle `{:error, %{status: 403}}` by alerting a person instead of retrying? Does the cache store the vocabulary version beside each answer? Do your tests use a fake transport for ordinary cases and one live call to the public vocabularies endpoint for contract checks? Can you replay a day of input without paying twice? If every answer is yes, the integration is in good shape, and the remaining work is about what you do with the data.

Think about the people who will read the output too. A planner wants labels, not codes. A data scientist wants the codes and the version. A manager wants a summary. Store the raw map once and produce each of those views from it, so the three audiences never disagree about what the service returned.

Keep a small mix task in the project that segments one URL and pretty prints the whole response. When someone asks why a page was labelled a certain way, you can answer in a minute, and that shortens every conversation about data quality.

<!--further-->
## Further reading and practical notes

The [Elixir language site](https://elixir-lang.org/) links to the guides for processes, supervision and tasks, and the [Elixir documentation on HexDocs](https://hexdocs.pm/elixir/) is the reference for `Task`, `GenServer`, `Supervisor` and the `Stream` module that the examples above lean on.

Some notes from practice. Keep the client struct in your application environment or in a supervised process, not in a module attribute, so that a key rotation does not need a recompile. When you call `Task.async_stream`, always set both `max_concurrency` and `timeout`, and decide what happens on timeout. The default of killing the whole stream is rarely what you want for a batch where one slow page should not stop the rest. Prefer `on_timeout: :kill_task` and record the miss.

Emit a telemetry event around every call with two tags, the status and whether the answer came from your cache. That gives you hit rate, error rate and latency from one source. Use the same event names in tests so that assertions on metrics are easy to write.

Finally, remember the shape of the data. The structured response uses coded vocabularies, so the cleanest storage is a `jsonb` column plus a few extracted columns for the fields you filter on most. Resist the urge to normalise it into twenty tables. The codes already do that work for you.

## Questions

**Does it depend on Req or Finch?** No. It uses `:httpc` from OTP, so the only package is Jason.

**Which Elixir?** 1.14 or later. TLS verification uses the OTP trust store.

**License?** MIT. info@alpha-quantum.com
