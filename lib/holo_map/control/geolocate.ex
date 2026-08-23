defmodule HoloMap.Control.Geolocate do
  @moduledoc """
  Locate the user, and optionally follow them.

      <HoloMap.Control.Geolocate track_user_location show_user_heading />

  ## Props

  | Prop | Type | Notes |
  | ---- | ---- | ----- |
  | `position` | string | Corner to place the control in. Default `"top-right"` |
  | `track_user_location` | boolean | Keep following after the first fix |
  | `show_user_location` | boolean | Draw a dot at the users position. Default true |
  | `show_accuracy_circle` | boolean | Draw the accuracy radius. Default true |
  | `show_user_heading` | boolean | Draw a heading arrow on the dot |
  | `position_options` | map | Passed to the browser Geolocation API |
  | `fit_bounds_options` | map | Camera options used when zooming to the user |

  `position_options` takes `enableHighAccuracy`, `timeout` and `maximumAge`.

  Geolocation requires a secure context and the users permission, and the
  browser prompt only appears when they click the button. Nothing happens on
  page load, by design.
  """

  use HoloMap.Def

  @keys [
    track_user_location: "trackUserLocation",
    show_user_location: "showUserLocation",
    show_accuracy_circle: "showAccuracyCircle",
    show_user_heading: "showUserHeading",
    position_options: "positionOptions",
    fit_bounds_options: "fitBoundsOptions"
  ]

  prop :position, :string,
    default: "top-right",
    values: ["top-left", "top-right", "bottom-left", "bottom-right"]

  prop :track_user_location, :any, default: nil
  prop :show_user_location, :any, default: nil
  prop :show_accuracy_circle, :any, default: nil
  prop :show_user_heading, :any, default: nil
  prop :position_options, :map, default: nil
  prop :fit_bounds_options, :map, default: nil

  @impl Hologram.Component
  def template do
    ~HOLO"""
    <div
      data-hm="control"
      data-hm-key={"control:geolocate:" <> @position}
      data-hm-map={HoloMap.Def.map_cid!(@map_cid)}
      data-hm-spec={HoloMap.Control.build(%{track_user_location: @track_user_location, show_user_location: @show_user_location, show_accuracy_circle: @show_accuracy_circle, show_user_heading: @show_user_heading, position_options: @position_options, fit_bounds_options: @fit_bounds_options}, HoloMap.Control.Geolocate.__keys__(), "geolocate", @position, [:track_user_location, :show_user_location, :show_accuracy_circle, :show_user_heading])}
    ></div>
    """
  end

  @doc false
  def __keys__, do: @keys
end
