defmodule CookielessAudiences.MixProject do
  use Mix.Project

  def project do
    [
      app: :cookielessaudiences,
      version: "1.0.1",
      elixir: "~> 1.14",
      description: "Elixir client for the Cookieless Audiences API: page-level audience segmentation and IAB categorization with no cookies and no PII.",
      package: package(),
      deps: deps(),
      docs: [main: "readme", extras: ["README.md"]],
      source_url: "https://github.com/explainableaixai/cookielessaudiences-elixir",
      homepage_url: "https://www.cookielessaudiences.com"
    ]
  end

  def application, do: [extra_applications: [:logger, :inets, :ssl, :public_key]]

  defp deps do
    [{:jason, "~> 1.4"}, {:ex_doc, "~> 0.34", only: :dev, runtime: false}]
  end

  defp package do
    [
      licenses: ["MIT"],
      files: ~w(lib mix.exs README.md CHANGELOG.md LICENSE),
      links: %{
        "Homepage" => "https://www.cookielessaudiences.com",
        "API reference" => "https://www.cookielessaudiences.com/api.php",
        "GitHub" => "https://github.com/explainableaixai/cookielessaudiences-elixir"
      }
    ]
  end
end
