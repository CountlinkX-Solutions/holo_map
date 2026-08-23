defmodule HoloMap.Sky do
  @moduledoc """
  Atmosphere at the horizon, for tilted and 3D maps.

      <HoloMap.Sky sky_color="#199EF3" horizon_color="#ffffff" fog_color="#0000ff" />

  Like `HoloMap.Terrain`, the sky is a map-level property rather than a layer:
  the component's presence turns it on, its absence turns it off.

  ## Props

  | Prop | Type | Notes |
  | ---- | ---- | ----- |
  | `sky_color` | color | Colour at the top of the sky |
  | `sky_horizon_blend` | number | 0–1. How far down the sky colour reaches |
  | `horizon_color` | color | Colour at the horizon line |
  | `horizon_fog_blend` | number | 0–1. Blend between horizon and fog |
  | `fog_color` | color | Colour of the fog over the ground |
  | `fog_ground_blend` | number | 0–1. How far up from the ground fog reaches |
  | `atmosphere_blend` | number | 0–1, or an expression. Overall opacity |
  | `properties` | map | Any further sky properties, merged last |

  Every prop accepts a MapLibre expression as well as a literal, which is how
  a sky follows the camera — fading the atmosphere in as the map tilts:

      <HoloMap.Sky
        atmosphere_blend={["interpolate", ["linear"], ["zoom"], 0, 1, 12, 0]}
      />

  ## Visibility

  The sky is only drawn where the horizon is on screen, which means a pitched
  camera. On a top-down map it renders nothing at all — that is not a
  misconfiguration, there is simply no horizon in view.
  """

  use HoloMap.Def

  prop :sky_color, :any, default: nil
  prop :sky_horizon_blend, :any, default: nil
  prop :horizon_color, :any, default: nil
  prop :horizon_fog_blend, :any, default: nil
  prop :fog_color, :any, default: nil
  prop :fog_ground_blend, :any, default: nil
  prop :atmosphere_blend, :any, default: nil
  prop :properties, :map, default: %{}

  @impl Hologram.Component
  def template do
    ~HOLO"""
    <div
      data-hm="sky"
      data-hm-key="sky"
      data-hm-map={HoloMap.Def.map_cid!(@map_cid)}
      data-hm-spec={HoloMap.Sky.build(%{
        sky_color: @sky_color,
        sky_horizon_blend: @sky_horizon_blend,
        horizon_color: @horizon_color,
        horizon_fog_blend: @horizon_fog_blend,
        fog_color: @fog_color,
        fog_ground_blend: @fog_ground_blend,
        atmosphere_blend: @atmosphere_blend
      }, @properties)}
    ></div>
    """
  end

  @doc false
  @spec build(map(), map()) :: String.t()
  def build(props, extra) do
    props
    |> HoloMap.Spec.dasherize()
    |> Map.merge(HoloMap.Spec.dasherize(extra))
    |> HoloMap.Def.spec()
  end
end
