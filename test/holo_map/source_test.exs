defmodule HoloMap.SourceTest do
  use HoloMap.RenderCase, async: true

  describe "GeoJSON" do
    test "carries inline features unchanged" do
      data = %{
        "type" => "FeatureCollection",
        "features" => [
          %{
            "type" => "Feature",
            "properties" => %{"name" => "Peña"},
            "geometry" => %{"type" => "Point", "coordinates" => [-70.66, 19.45]}
          }
        ]
      }

      html = render_def(HoloMap.Source.GeoJSON, id: "parcels", data: data)

      assert spec_for(html, "parcels") == %{"type" => "geojson", "data" => data}
    end

    test "accepts a URL instead of inline data" do
      html = render_def(HoloMap.Source.GeoJSON, id: "stops", data: "/api/stops.geojson")

      assert spec_for(html, "stops")["data"] == "/api/stops.geojson"
    end

    test "maps clustering props onto MapLibre's camelCase names" do
      html =
        render_def(HoloMap.Source.GeoJSON,
          id: "stops",
          data: "/s.geojson",
          cluster: true,
          cluster_radius: 60,
          cluster_max_zoom: 14,
          cluster_min_points: 3
        )

      spec = spec_for(html, "stops")

      assert spec["cluster"] == true
      assert spec["clusterRadius"] == 60
      assert spec["clusterMaxZoom"] == 14
      assert spec["clusterMinPoints"] == 3
    end

    test "maps the feature-id props needed for feature state" do
      html =
        render_def(HoloMap.Source.GeoJSON,
          id: "s",
          data: "/s.geojson",
          generate_id: true,
          promote_id: "parcel_id",
          line_metrics: true
        )

      spec = spec_for(html, "s")

      assert spec["generateId"] == true
      assert spec["promoteId"] == "parcel_id"
      assert spec["lineMetrics"] == true
    end
  end

  describe "Vector" do
    test "carries a TileJSON url" do
      html = render_def(HoloMap.Source.Vector, id: "basemap", url: "https://t.example/b.json")

      assert spec_for(html, "basemap") == %{
               "type" => "vector",
               "url" => "https://t.example/b.json"
             }
    end

    test "carries tile templates and lowercase zoom keys" do
      html =
        render_def(HoloMap.Source.Vector,
          id: "parcels",
          tiles: ["https://t.example/{z}/{x}/{y}.pbf"],
          min_zoom: 8,
          max_zoom: 14
        )

      spec = spec_for(html, "parcels")

      assert spec["tiles"] == ["https://t.example/{z}/{x}/{y}.pbf"]
      assert spec["minzoom"] == 8, "MapLibre spells source zoom keys lowercase, not camelCase"
      assert spec["maxzoom"] == 14
    end
  end

  describe "Raster" do
    test "uses camelCase for tileSize but lowercase for zoom" do
      # These two casings sit side by side in the MapLibre spec, which is why
      # HoloMap uses an explicit key table rather than one mechanical rule.
      html =
        render_def(HoloMap.Source.Raster,
          id: "ortho",
          tiles: ["https://t.example/{z}/{x}/{y}.png"],
          tile_size: 256,
          min_zoom: 0
        )

      spec = spec_for(html, "ortho")

      assert spec["tileSize"] == 256
      assert spec["minzoom"] == 0
    end
  end

  describe "RasterDEM" do
    test "carries the encoding and its custom coefficients" do
      html =
        render_def(HoloMap.Source.RasterDEM,
          id: "dem",
          tiles: ["https://t.example/{z}/{x}/{y}.png"],
          encoding: "custom",
          red_factor: 256.0,
          green_factor: 1.0,
          blue_factor: 0.00390625,
          base_shift: 32_768.0
        )

      spec = spec_for(html, "dem")

      assert spec["type"] == "raster-dem"
      assert spec["encoding"] == "custom"
      assert spec["redFactor"] == 256.0
      assert spec["baseShift"] == 32_768.0
    end
  end

  describe "Image" do
    test "normalises all four corners" do
      html =
        render_def(HoloMap.Source.Image,
          id: "plan",
          url: "/plan.png",
          coordinates: [
            {-70.662, 19.453},
            {-70.660, 19.453},
            {-70.660, 19.4515},
            {-70.662, 19.4515}
          ]
        )

      assert spec_for(html, "plan") == %{
               "type" => "image",
               "url" => "/plan.png",
               "coordinates" => [
                 [-70.662, 19.453],
                 [-70.660, 19.453],
                 [-70.660, 19.4515],
                 [-70.662, 19.4515]
               ]
             }
    end
  end

  test "every source requires a surrounding map" do
    for {module, props} <- [
          {HoloMap.Source.GeoJSON, [id: "s", data: "/s.json"]},
          {HoloMap.Source.Vector, [id: "s", url: "/s.json"]},
          {HoloMap.Source.Raster, [id: "s", url: "/s.json"]},
          {HoloMap.Source.RasterDEM, [id: "s", url: "/s.json"]},
          {HoloMap.Source.Image,
           [id: "s", url: "/s.png", coordinates: [{0, 0}, {1, 0}, {1, 1}, {0, 1}]]}
        ] do
      assert_raise ArgumentError, ~r/outside a <HoloMap.Map>/, fn -> render(module, props) end
    end
  end
end
