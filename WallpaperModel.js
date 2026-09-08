function titleForSlug(slug) {
  return String(slug || "")
    .replace(/[-_]+/g, " ")
    .replace(/\b\w/g, function(match) { return match.toUpperCase() })
}

function parseRows(raw) {
  var maximumThemes = 256
  var maximumBackgroundsPerTheme = 256
  var maximumBackgroundsTotal = 2048
  var themes = []
  var bySlug = Object.create(null)
  var currentTheme = ""
  var currentBackground = ""
  var backgroundTotal = 0
  var lines = String(raw || "").split("\n")

  function ensureTheme(slug, name, count, preview) {
    if (!/^[a-z0-9]+(?:[a-z0-9-]*[a-z0-9])?$/.test(slug)) return null
    if (!Object.prototype.hasOwnProperty.call(bySlug, slug)) {
      if (themes.length >= maximumThemes) return null
      bySlug[slug] = {
        slug: slug,
        name: name || titleForSlug(slug),
        count: Number(count) || 0,
        preview: preview || "",
        backgrounds: []
      }
      themes.push(bySlug[slug])
    } else if (name !== undefined) {
      bySlug[slug].name = name || titleForSlug(slug)
      bySlug[slug].count = Math.min(maximumBackgroundsPerTheme, Math.max(0, Number(count) || 0))
      bySlug[slug].preview = preview || ""
    }
    return bySlug[slug]
  }

  function validField(value) {
    return typeof value === "string" && !/[\t\r\n]/.test(value)
  }

  function validPath(value) {
    return validField(value) && value.charAt(0) === "/"
  }

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (!line) continue

    var fields = line.split("\t")
    var kind = fields[0]

    if (kind === "meta" && fields.length === 3) {
      if (fields[1] === "current-theme" && validField(fields[2])) currentTheme = fields[2]
      else if (fields[1] === "current-background" && (!fields[2] || validPath(fields[2]))) currentBackground = fields[2]
      continue
    }

    if (kind === "theme" && fields.length === 5 && validField(fields[2])
        && (!fields[4] || validPath(fields[4]))) {
      ensureTheme(fields[1], fields[2], fields[3], fields[4])
      continue
    }

    if (kind === "background" && fields.length === 5 && validPath(fields[2])
        && (!fields[3] || validPath(fields[3])) && validField(fields[4])
        && backgroundTotal < maximumBackgroundsTotal) {
      var theme = ensureTheme(fields[1])
      if (!theme || !Array.isArray(theme.backgrounds)
          || theme.backgrounds.length >= maximumBackgroundsPerTheme) continue
      var backgroundPath = fields[2]
      var thumbnailPath = fields[3] || ""
      if (indexOfPath(theme.backgrounds, backgroundPath) !== -1) continue
      theme.backgrounds.push({
        path: backgroundPath,
        thumbnail: thumbnailPath,
        fingerprint: fields[4],
        name: backgroundPath.split("/").pop()
      })
      backgroundTotal += 1
    }
  }

  for (var j = 0; j < themes.length; j++) {
    if (!themes[j].count) themes[j].count = themes[j].backgrounds.length
    if (!themes[j].preview && themes[j].backgrounds.length > 0)
      themes[j].preview = themes[j].backgrounds[0].thumbnail || ""
  }

  return {
    themes: themes,
    currentTheme: currentTheme,
    currentBackground: currentBackground
  }
}

function filterThemes(themes, query) {
  var values = Array.isArray(themes) ? themes : []
  var needle = String(query || "").trim().toLowerCase()
  if (!needle) return values

  return values.filter(function(theme) {
    var name = String(theme.name || "").toLowerCase()
    var slug = String(theme.slug || "").toLowerCase()
    return name.indexOf(needle) !== -1 || slug.indexOf(needle) !== -1
  })
}

function indexOfPath(backgrounds, path) {
  var values = Array.isArray(backgrounds) ? backgrounds : []
  for (var i = 0; i < values.length; i++) {
    if (values[i].path === path) return i
  }
  return -1
}

function labelForPath(path) {
  var name = String(path || "").split("/").pop().replace(/\.[^.]+$/, "")
  return name
    .replace(/^\d+[-_]/, "")
    .replace(/[-_]+/g, " ")
    .replace(/\b\w/g, function(match) { return match.toUpperCase() })
}

function gridColumns(width, minimumCellWidth, maximumColumns) {
  var available = Number(width) || 0
  var minimum = Math.max(1, Number(minimumCellWidth) || 1)
  var maximum = Math.max(1, Number(maximumColumns) || 1)
  return Math.max(1, Math.min(maximum, Math.floor(available / minimum)))
}

if (typeof module !== "undefined") {
  module.exports = {
    titleForSlug: titleForSlug,
    parseRows: parseRows,
    filterThemes: filterThemes,
    indexOfPath: indexOfPath,
    labelForPath: labelForPath,
    gridColumns: gridColumns
  }
}
