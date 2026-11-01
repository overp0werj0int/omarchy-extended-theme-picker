function nameForPath(path) {
  return String(path || "").split("/").pop().replace(/\.[^/.]+$/, "")
}

function labelForPath(path) {
  return nameForPath(path).replace(/[-_]+/g, " ").replace(/\b\w/g, function(match) { return match.toUpperCase() })
}

function loadRows(rows) {
  var images = []
  var seen = {}
  var paths = String(rows || "").split("\n")

  for (var i = 0; i < paths.length; i++) {
    var row = paths[i]
    if (!row) continue

    var columns = row.split("\t")
    var path = columns[0]
    if (!path) continue

    var fileName = path.split("/").pop()
    if (seen[fileName]) continue
    seen[fileName] = true

    images.push({
      filePath: path,
      fileName: fileName,
      thumbnailPath: columns[1] || path
    })
  }

  return images
}

function itemMatches(images, index, filterText) {
  if (!Array.isArray(images) || index < 0 || index >= images.length) return false
  var needle = String(filterText || "").toLowerCase()
  if (!needle) return true

  var path = String(images[index].filePath || "")
  return nameForPath(path).toLowerCase().indexOf(needle) !== -1
      || labelForPath(path).toLowerCase().indexOf(needle) !== -1
}

function firstMatchingIndex(images, filterText) {
  var values = Array.isArray(images) ? images : []
  for (var i = 0; i < values.length; i++) {
    if (itemMatches(values, i, filterText)) return i
  }

  return -1
}

function filteredPosition(images, index, filterText) {
  if (!filterText) return index

  var position = 0
  for (var i = 0; i < index; i++) {
    if (itemMatches(images, i, filterText)) position++
  }

  return position
}

function selectedFilteredPosition(images, selectedIndex, filterText) {
  if (!filterText) return selectedIndex
  return itemMatches(images, selectedIndex, filterText) ? filteredPosition(images, selectedIndex, filterText) : 0
}

function indexForSelectedImage(images, selectedImage) {
  var values = Array.isArray(images) ? images : []
  for (var i = 0; i < values.length; i++) {
    if (values[i].filePath === selectedImage) return i
  }

  return 0
}

function nextSelectedIndexForFilter(images, selectedIndex, filterText) {
  if (itemMatches(images, selectedIndex, filterText)) return selectedIndex
  return firstMatchingIndex(images, filterText)
}

function settingsFromShellJson(raw, pluginId) {
  var settings = { cardSwapAnimation: false, glassOverlay: false }
  try {
    var plugins = JSON.parse(raw).plugins
    var entry = (Array.isArray(plugins) ? plugins : []).find(function(plugin) { return plugin && plugin.id === pluginId })
    if (entry) {
      settings.cardSwapAnimation = entry.cardSwapAnimation === true
      settings.glassOverlay = entry.glassOverlay === true
    }
  } catch (e) {}
  return settings
}

function cardLayout(offset, L) {
  var t = Math.min(1, Math.abs(offset))
  var width = L.previewWidth * (1 - t) + L.sliceWidth * t
  var height = L.previewHeight * (1 - t) + L.sliceHeight * t
  var x
  if (offset <= 0) x = L.previewX + offset * L.step
  else if (offset < 1) x = L.previewX * (1 - offset) + L.firstRightX * offset
  else x = L.firstRightX + (offset - 1) * L.step
  return { x: x, y: (L.previewHeight - height) / 2, width: width, height: height, emphasis: 1 - t }
}

if (typeof module !== "undefined") {
  module.exports = {
    nameForPath: nameForPath,
    labelForPath: labelForPath,
    loadRows: loadRows,
    itemMatches: itemMatches,
    firstMatchingIndex: firstMatchingIndex,
    filteredPosition: filteredPosition,
    selectedFilteredPosition: selectedFilteredPosition,
    indexForSelectedImage: indexForSelectedImage,
    nextSelectedIndexForFilter: nextSelectedIndexForFilter,
    settingsFromShellJson: settingsFromShellJson,
    cardLayout: cardLayout
  }
}
