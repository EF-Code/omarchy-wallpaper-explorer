function titleForSlug(slug) {
  return String(slug || "")
    .replace(/[-_]+/g, " ")
    .replace(/\b\w/g, function(match) { return match.toUpperCase() })
}

function parseRows(raw) {
  var themes = []
  var bySlug = {}
  var currentTheme = ""
  var currentBackground = ""
  var lines = String(raw || "").split("\n")

  function ensureTheme(slug, name, count, preview) {
    if (!bySlug[slug]) {
      bySlug[slug] = {
        slug: slug,
        name: name || titleForSlug(slug),
        count: Number(count) || 0,
        preview: preview || "",
        backgrounds: []
      }
      themes.push(bySlug[slug])
    }
    return bySlug[slug]
  }

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (!line) continue

    var fields = line.split("\t")
    var kind = fields[0]

    if (kind === "meta") {
      if (fields[1] === "current-theme") currentTheme = fields.slice(2).join("\t")
      else if (fields[1] === "current-background") currentBackground = fields.slice(2).join("\t")
      continue
    }

    if (kind === "theme" && fields[1]) {
      ensureTheme(fields[1], fields[2], fields[3], fields[4] || "")
      continue
    }

    if (kind === "background" && fields[1] && fields[2]) {
      var theme = ensureTheme(fields[1])
      var backgroundPath = fields[2]
      var thumbnailPath = fields[3] || ""
      theme.backgrounds.push({
        path: backgroundPath,
        thumbnail: thumbnailPath,
        name: backgroundPath.split("/").pop()
      })
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
