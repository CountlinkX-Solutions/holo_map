defmodule HoloMap.Image do
  @moduledoc """
  Registers an image so layers can name it.

      <HoloMap.Image id="pin" url="/icons/pin.png" />

      <HoloMap.Layer.Symbol
        id="stops"
        source="stops"
        layout={%{icon_image: "pin", icon_size: 0.5, icon_allow_overlap: true}}
      />

  ## Why this component has to exist

  A symbol layer's `icon_image` names an image; it does not fetch one. The name
  has to already exist somewhere the map can find it, and there are only two
  such places.

  The first is the **sprite** the style ships: an atlas of named icons, declared
  by the style itself. `icon_image: "airport"` on a style that carries an
  airport icon works with no help from this component at all.

  The second is an image registered on the map at runtime, which is what
  `HoloMap.Image` does. Anything of your own (a PNG, an SVG rendered to a
  bitmap, a brand marker) goes through here.

  Referencing a name that exists in neither place is a **quiet failure**.
  MapLibre emits a `styleimagemissing` event and draws nothing; there is no
  error, no console warning, and the layer looks like it has bad data. Not all
  styles ship a sprite, and MapLibre's own demo tiles ship none, so on those
  every icon must be registered.

  ## Props

  | Prop | Type | Notes |
  | ---- | ---- | ----- |
  | `id` | string | **Required.** The name layers use in `icon_image`, `fill_pattern` or `line_pattern` |
  | `url` | string | **Required.** Where to fetch the image from |
  | `sdf` | boolean | Treat it as a signed-distance field, so `icon_color` can recolour it |
  | `pixel_ratio` | number | Device pixels per image pixel. `2` for an image drawn at twice its display size |
  | `stretch_x` / `stretch_y` | list | Stretchable regions, for images used as label backgrounds |
  | `content` | list | The `[x1, y1, x2, y2]` box that text is placed within |

  ## Ordering does not matter

  Loading is asynchronous and deliberately not sequenced against the layers that
  use the image. MapLibre re-resolves a missing icon on later renders, so a
  layer written above its `HoloMap.Image` simply starts drawing once the image
  arrives. Declare them in whatever order reads best.

  ## Recolouring with `sdf`

  A normal image is drawn with its own colours. An SDF image is a shape, and
  `icon_color` paints it: one file, any number of colours, driven by data.

      <HoloMap.Image id="pin" url="/icons/pin-sdf.png" sdf />

      <HoloMap.Layer.Symbol
        id="stops"
        source="stops"
        layout={%{icon_image: "pin"}}
        paint={%{icon_color: ["match", ["get", "status"], "open", "#16a34a", "#dc2626"]}}
      />

  This only works on an image actually authored as a distance field; passing
  `sdf` on an ordinary PNG produces a smear.

  ## Markers or symbols?

  `HoloMap.Marker` is a DOM node per point: easy to style with your own CSS, and
  expensive past a few dozen. A symbol layer with a registered icon renders on
  the GPU and scales to thousands. This component is what makes the second
  option available for icons you own.

  ## Lifetime

  The image is registered while the component renders and removed when it stops.
  A style change discards registered images along with sources and layers, and
  the runtime registers them again once the new style has loaded, so swapping
  `HoloMap.Map`'s `style` does not cost you the icons.

  Removing an image that a layer still references is not an error; that layer
  goes back to drawing nothing.
  """

  use HoloMap.Def

  @keys [
    url: "url",
    sdf: "sdf",
    pixel_ratio: "pixelRatio",
    stretch_x: "stretchX",
    stretch_y: "stretchY",
    content: "content"
  ]

  prop :id, :string, required: true
  prop :url, :string, required: true
  prop :sdf, :any, default: nil
  prop :pixel_ratio, :any, default: nil
  prop :stretch_x, :list, default: nil
  prop :stretch_y, :list, default: nil
  prop :content, :list, default: nil

  @impl Hologram.Component
  def template do
    ~HOLO"""
    <div
      data-hm="image"
      data-hm-key={@id}
      data-hm-map={HoloMap.Def.map_cid!(@map_cid)}
      data-hm-spec={HoloMap.Image.build(%{
        url: @url,
        sdf: @sdf,
        pixel_ratio: @pixel_ratio,
        stretch_x: @stretch_x,
        stretch_y: @stretch_y,
        content: @content
      })}
    ></div>
    """
  end

  @doc false
  @spec build(map()) :: String.t()
  def build(props) do
    props
    |> HoloMap.Spec.booleans([:sdf])
    |> HoloMap.Spec.take(@keys)
    |> HoloMap.Def.spec()
  end
end
