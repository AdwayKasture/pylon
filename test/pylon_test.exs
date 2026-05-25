defmodule PylonTest do
  use ExUnit.Case
  doctest Pylon

  test "greets the world" do
    assert Pylon.hello() == :world
  end
end
