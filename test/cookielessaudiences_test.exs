defmodule CookielessAudiencesTest do
  use ExUnit.Case

  test "labels_for resolves codes and keeps unknown ones" do
    r = %{
      "interests" => %{"tier1" => ["INT.a"]},
      "purchase_intent" => %{"codes" => ["PI.b", "PI.c"]},
      "labels" => %{"INT.a" => "A", "PI.b" => "B"}
    }

    assert CookielessAudiences.labels_for(r) == ["A", "B", "PI.c"]
  end

  test "new builds a client" do
    assert %CookielessAudiences{api_key: "k", timeout: 120_000} = CookielessAudiences.new("k")
  end
end
