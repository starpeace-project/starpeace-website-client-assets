_ = require('lodash')
path = require('path')
fs = require('fs-extra')

STARPEACE = require('@starpeace/starpeace-assets-types')

Manifest = require('../common/manifest')
Spritesheet = require('../common/spritesheet')
Texture = require('../common/texture')
TextureManifest = require('../common/texture-manifest')
Utils = require('../utils/utils')

DEBUG_MODE = false

OUTPUT_TEXTURE_WIDTH = 512
OUTPUT_TEXTURE_HEIGHT = 512


load_road_manifest = (road_dir) ->
  new Promise (done) ->
    console.log "loading road definition manifest from #{road_dir}\n"
    definitions = _.map(JSON.parse(fs.readFileSync(path.join(road_dir, 'road-manifest.json'))), STARPEACE.road.RoadDefinition.fromJson)
    console.log "found and loaded #{definitions.length} road definitions\n"
    done(new Manifest(definitions))

load_road_textures = (road_dir) ->
  textures = await Texture.load(road_dir)
  console.log "found and loaded #{textures.length} road textures into manifest\n"
  new TextureManifest(textures)

aggregate = ([road_definition_manifest, road_texture_manifest]) ->
  new Promise (done, error) ->

    frame_texture_groups = []
    for definition in road_definition_manifest.definitions
      texture = road_texture_manifest.by_file_path[definition.image]
      unless texture?
        console.log "unable to find road image #{definition.image}"
        continue

      texture.id = definition.id
      definition.frame_ids = [texture.id]
      frame_texture_groups.push [texture]

    done([road_definition_manifest, Spritesheet.pack_textures(frame_texture_groups, new Set(), OUTPUT_TEXTURE_WIDTH, OUTPUT_TEXTURE_HEIGHT)])


write_assets = (output_dir) -> ([road_definition_manifest, road_spritesheets]) ->
  new Promise (done) ->
    write_promises = []

    frame_atlas = {}
    atlas_names = []
    for spritesheet in road_spritesheets
      texture_name = "road.texture.#{spritesheet.index}.png"
      write_promises.push spritesheet.save_texture(output_dir, texture_name)

      atlas_name = "road.atlas.#{spritesheet.index}.json"
      atlas_names.push "./#{atlas_name}"

      spritesheet.save_atlas(output_dir, texture_name, atlas_name, DEBUG_MODE)

      frame_atlas[data.key] = atlas_name for data in spritesheet.packed_texture_data

    definitions = {}
    definitions[definition.id] = {
      atlas: frame_atlas[definition.frame_ids[0]]
      frames: definition.frame_ids
    } for definition in road_definition_manifest.definitions

    json = {
      atlas: atlas_names
      road: definitions
    }

    metadata_file = path.join(output_dir, "road.metadata.json")
    fs.mkdirsSync(path.dirname(metadata_file))
    fs.writeFileSync(metadata_file, if DEBUG_MODE then JSON.stringify(json, null, 2) else JSON.stringify(json))
    console.log " [OK] road metadata saved to #{metadata_file}"

    Promise.all(write_promises).then (result) ->
      process.stdout.write '\n'
      done()


module.exports = class CombineRoadManifest
  @combine: (road_dir, target_dir) ->
    new Promise (done, error) ->
      Promise.all [
          load_road_manifest(road_dir), load_road_textures(road_dir)
        ]
        .then aggregate
        .then write_assets(target_dir)
        .then done
        .catch error
