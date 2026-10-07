defmodule CookielessAudiences do
  @moduledoc """
  Client for the Cookieless Audiences API: page-level audience segmentation
  and IAB content categorization. No cookies, no personal data.

      client = CookielessAudiences.new(System.fetch_env!("COOKIELESS_KEY"))
      {:ok, page} = CookielessAudiences.segment(client, "https://example.com/blog")
  """

  @base "https://www.cookielessaudiences.com"

  @status_text %{
    400 => "bad request, check the parameters",
    401 => "invalid API key",
    403 => "key not active or monthly credits used up",
    407 => "missing data_type, must be url or text",
    410 => "not enough content in the page or text",
    411 => "the URL content could not be fetched",
    500 => "general error, check the request or contact support"
  }

  defstruct [:api_key, timeout: 120_000]

  @type t :: %__MODULE__{api_key: String.t(), timeout: pos_integer()}

  @doc "Builds a client."
  def new(api_key, opts \\ []) when is_binary(api_key) do
    %__MODULE__{api_key: api_key, timeout: Keyword.get(opts, :timeout, 120_000)}
  end

  @doc "Structured audience profile for a URL. Pass `structured: false` for the legacy shape."
  def segment(%__MODULE__{} = c, url, opts \\ []) do
    form = [{"query", url}, {"api_key", c.api_key}]
    form = if Keyword.get(opts, :structured, true), do: form ++ [{"format", "structured"}], else: form
    post(c, "/api/audience/segment.php", form)
  end

  @doc "IAB content categories for a URL."
  def categorize(%__MODULE__{} = c, url, opts \\ []) do
    form = [{"query", url}, {"api_key", c.api_key}, {"data_type", "url"}]
    form = if Keyword.get(opts, :confidence, true), do: form ++ [{"confidence", "1"}], else: form

    form =
      if Keyword.get(opts, :root_fallback, false),
        do: form ++ [{"use_domain_as_basis_of_categorization_for_insufficient_subdomain_content", "1"}],
        else: form

    post(c, "/api/iab/iab_web_content_filtering.php", form)
  end

  @doc "IAB content categories for plain text."
  def categorize_text(%__MODULE__{} = c, text) do
    post(c, "/api/iab/iab_content_filtering.php", [
      {"query", text},
      {"api_key", c.api_key},
      {"data_type", "text"},
      {"confidence", "1"}
    ])
  end

  @doc "Public vocabularies, no key needed."
  def vocabularies(timeout \\ 60_000) do
    case request(:get, {String.to_charlist(@base <> "/api/audience/filters.php"), headers()}, timeout) do
      {:ok, body} -> Jason.decode(body)
      error -> error
    end
  end

  @doc "Readable names for the INT.* and PI.* codes of a structured response."
  def labels_for(result) when is_map(result) do
    names = Map.get(result, "labels", %{})

    for group <- ["interests", "purchase_intent"],
        key <- ["tier1", "tier2", "codes"],
        code <- get_in(result, [group, key]) || [] do
      Map.get(names, code, code)
    end
  end

  defp headers do
    [{~c"user-agent", ~c"cookielessaudiences-elixir/1.0.0 (+https://www.cookielessaudiences.com)"}]
  end

  defp post(c, path, form) do
    body = URI.encode_query(form)
    req = {String.to_charlist(@base <> path), headers(), ~c"application/x-www-form-urlencoded", body}

    with {:ok, raw} <- request(:post, req, c.timeout),
         {:ok, json} <- Jason.decode(raw) do
      case Map.get(json, "status", 200) do
        200 -> {:ok, json}
        status -> {:error, %{status: status, message: Map.get(@status_text, status, "API error"), body: json}}
      end
    end
  end

  defp request(method, req, timeout) do
    http_opts = [timeout: timeout, ssl: [verify: :verify_peer, cacerts: :public_key.cacerts_get(), depth: 3,
                 customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]]]

    case :httpc.request(method, req, http_opts, body_format: :binary) do
      {:ok, {{_, _code, _}, _headers, body}} -> {:ok, body}
      {:error, reason} -> {:error, %{status: 0, message: inspect(reason)}}
    end
  end
end
