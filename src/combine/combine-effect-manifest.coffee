_ = require('lodash')
path = require('path')
fs = require('fs-extra')

STARPEACE = require('@starpeace/starpeace-assets-types')

AnimatedTexture = require('../common/animated-texture')
Manifest = require('../common/manifest')
TextureManifest = require('../common/texture-manifest')
Spritesheet = require('../common/spritesheet')
Utils = require('../utils/utils')

DEBUG_MODE = false

OUTPUT_TEXTURE_WIDTH = 256
OUTPUT_TEXTURE_HEIGHT = 256


load_effect_manifest = (effect_dir) ->
  new Promise (done) ->
    console.log "loading effect definition manifest from #{effect_dir}\n"
    definitions = _.map(JSON.parse(fs.readFileSync(path.join(effect_dir, 'effect-manifest.json'))), STARPEACE.effect.EffectDefinition.fromJson)
    console.log "found and loaded #{definitions.length} effect definitions\n"
    done(new Manifest(definitions))

load_effect_textures = (effect_dir) ->
  textures = await AnimatedTexture.load(effect_dir)
  console.log "found and loaded #{textures.length} effect textures into manifest\n"
  new TextureManifest(textures)

aggregate = ([effect_definition_manifest, effect_texture_manifest]) ->
  new Promise (done) ->
    frame_texture_groups = []
    for definition in effect_definition_manifest.definitions
      texture = effect_texture_manifest.by_file_path[definition.image]
      unless texture?
        console.log "unable to find effect image #{definition.image}"
        continue

      frame_textures = texture.get_frame_textures(definition.id, definition.width, definition.height)
      definition.frame_ids = _.map(frame_textures, (frame) -> frame.id)

      frame_texture_groups.push frame_textures
      console.log " [OK] #{definition.id} has #{frame_textures.length} frames"

    done([effect_definition_manifest, Spritesheet.pack_textures(frame_texture_groups, new Set(), OUTPUT_TEXTURE_WIDTH, OUTPUT_TEXTURE_HEIGHT)])


write_assets = (output_dir) -> ([effect_definition_manifest, effect_spritesheets]) ->
  new Promise (done) ->
    write_promises = []

    frame_atlas = {}
    atlas_names = []
    for spritesheet in effect_spritesheets
      texture_name = "effect.texture.#{spritesheet.index}.png"
      write_promises.push spritesheet.save_texture(output_dir, texture_name)

      atlas_name = "effect.atlas.#{spritesheet.index}.json"
      atlas_names.push "./#{atlas_name}"

      spritesheet.save_atlas(output_dir, texture_name, atlas_name, DEBUG_MODE)

      frame_atlas[data.key] = atlas_name for data in spritesheet.packed_texture_data

    definitions = {}
    for definition in effect_definition_manifest.definitions
      definitions[definition.id] = {
        w: definition.width
        h: definition.height
        s_x: definition.sourceX
        s_y: definition.sourceY
        atlas: frame_atlas[definition.frame_ids[0]]
        frames: definition.frame_ids
      } if definition.frame_ids?.length

    json = {
      atlas: atlas_names
      effects: definitions
    }

    metadata_file = path.join(output_dir, "effect.metadata.json")
    fs.mkdirsSync(path.dirname(metadata_file))
    fs.writeFileSync(metadata_file, if DEBUG_MODE then JSON.stringify(json, null, 2) else JSON.stringify(json))
    console.log " [OK] effect metadata saved to #{metadata_file}"

    Promise.all(write_promises).then (result) ->
      process.stdout.write '\n'
      done()


module.exports = class CombineEffectManifest
  @combine: (effect_dir, target_dir) ->
    new Promise (done, error) ->
      Promise.all [
          load_effect_manifest(effect_dir), load_effect_textures(effect_dir)
        ]
        .then aggregate
        .then write_assets(target_dir)
        .then done
        .catch error
