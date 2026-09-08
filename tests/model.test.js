const assert = require("node:assert/strict")
const Model = require("../WallpaperModel.js")

const raw = [
  "meta\tcurrent-theme\tlast-horizon",
  "meta\tcurrent-background\t/usr/share/omarchy/themes/last-horizon/backgrounds/4-new-horizons.jpg",
  "theme\tsolitude\tSolitude\t2\t/usr/share/omarchy/themes/solitude/backgrounds/1-on-pole.jpg",
  "background\tsolitude\t/usr/share/omarchy/themes/solitude/backgrounds/1-on-pole.jpg\t/tmp/one.jpg\tfingerprint-one",
  "background\tsolitude\t/usr/share/omarchy/themes/solitude/backgrounds/2-wreakage.jpg\t/tmp/two.jpg\tfingerprint-two",
  "theme\taether\tAether\t0\t"
].join("\n")

const parsed = Model.parseRows(raw)
assert.equal(parsed.currentTheme, "last-horizon")
assert.equal(parsed.currentBackground.endsWith("4-new-horizons.jpg"), true)
assert.equal(parsed.themes.length, 2)
assert.equal(parsed.themes[0].backgrounds.length, 2)
assert.equal(parsed.themes[0].backgrounds[0].thumbnail, "/tmp/one.jpg")
assert.equal(parsed.themes[0].backgrounds[0].fingerprint, "fingerprint-one")
assert.equal(parsed.themes[1].count, 0)
assert.equal(Model.titleForSlug("last-horizon"), "Last Horizon")
assert.equal(Model.labelForPath("/tmp/4-new-horizons.jpg"), "New Horizons")
assert.equal(Model.indexOfPath(parsed.themes[0].backgrounds, parsed.themes[0].backgrounds[1].path), 1)
assert.deepEqual(Model.filterThemes(parsed.themes, "SOL"), [parsed.themes[0]])
assert.equal(Model.gridColumns(1000, 240, 4), 4)
assert.equal(Model.gridColumns(420, 240, 4), 1)

for (const slug of ["__proto__", "constructor", "tostring"]) {
  const hostile = Model.parseRows([
    `theme\t${slug}\tHostile\t1\t`,
    `background\t${slug}\t/tmp/image.jpg\t/tmp/preview.jpg\tfingerprint`
  ].join("\n"))
  if (slug === "__proto__") assert.equal(hostile.themes.length, 0)
  else assert.equal(hostile.themes[0].backgrounds.length, 1)
}

const malformed = Model.parseRows([
  "theme\tsafe\tSafe\t1\t\textra",
  "background\tsafe\t/tmp/image.jpg\t/tmp/preview.jpg",
  "background\tsafe\trelative.jpg\t/tmp/preview.jpg\tfingerprint"
].join("\n"))
assert.equal(malformed.themes.length, 0)

console.log("Wallpaper Explorer model tests passed")
