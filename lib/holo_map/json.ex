defmodule HoloMap.JSON do
  @moduledoc """
  A small JSON encoder that runs in the browser.

  Every component specification travels from Elixir to MapLibre as a JSON
  string in a DOM attribute, and that string has to be produced during
  *client-side* re-renders as well as during server-side rendering. Hologram
  compiles a well-defined subset of Elixir to JavaScript, and `Jason`, which
  leans on Erlang primitives and protocols outside that subset, is not part of
  it. So `HoloMap` carries its own encoder, written only in constructs the
  Hologram client runtime supports.

  It handles exactly what a MapLibre style specification contains: strings,
  integers, floats, booleans, `nil`, atoms, lists and maps. Anything else
  raises `ArgumentError` rather than being silently coerced. A struct or a
  tuple reaching this function means the calling component built a spec it did
  not intend to.

  ## Examples

      iex> HoloMap.JSON.encode(%{"fill-color" => "#f00", "fill-opacity" => 0.5})
      ~s({"fill-color":"#f00","fill-opacity":0.5})

      iex> HoloMap.JSON.encode(["get", "name"])
      ~s(["get","name"])

      iex> HoloMap.JSON.encode(nil)
      "null"

  Map keys are emitted in sorted order. That is not cosmetic: the reconciler
  compares the previous and current attribute strings to decide whether a
  MapLibre call is needed, and Erlang map iteration order is not stable across
  builds. Sorting makes an unchanged spec encode to an unchanged string.
  """

  @doc """
  Encodes `value` as a JSON string.

  Raises `ArgumentError` for terms with no JSON representation.
  """
  @spec encode(term()) :: String.t()
  def encode(nil), do: "null"
  def encode(true), do: "true"
  def encode(false), do: "false"
  def encode(value) when is_binary(value), do: encode_string(value)
  def encode(value) when is_integer(value), do: Integer.to_string(value)
  def encode(value) when is_float(value), do: Float.to_string(value)
  def encode(value) when is_atom(value), do: encode_string(Atom.to_string(value))

  # Structs are maps, so they would otherwise fall into the map clause and be
  # encoded with their `__struct__` field, or, when they are also Enumerable
  # (a Range, a MapSet), fail obscurely inside the list clause. A struct in a
  # map specification is always a mistake, so it is named as one.
  def encode(%module{}) do
    raise ArgumentError,
          "HoloMap.JSON cannot encode a #{inspect(module)} struct. " <>
            "Convert it to a plain map, list or scalar before putting it in a map specification."
  end

  def encode(value) when is_list(value) do
    "[" <> Enum.map_join(value, ",", &encode/1) <> "]"
  end

  def encode(value) when is_map(value) do
    body =
      value
      |> Enum.map(fn {key, val} -> {encode_key(key), val} end)
      |> Enum.sort_by(fn {key, _val} -> key end)
      |> Enum.map_join(",", fn {key, val} -> encode_string(key) <> ":" <> encode(val) end)

    "{" <> body <> "}"
  end

  def encode(value) do
    raise ArgumentError,
          "HoloMap.JSON cannot encode #{inspect(value)}. " <>
            "Map specifications may only contain strings, numbers, booleans, nil, " <>
            "atoms, lists and maps."
  end

  defp encode_key(key) when is_binary(key), do: key
  defp encode_key(key) when is_atom(key), do: Atom.to_string(key)
  defp encode_key(key) when is_integer(key), do: Integer.to_string(key)

  defp encode_key(key) do
    raise ArgumentError,
          "HoloMap.JSON cannot use #{inspect(key)} as an object key. " <>
            "Keys must be strings, atoms or integers."
  end

  # Escapes only what JSON requires: the quote, the backslash and the C0
  # control range. Iterating bytes rather than graphemes is safe here because
  # every byte of a multi-byte UTF-8 sequence is >= 0x80, so none of them can
  # collide with an ASCII character that needs escaping. They pass through
  # untouched and the sequence stays intact.
  defp encode_string(string) do
    escaped =
      for <<byte <- string>>, into: "" do
        escape_byte(byte)
      end

    "\"" <> escaped <> "\""
  end

  defp escape_byte(?"), do: "\\\""
  defp escape_byte(?\\), do: "\\\\"
  defp escape_byte(?\n), do: "\\n"
  defp escape_byte(?\r), do: "\\r"
  defp escape_byte(?\t), do: "\\t"
  defp escape_byte(?\b), do: "\\b"
  defp escape_byte(?\f), do: "\\f"

  defp escape_byte(byte) when byte < 0x20 do
    "\\u00" <> pad_hex(byte)
  end

  defp escape_byte(byte), do: <<byte>>

  defp pad_hex(byte) do
    hex = Integer.to_string(byte, 16)

    case byte < 0x10 do
      true -> "0" <> hex
      false -> hex
    end
  end
end
