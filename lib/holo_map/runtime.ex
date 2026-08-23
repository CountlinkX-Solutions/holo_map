defmodule HoloMap.Runtime do
  @moduledoc """
  The Elixir seam onto the browser runtime.

  This is the only module in `HoloMap` that touches JavaScript. Everything else
  — components, specifications, event normalisation — is ordinary Elixir that
  can be unit tested, which is the point: Hologram's JS interop is a no-op on
  the server and cannot be covered by `ExUnit`, so the less code lives behind
  it, the more of the library is actually verifiable.

  The functions here are thin on purpose. The reconciliation logic they reach
  lives in `runtime.mjs`; see the [Architecture guide](architecture.html) for
  how the two halves fit together.

  > #### Interop runs in actions only {: .warning}
  >
  > Hologram executes JS interop exclusively inside action handlers. Calling
  > these functions from `init/2`, `init/3` or a command silently does nothing
  > — on the server they are compiled to no-ops. `HoloMap.Map` therefore boots
  > through `put_action/2` rather than directly from `init/3`.
  """

  use Hologram.JS

  js_import(:boot, from: "./js/runtime.mjs")
  js_import(:invoke, from: "./js/runtime.mjs")
  js_import(:destroy, from: "./js/runtime.mjs")

  @doc """
  Creates the MapLibre instance for `cid` and starts watching its definitions.

  Idempotent. Calling it for a map that is already running reconciles that map
  instead of building a second one, and calling it after a client-side
  navigation — where the same cid is rendered onto a fresh DOM node — disposes
  the stale instance first.
  """
  @spec boot(String.t()) :: :ok
  def boot(cid) do
    JS.call(:boot, [cid])
    :ok
  end

  @doc """
  Calls `method` on the underlying `maplibregl.Map` with `args`.

  Calls made before the style finishes loading are queued and replayed on
  `load`, so a camera move issued from a mount action is not lost.

  This is the general escape hatch. Prefer the named wrappers in `HoloMap.API`,
  which document their arguments and normalise option keys; reach for this only
  for a MapLibre method those do not cover yet.

      HoloMap.Runtime.call(cid, "setRenderWorldCopies", [false])
  """
  @spec call(String.t(), String.t(), list()) :: :ok
  def call(cid, method, args \\ []) do
    JS.call(:invoke, [cid, method, args])
    :ok
  end

  @doc """
  Documents the JavaScript-side escape hatch. Not callable from Elixir.

  A MapLibre plugin — a draw control, a geocoder, a deck.gl overlay — needs the
  raw `maplibregl.Map` object, and Hologram's interop cannot hand one to a
  third-party script. Every booted map is therefore published on `window`:

      window.HoloMap.map("explorer")   // the maplibregl.Map, or null
      window.HoloMap.cids()            // every live map's cid
      window.HoloMap.destroy("explorer")

  Reach for it from your own JavaScript when a plugin needs the instance. From
  Elixir, use `HoloMap.API` and `call/3` instead — they queue correctly against
  the style's readiness, which a raw handle does not.
  """
  @spec global_api() :: :ok
  def global_api, do: :ok

  @doc """
  Tears the map down and releases its WebGL context.

  Normally unnecessary: the runtime observes its own container and disposes the
  map when Hologram removes it from the page. Use this when a map should stop
  consuming a context while its container stays mounted.
  """
  @spec destroy(String.t()) :: :ok
  def destroy(cid) do
    JS.call(:destroy, [cid])
    :ok
  end
end
