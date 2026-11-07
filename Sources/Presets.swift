import AppKit
import SwiftUI

// MARK: - Presets

/// A whole look in one click: background, lyric animation, font, particles and extras together.
struct Preset {
    let name: String
    let symbol: String
    let blurb: String
    let tweak: (inout StyleValues) -> Void

    /// The preset's look on top of the defaults, keeping the settings that aren't about looks.
    func values(keeping current: StyleValues) -> StyleValues {
        var v = StyleValues()
        tweak(&v)
        return v.keepingSystemSettings(from: current)
    }
}

extension StyleValues {
    /// A visual with the lyric look that goes with it, clean like a wallpaper: no rim light, bursts or particles.
    mutating func visualLook(_ background: String) {
        stageBackground = background
        stageLayout = "matched"
        edgeGlow = false
        keywordBursts = false
        particles = "none"
        depth = false
        lyricsBacking = "none"
        motion = 0.6
    }

    /// Copies over everything a preset shouldn't touch: where lyrics show, sync, the desktop window, permissions.
    func keepingSystemSettings(from c: StyleValues) -> StyleValues {
        var v = self
        v.showOnLockScreen = c.showOnLockScreen
        v.stageClock = c.stageClock
        v.stageFooter = c.stageFooter
        v.keepAwake = c.keepAwake
        v.audioReactive = c.audioReactive
        v.romanize = c.romanize
        v.titleCard = c.titleCard
        v.autoSync = c.autoSync
        v.lyricsBackup = c.lyricsBackup
        v.youtube = c.youtube
        v.matchOutput = c.matchOutput
        v.learnTiming = c.learnTiming
        v.batterySaver = c.batterySaver
        v.showOnDesktop = c.showOnDesktop
        v.liveWallpaper = c.liveWallpaper
        v.shuffleLooks = c.shuffleLooks
        v.myFont = c.myFont
        if c.myFont {
            // Your font stays as you chose it whichever preset you pick.
            v.fontFamily = c.fontFamily
            v.fontWeight = c.fontWeight
            v.italic = c.italic
        }
        v.syncLyrics = c.syncLyrics
        v.translate = c.translate
        v.tintVisuals = c.tintVisuals
        v.secondLayout = c.secondLayout
        v.desktopLayout = c.desktopLayout
        v.edgeDesktop = c.edgeDesktop
        // The edge light is yours, not the preset's: it stays as you set it whichever look you pick.
        v.edgeGlow = c.edgeGlow
        v.edgeStyle = c.edgeStyle
        v.edgeColor = c.edgeColor
        v.edgeHex = c.edgeHex
        v.edgeThickness = c.edgeThickness
        v.edgeBrightness = c.edgeBrightness
        v.edgeBeat = c.edgeBeat
        v.fontSize = c.fontSize
        v.width = c.width
        v.background = c.background
        v.backgroundOpacity = c.backgroundOpacity
        v.showHeader = c.showHeader
        v.clickThrough = c.clickThrough
        v.offset = c.offset
        return v
    }
}

enum Presets {
    /// Looks borrowed from lyric edits on reels.
    static let builtIn: [Preset] = [
        Preset(name: "Reel Edit", symbol: "scissors", blurb: "Cuts on the beat, a new effect every line") { _ in },
        Preset(name: "Late Night", symbol: "sparkles", blurb: "Mono cover, constellation lyrics, white rim light") { v in
            v.stageLayout = "constellation"
            v.stageBackground = "mono"
            v.colorMode = "white"
            v.fontFamily = "Manrope"
            v.fontWeight = "bold"
            v.keywordBursts = false
            v.backgroundDarkness = 0.75
            v.motion = 0.25
            v.edgeStyle = "rim"
            v.edgeColor = "white"
            v.edgeThickness = 48
            v.edgeBrightness = 0.9
        },
        Preset(name: "Fisheye", symbol: "circle.circle.fill", blurb: "Words rolling under a glass lens") { v in
            v.stageLayout = "fisheye"
            v.stageBackground = "mono"
            v.colorMode = "white"
            v.fontFamily = "Manrope"
            v.fontWeight = "bold"
            v.keywordBursts = false
            v.backgroundDarkness = 0.75
            v.motion = 0.25
        },
        Preset(name: "Fisheye Visual", symbol: "eye.circle.fill", blurb: "The glass lens, with icons beside the words") { v in
            v.stageLayout = "fisheyevisual"
            v.stageBackground = "mono"
            v.colorMode = "white"
            v.fontFamily = "Manrope"
            v.fontWeight = "bold"
            v.keywordBursts = false
            v.backgroundDarkness = 0.75
            v.motion = 0.25
        },
        Preset(name: "Visualizer", symbol: "sparkles.tv.fill", blurb: "Cuts between all the visuals, each with its own lyric look") { v in
            v.visualLook("visualmix")
        },
        Preset(name: "Nebula", symbol: "moon.stars.fill", blurb: "Purple space, neon comets, the sung word in a box") { v in
            v.visualLook("nebula")
        },
        Preset(name: "Voxel Land", symbol: "cube.fill", blurb: "A block landscape with a river, soft pink words") { v in
            v.visualLook("voxel")
        },
        Preset(name: "Vortex", symbol: "hurricane", blurb: "The artwork as a spinning storm") { v in
            v.visualLook("vortex")
        },
        Preset(name: "Chrome", symbol: "staroflife.fill", blurb: "A spiky chrome sculpture, one huge word at a time") { v in
            v.visualLook("chrome")
        },
        Preset(name: "Dot Globe", symbol: "globe", blurb: "A globe of dots, the line building up in orange and gold") { v in
            v.visualLook("dotsphere")
        },
        Preset(name: "Particle Hill", symbol: "circle.dashed", blurb: "Glowing strands, a ring on every beat") { v in
            v.visualLook("hill")
        },
        Preset(name: "Smear", symbol: "wind", blurb: "The artwork in motion blur, big red words") { v in
            v.visualLook("smear")
        },
        Preset(name: "Sunset Glow", symbol: "sun.horizon.fill", blurb: "A warm gradient and 3D letters") { v in
            v.visualLook("sunset")
        },
        Preset(name: "Contours", symbol: "water.waves", blurb: "Black and white bands winding together, words on tape") { v in
            v.visualLook("contours")
        },
        Preset(name: "Molten", symbol: "flame", blurb: "Seams of lava, the sung word in a dark box") { v in
            v.visualLook("molten")
        },
        Preset(name: "Terraces", symbol: "map.fill", blurb: "A topographic map in steps of blue") { v in
            v.visualLook("terraces")
        },
        Preset(name: "Silk", symbol: "wind.snow", blurb: "Pale silk folds, words on a strip of tape") { v in
            v.visualLook("silk")
        },
        Preset(name: "Ink Drops", symbol: "drop.fill", blurb: "Ink merging on paper, big red words") { v in
            v.visualLook("ink")
        },
        Preset(name: "Tunnel", symbol: "circle.circle", blurb: "Neon rings rushing past, one word at a time") { v in
            v.visualLook("tunnel")
        },
        Preset(name: "Wire Sea", symbol: "waveform.path", blurb: "A wireframe ocean lifted by the music") { v in
            v.visualLook("wiresea")
        },
        Preset(name: "Night City", symbol: "building.2.fill", blurb: "Flying low over a block city at night") { v in
            v.visualLook("city")
        },
        Preset(name: "Ringed Planet", symbol: "globe.americas.fill", blurb: "A planet in a ring of glittering dust") { v in
            v.visualLook("ringed")
        },
        Preset(name: "Shoal", symbol: "fish.fill", blurb: "A school of fish circling under shafts of light") { v in
            v.visualLook("shoal")
        },
        Preset(name: "Warp", symbol: "sparkles", blurb: "Stars streaking to light speed on every hit") { v in
            v.visualLook("warp")
        },
        Preset(name: "Paper Bird", symbol: "bird.fill", blurb: "A paper bird gliding over low hills at dusk") { v in
            v.visualLook("paperbird")
        },
        Preset(name: "Freefall", symbol: "arrow.down.to.line", blurb: "Dropping between lit towers") { v in
            v.visualLook("freefall")
        },
        Preset(name: "Light Hall", symbol: "rectangle.portrait.on.rectangle.portrait", blurb: "A hall of glowing frames, pulsing on the beat") { v in
            v.visualLook("lighthall")
        },
        Preset(name: "TV Wall", symbol: "tv", blurb: "Old TVs flicking between the cover and static") { v in
            v.visualLook("tvwall")
        },
        Preset(name: "Neon Lattice", symbol: "square.grid.3x3.fill", blurb: "Flying through a grid of neon beams") { v in
            v.visualLook("lattice")
        },
        Preset(name: "Northern Lights", symbol: "sparkles", blurb: "Aurora curtains over a dark field") { v in
            v.visualLook("northern")
        },
        Preset(name: "Neon Dunes", symbol: "sun.dust.fill", blurb: "Dunes at dusk traced in neon") { v in
            v.visualLook("dunes")
        },
        Preset(name: "Glow Lagoon", symbol: "drop.circle.fill", blurb: "Glowing water, a ring on every beat") { v in
            v.visualLook("lagoon")
        },
        Preset(name: "Canyon", symbol: "mountain.2.fill", blurb: "Layered rock in rust and sand") { v in
            v.visualLook("canyon")
        },
        Preset(name: "Helix", symbol: "hurricane", blurb: "A spiral of blocks swelling with the music") { v in
            v.visualLook("helix")
        },
        Preset(name: "Clockwork", symbol: "clock.fill", blurb: "A clock ticking on the beat, with butterflies") { v in
            v.visualLook("clockwork")
        },
        Preset(name: "Glass Swirl", symbol: "circle.hexagongrid.fill", blurb: "Ribbons of glass spiralling in") { v in
            v.visualLook("glassswirl")
        },
        Preset(name: "Gravity Well", symbol: "circle.dotted.circle", blurb: "Light spiralling down into a well") { v in
            v.visualLook("gravitywell")
        },
        Preset(name: "Wood Grain", symbol: "square.stack.3d.down.forward.fill", blurb: "Polished wood rings and knots") { v in
            v.visualLook("woodgrain")
        },
        Preset(name: "Night Drive", symbol: "moon.stars.fill", blurb: "Spinning vinyl, neon words, stars") { v in
            v.stageBackground = "vinyl"
            v.wordStyle = "neon"
            v.transition = "fade"
            v.particles = "stars"
            v.lightLeaks = true
            v.fontFamily = "Righteous"
            v.fontWeight = "regular"
            v.backgroundDarkness = 0.62
            v.motion = 0.45
        },
        Preset(name: "Hype", symbol: "flame.fill", blurb: "Kaleidoscope, words slam in, embers") { v in
            v.stageBackground = "kaleido"
            v.wordStyle = "slam"
            v.transition = "zoom"
            v.rgbSplit = true
            v.particles = "embers"
            v.motion = 1
            v.fontFamily = "Anton"
            v.fontWeight = "regular"
            v.uppercase = true
            v.stageFontSize = 185
            v.backgroundDarkness = 0.5
        },
        Preset(name: "Chill", symbol: "cloud.fill", blurb: "Floating cover, soft reveal, bokeh") { v in
            v.stageBackground = "cover"
            v.stageLayout = "lines"
            v.linesShown = 3
            v.wordStyle = "reveal"
            v.transition = "blur"
            v.particles = "bokeh"
            v.lyricsBacking = "shade"
            v.fontFamily = "DM Serif Display"
            v.fontWeight = "regular"
            v.motion = 0.35
            v.stageFontSize = 130
        },
        Preset(name: "Love Letter", symbol: "heart.fill", blurb: "Pink duotone, letters cascade in, script") { v in
            v.stageBackground = "duotone"
            v.stageLayout = "lines"
            v.linesShown = 2
            v.wordStyle = "cascade"
            v.transition = "fade"
            v.particles = "bokeh"
            v.lightLeaks = true
            v.fontFamily = "Pacifico"
            v.fontWeight = "regular"
            v.colorMode = "custom"
            v.customHex = "#FF8CC6"
            v.motion = 0.4
            v.stageFontSize = 135
        },
        Preset(name: "Glitchcore", symbol: "waveform.path.ecg", blurb: "RGB split, glitching words, mint") { v in
            v.stageBackground = "motion"
            v.rgbSplit = true
            v.wordStyle = "glitch"
            v.transition = "flip"
            v.particles = "dust"
            v.fontFamily = "Space Grotesk"
            v.fontWeight = "bold"
            v.uppercase = true
            v.tracking = 2
            v.colorMode = "custom"
            v.customHex = "#7CFFCB"
            v.motion = 0.9
        },
        Preset(name: "Movie Subs", symbol: "film.fill", blurb: "Cinematic band, one line, wide caps") { v in
            v.stageBackground = "motion"
            v.stageLayout = "lines"
            v.linesShown = 1
            v.wordStyle = "reveal"
            v.transition = "fade"
            v.lyricsBacking = "band"
            v.particles = "dust"
            v.edgeGlow = false
            v.fontFamily = "Bebas Neue"
            v.fontWeight = "regular"
            v.uppercase = true
            v.tracking = 6
            v.colorMode = "white"
            v.backgroundDarkness = 0.7
            v.motion = 0.3
            v.stageFontSize = 140
        },
        Preset(name: "Galaxy", symbol: "sparkles", blurb: "Spinning disc, comet through the words") { v in
            v.stageBackground = "disc"
            v.stageLayout = "lines"
            v.linesShown = 2
            v.wordStyle = "comet"
            v.transition = "zoom"
            v.particles = "stars"
            v.lyricsBacking = "glass"
            v.fontFamily = "Sora"
            v.fontWeight = "semibold"
            v.stageFontSize = 120
        },
        Preset(name: "Highlighter", symbol: "highlighter", blurb: "Clean word stack with the marker box") { v in
            v.stageBackground = "motion"
            v.stackStyle = "box"
            v.particles = "none"
            v.keywordBursts = false
            v.edgeGlow = false
            v.fontFamily = "Archivo Black"
            v.fontWeight = "regular"
            v.motion = 0.4
        },
        Preset(name: "Fan Edit", symbol: "wand.and.stars", blurb: "The cover with big poster lyrics") { v in
            v.stageBackground = "motion"
            v.stageLayout = "reel"
            v.depthOverLyrics = true
            v.fontFamily = "Anton"
            v.fontWeight = "regular"
            v.uppercase = true
            v.keywordBursts = false
            v.motion = 0.9
            v.backgroundDarkness = 0.45
        },
        Preset(name: "Cinema Cut", symbol: "camera.aperture", blurb: "Wide caps, darker grade") { v in
            v.stageBackground = "motion"
            v.stageLayout = "reel"
            v.fontFamily = "Bebas Neue"
            v.fontWeight = "regular"
            v.uppercase = true
            v.tracking = 4
            v.colorMode = "white"
            v.edgeGlow = false
            v.keywordBursts = false
            v.particles = "dust"
            v.motion = 0.5
            v.backgroundDarkness = 0.62
        },
        Preset(name: "Poster Drop", symbol: "textformat.size", blurb: "Heavy poster type") { v in
            v.stageBackground = "motion"
            v.stageLayout = "reel"
            v.fontFamily = "Archivo Black"
            v.fontWeight = "regular"
            v.uppercase = true
            v.keywordBursts = false
            v.motion = 0.85
            v.backgroundDarkness = 0.55
        },
        Preset(name: "Sad Hours", symbol: "cloud.rain.fill", blurb: "Blue duotone, slow italic serif") { v in
            v.stageBackground = "duotone"
            v.stageLayout = "lines"
            v.linesShown = 2
            v.wordStyle = "reveal"
            v.transition = "fade"
            v.particles = "dust"
            v.edgeGlow = false
            v.fontFamily = "Playfair Display"
            v.fontWeight = "regular"
            v.italic = true
            v.colorMode = "custom"
            v.customHex = "#A9CCFF"
            v.motion = 0.25
            v.stageFontSize = 125
            v.backgroundDarkness = 0.65
        },
        Preset(name: "Golden Hour", symbol: "sun.max.fill", blurb: "Warm light leaks, soft bokeh, script") { v in
            v.stageBackground = "motion"
            v.stageLayout = "lines"
            v.linesShown = 2
            v.wordStyle = "shine"
            v.transition = "fade"
            v.particles = "bokeh"
            v.lightLeaks = true
            v.fontFamily = "Lobster"
            v.fontWeight = "regular"
            v.colorMode = "custom"
            v.customHex = "#FFD08A"
            v.motion = 0.35
            v.stageFontSize = 130
        },
        Preset(name: "Y2K", symbol: "sparkle", blurb: "Kaleidoscope, neon outline type, stars") { v in
            v.stageBackground = "kaleido"
            v.wordStyle = "neon"
            v.transition = "flip"
            v.particles = "stars"
            v.fontFamily = "Monoton"
            v.fontWeight = "regular"
            v.uppercase = true
            v.colorMode = "custom"
            v.customHex = "#D0AEFF"
            v.motion = 0.6
            v.stageFontSize = 130
            v.backgroundDarkness = 0.6
        },
        Preset(name: "Polaroid Days", symbol: "photo.fill", blurb: "Swinging polaroid, petals, handwriting") { v in
            v.stageBackground = "polaroid"
            v.stageLayout = "lines"
            v.linesShown = 2
            v.wordStyle = "float"
            v.transition = "fade"
            v.particles = "petals"
            v.lyricsBacking = "shade"
            v.fontFamily = "Caveat"
            v.fontWeight = "bold"
            v.motion = 0.6
            v.stageFontSize = 130
            v.backgroundDarkness = 0.4
        },
        Preset(name: "Mixtape", symbol: "recordingtape", blurb: "Cassette, VHS tape, typed words") { v in
            v.stageBackground = "cassette"
            v.stageLayout = "lines"
            v.linesShown = 2
            v.wordStyle = "typewriter"
            v.transition = "slide"
            v.vhs = true
            v.lyricsBacking = "shade"
            v.fontFamily = "Righteous"
            v.fontWeight = "regular"
            v.motion = 0.5
            v.stageFontSize = 115
            v.backgroundDarkness = 0.45
        },
        Preset(name: "Moonlit", symbol: "moon.fill", blurb: "Lake reflection, fireflies, ink") { v in
            v.stageBackground = "lake"
            v.stageLayout = "lines"
            v.linesShown = 2
            v.wordStyle = "ink"
            v.transition = "fade"
            v.particles = "fireflies"
            v.edgeGlow = false
            v.fontFamily = "Playfair Display"
            v.fontWeight = "regular"
            v.italic = true
            v.colorMode = "white"
            v.motion = 0.5
            v.stageFontSize = 120
            v.backgroundDarkness = 0.4
        },
        Preset(name: "Late Show", symbol: "popcorn.fill", blurb: "Cinema screen, subtitle band") { v in
            v.stageBackground = "cinema"
            v.stageLayout = "lines"
            v.linesShown = 1
            v.wordStyle = "fade"
            v.transition = "fade"
            v.lyricsBacking = "band"
            v.edgeGlow = false
            v.fontFamily = "Bebas Neue"
            v.fontWeight = "regular"
            v.uppercase = true
            v.tracking = 5
            v.colorMode = "white"
            v.stageFontSize = 115
            v.backgroundDarkness = 0.25
        },
        Preset(name: "Synthwave", symbol: "sunset.fill", blurb: "Neon grid, comets, VHS") { v in
            v.stageBackground = "retro"
            v.stageLayout = "lines"
            v.linesShown = 2
            v.wordStyle = "neon"
            v.transition = "zoom"
            v.particles = "comets"
            v.vhs = true
            v.fontFamily = "Unbounded"
            v.fontWeight = "bold"
            v.uppercase = true
            v.colorMode = "custom"
            v.customHex = "#3DE8FF"
            v.motion = 0.7
            v.stageFontSize = 95
            v.backgroundDarkness = 0.3
        },
        Preset(name: "Snow Globe", symbol: "snowflake", blurb: "Floating cover in falling snow") { v in
            v.stageBackground = "cover"
            v.stageLayout = "lines"
            v.linesShown = 2
            v.wordStyle = "float"
            v.transition = "blur"
            v.particles = "snow"
            v.fontFamily = "DM Serif Display"
            v.fontWeight = "regular"
            v.colorMode = "white"
            v.motion = 0.4
            v.stageFontSize = 125
        },
        Preset(name: "Monsoon", symbol: "cloud.heavyrain.fill", blurb: "Rain on the cover, words turn to smoke") { v in
            v.stageBackground = "motion"
            v.stageLayout = "lines"
            v.linesShown = 2
            v.wordStyle = "smoke"
            v.transition = "fade"
            v.particles = "rain"
            v.edgeGlow = false
            v.fontFamily = "Space Grotesk"
            v.fontWeight = "bold"
            v.colorMode = "custom"
            v.customHex = "#BFE0FF"
            v.motion = 0.3
            v.stageFontSize = 115
            v.backgroundDarkness = 0.68
        },
        Preset(name: "Sakura", symbol: "leaf.fill", blurb: "Pink duotone, drifting petals, swinging words") { v in
            v.stageBackground = "duotone"
            v.stageLayout = "lines"
            v.linesShown = 2
            v.wordStyle = "swing"
            v.transition = "fade"
            v.particles = "petals"
            v.lightLeaks = true
            v.fontFamily = "Pacifico"
            v.fontWeight = "regular"
            v.colorMode = "custom"
            v.customHex = "#FFC2DC"
            v.motion = 0.35
            v.stageFontSize = 120
        },
        Preset(name: "Festival", symbol: "fireworks", blurb: "Rising lanterns, rainbow words") { v in
            v.stageBackground = "vinyl"
            v.stageLayout = "lines"
            v.linesShown = 2
            v.wordStyle = "rainbow"
            v.transition = "zoom"
            v.particles = "lanterns"
            v.fontFamily = "Lobster"
            v.fontWeight = "regular"
            v.motion = 0.5
            v.stageFontSize = 130
            v.backgroundDarkness = 0.6
        },
        Preset(name: "Bubblegum", symbol: "bubbles.and.sparkles.fill", blurb: "Bubbles, jelly words, sugar pink") { v in
            v.stageBackground = "cover"
            v.stageLayout = "lines"
            v.linesShown = 2
            v.wordStyle = "jelly"
            v.transition = "scale"
            v.particles = "bubbles"
            v.fontFamily = "Bungee"
            v.fontWeight = "regular"
            v.colorMode = "custom"
            v.customHex = "#FF9AD5"
            v.motion = 0.5
            v.stageFontSize = 105
        },
        Preset(name: "Stadium", symbol: "light.beacon.max.fill", blurb: "Sweeping stage beams, stamped words") { v in
            v.stageBackground = "disc"
            v.wordStyle = "stamp"
            v.transition = "zoom"
            v.lightBeams = true
            v.fontFamily = "Archivo Black"
            v.fontWeight = "regular"
            v.uppercase = true
            v.motion = 0.6
            v.backgroundDarkness = 0.6
        },
        Preset(name: "Ripple", symbol: "water.waves", blurb: "Aurora flow, a wave through the letters") { v in
            v.stageBackground = "aurora"
            v.stageLayout = "lines"
            v.linesShown = 2
            v.wordStyle = "ripple"
            v.transition = "fade"
            v.particles = "bokeh"
            v.fontFamily = "Sora"
            v.fontWeight = "semibold"
            v.stageFontSize = 115
        },
        Preset(name: "Art Gallery", symbol: "photo.artframe", blurb: "Framed on a wall, light gliding past") { v in
            v.stageBackground = "gallery"
            v.wordStyle = "reveal"
            v.transition = "fade"
            v.fontFamily = "DM Serif Display"
            v.fontWeight = "regular"
            v.colorMode = "white"
            v.lyricsBacking = "shade"
            v.edgeGlow = false
            v.stageFontSize = 110
            v.backgroundDarkness = 0.2
            v.stageLayout = "lines"
            v.linesShown = 2
        },
        Preset(name: "Times Square", symbol: "building.2.crop.circle", blurb: "City billboard, huge poster lyrics") { v in
            v.stageBackground = "billboard"
            v.fontFamily = "Bebas Neue"
            v.fontWeight = "regular"
            v.tracking = 3
            v.motion = 0.7
            v.backgroundDarkness = 0.3
            v.stageLayout = "reel"
            v.keywordBursts = false
            v.uppercase = true
        },
        Preset(name: "Channel 3", symbol: "tv", blurb: "Old tube TV, typed captions") { v in
            v.stageBackground = "crt"
            v.wordStyle = "typewriter"
            v.transition = "slide"
            v.vhs = true
            v.lyricsBacking = "band"
            v.fontFamily = "Righteous"
            v.fontWeight = "regular"
            v.colorMode = "white"
            v.edgeGlow = false
            v.stageFontSize = 95
            v.backgroundDarkness = 0.2
            v.stageLayout = "lines"
            v.linesShown = 1
        },
        Preset(name: "Cosmos", symbol: "globe.europe.africa.fill", blurb: "Deep space, a moon in orbit") { v in
            v.stageBackground = "galaxy"
            v.wordStyle = "float"
            v.transition = "zoom"
            v.particles = "comets"
            v.fontFamily = "Sora"
            v.fontWeight = "semibold"
            v.stageFontSize = 105
            v.backgroundDarkness = 0.25
            v.stageLayout = "lines"
            v.linesShown = 2
        },
        Preset(name: "Sunset Beach", symbol: "beach.umbrella.fill", blurb: "Rolling waves, soft script") { v in
            v.stageBackground = "ocean"
            v.wordStyle = "ripple"
            v.transition = "fade"
            v.fontFamily = "Pacifico"
            v.fontWeight = "regular"
            v.colorMode = "white"
            v.edgeGlow = false
            v.stageFontSize = 110
            v.backgroundDarkness = 0.2
            v.stageLayout = "lines"
            v.linesShown = 2
        },
        Preset(name: "High Peaks", symbol: "mountain.2.fill", blurb: "Ridges drifting, inked serif") { v in
            v.stageBackground = "mountains"
            v.wordStyle = "ink"
            v.transition = "fade"
            v.particles = "dust"
            v.fontFamily = "Playfair Display"
            v.fontWeight = "regular"
            v.colorMode = "white"
            v.edgeGlow = false
            v.stageFontSize = 115
            v.backgroundDarkness = 0.22
            v.stageLayout = "lines"
            v.linesShown = 2
        },
        Preset(name: "Open Road", symbol: "road.lanes", blurb: "Night highway, slamming poster type") { v in
            v.stageBackground = "highway"
            v.fontFamily = "Anton"
            v.fontWeight = "regular"
            v.motion = 0.8
            v.backgroundDarkness = 0.3
            v.stageLayout = "reel"
            v.keywordBursts = false
            v.uppercase = true
        },
        Preset(name: "Neon Alley", symbol: "lightbulb.max.fill", blurb: "Neon on brick, rain coming down") { v in
            v.stageBackground = "neonwall"
            v.wordStyle = "neon"
            v.transition = "fade"
            v.particles = "rain"
            v.fontFamily = "Monoton"
            v.fontWeight = "regular"
            v.uppercase = true
            v.colorMode = "custom"
            v.customHex = "#FF4FA3"
            v.edgeGlow = false
            v.stageFontSize = 95
            v.backgroundDarkness = 0.35
            v.stageLayout = "lines"
            v.linesShown = 2
        },
        Preset(name: "Deep Blue", symbol: "fish.fill", blurb: "Aquarium, fish and rising bubbles") { v in
            v.stageBackground = "aquarium"
            v.wordStyle = "wave"
            v.transition = "fade"
            v.fontFamily = "Poppins"
            v.fontWeight = "bold"
            v.colorMode = "white"
            v.edgeGlow = false
            v.stageFontSize = 100
            v.backgroundDarkness = 0.2
            v.stageLayout = "lines"
            v.linesShown = 2
        },
        Preset(name: "Enchanted", symbol: "tree.fill", blurb: "Misty forest, fireflies, script") { v in
            v.stageBackground = "forest"
            v.wordStyle = "float"
            v.transition = "fade"
            v.particles = "fireflies"
            v.fontFamily = "Lobster"
            v.fontWeight = "regular"
            v.colorMode = "custom"
            v.customHex = "#D9FFC4"
            v.edgeGlow = false
            v.stageFontSize = 120
            v.backgroundDarkness = 0.2
            v.stageLayout = "lines"
            v.linesShown = 2
        },
        Preset(name: "Code Rain", symbol: "terminal.fill", blurb: "Falling code, words decrypt in a terminal") { v in
            v.stageBackground = "coderain"
            v.wordStyle = "scramble"
            v.transition = "fade"
            v.lyricsBacking = "terminal"
            v.fontFamily = "System Mono"
            v.fontWeight = "bold"
            v.colorMode = "custom"
            v.customHex = "#3DFF85"
            v.edgeGlow = false
            v.stageFontSize = 70
            v.backgroundDarkness = 0.2
            v.stageLayout = "lines"
            v.linesShown = 2
        },
        Preset(name: "Front Page", symbol: "newspaper.fill", blurb: "The song as the headline, a paper note") { v in
            v.stageBackground = "newspaper"
            v.wordStyle = "typewriter"
            v.transition = "fade"
            v.lyricsBacking = "paper"
            v.fontFamily = "Abril Fatface"
            v.fontWeight = "regular"
            v.colorMode = "custom"
            v.customHex = "#2A2320"
            v.edgeGlow = false
            v.stageFontSize = 75
            v.backgroundDarkness = 0.1
            v.stageLayout = "lines"
            v.linesShown = 2
        },
        Preset(name: "Love Note", symbol: "envelope.fill", blurb: "A handwritten note on the polaroid") { v in
            v.stageBackground = "polaroid"
            v.wordStyle = "ink"
            v.transition = "fade"
            v.lyricsBacking = "paper"
            v.fontFamily = "Dancing Script"
            v.fontWeight = "bold"
            v.colorMode = "custom"
            v.customHex = "#A0244E"
            v.edgeGlow = false
            v.stageFontSize = 80
            v.backgroundDarkness = 0.45
            v.stageLayout = "lines"
            v.linesShown = 2
        },
        Preset(name: "Text Thread", symbol: "message.fill", blurb: "Lyrics arrive as chat messages") { v in
            v.stageBackground = "cover"
            v.wordStyle = "pop"
            v.transition = "slide"
            v.lyricsBacking = "bubble"
            v.fontFamily = "System Rounded"
            v.fontWeight = "semibold"
            v.colorMode = "custom"
            v.customHex = "#1C7CFF"
            v.edgeGlow = false
            v.stageFontSize = 75
            v.stageLayout = "lines"
            v.linesShown = 1
        },
        Preset(name: "Exit Ahead", symbol: "signpost.right.fill", blurb: "Night highway, words on a road sign") { v in
            v.stageBackground = "highway"
            v.wordStyle = "reveal"
            v.transition = "push"
            v.lyricsBacking = "sign"
            v.fontFamily = "Oswald"
            v.fontWeight = "semibold"
            v.colorMode = "white"
            v.edgeGlow = false
            v.stageFontSize = 75
            v.backgroundDarkness = 0.3
            v.stageLayout = "lines"
            v.linesShown = 1
        },
        Preset(name: "Console", symbol: "chevron.left.forwardslash.chevron.right", blurb: "Black screen, green terminal") { v in
            v.stageBackground = "black"
            v.wordStyle = "typewriter"
            v.transition = "fade"
            v.lyricsBacking = "terminal"
            v.fontFamily = "System Mono"
            v.fontWeight = "regular"
            v.colorMode = "custom"
            v.customHex = "#3DFF85"
            v.edgeGlow = false
            v.stageFontSize = 70
            v.stageLayout = "lines"
            v.linesShown = 2
        },
        Preset(name: "Comic Book", symbol: "bubble.left.and.exclamationmark.bubble.right.fill", blurb: "Duotone panel, stamped speech bubbles") { v in
            v.stageBackground = "duotone"
            v.wordStyle = "stamp"
            v.transition = "zoom"
            v.lyricsBacking = "bubble"
            v.fontFamily = "Bungee"
            v.fontWeight = "regular"
            v.uppercase = true
            v.colorMode = "custom"
            v.customHex = "#111111"
            v.edgeGlow = false
            v.stageFontSize = 70
            v.stageLayout = "lines"
            v.linesShown = 1
        },
        Preset(name: "Night Museum", symbol: "building.columns.fill", blurb: "Dark gallery, dust in the light") { v in
            v.stageBackground = "gallery"
            v.wordStyle = "fade"
            v.transition = "blur"
            v.particles = "dust"
            v.lightBeams = true
            v.fontFamily = "Syne"
            v.fontWeight = "bold"
            v.colorMode = "white"
            v.edgeGlow = false
            v.stageFontSize = 100
            v.backgroundDarkness = 0.5
            v.stageLayout = "lines"
            v.linesShown = 2
        },
        Preset(name: "Stargazer", symbol: "binoculars.fill", blurb: "Space with poster lyrics") { v in
            v.stageBackground = "galaxy"
            v.fontFamily = "Unbounded"
            v.fontWeight = "bold"
            v.motion = 0.7
            v.backgroundDarkness = 0.3
            v.stageLayout = "reel"
            v.keywordBursts = false
            v.uppercase = true
        },
        Preset(name: "Winter Peaks", symbol: "snowflake.circle.fill", blurb: "Ridges under falling snow") { v in
            v.stageBackground = "mountains"
            v.wordStyle = "float"
            v.transition = "fade"
            v.particles = "snow"
            v.fontFamily = "Manrope"
            v.fontWeight = "bold"
            v.colorMode = "white"
            v.edgeGlow = false
            v.stageFontSize = 105
            v.backgroundDarkness = 0.35
            v.stageLayout = "lines"
            v.linesShown = 2
        },
        Preset(name: "Drive-In", symbol: "car.side.fill", blurb: "Cinema, big poster lyrics") { v in
            v.stageBackground = "cinema"
            v.fontFamily = "Oswald"
            v.fontWeight = "bold"
            v.colorMode = "white"
            v.motion = 0.6
            v.edgeGlow = false
            v.backgroundDarkness = 0.3
            v.stageLayout = "reel"
            v.keywordBursts = false
            v.uppercase = true
        },
        Preset(name: "Arcade", symbol: "gamecontroller.fill", blurb: "Neon grid, jelly pixel type") { v in
            v.stageBackground = "retro"
            v.wordStyle = "jelly"
            v.transition = "scale"
            v.particles = "stars"
            v.fontFamily = "Bungee"
            v.fontWeight = "regular"
            v.uppercase = true
            v.colorMode = "custom"
            v.customHex = "#FFE14D"
            v.motion = 0.8
            v.stageFontSize = 95
            v.backgroundDarkness = 0.3
            v.stageLayout = "lines"
            v.linesShown = 2
        },
        Preset(name: "Campfire", symbol: "flame.circle.fill", blurb: "Forest at night, rising embers") { v in
            v.stageBackground = "forest"
            v.wordStyle = "smoke"
            v.transition = "fade"
            v.particles = "embers"
            v.fontFamily = "Caveat"
            v.fontWeight = "bold"
            v.colorMode = "custom"
            v.customHex = "#FFC27A"
            v.edgeGlow = false
            v.stageFontSize = 125
            v.backgroundDarkness = 0.45
            v.stageLayout = "lines"
            v.linesShown = 2
        },
        Preset(name: "Zen Garden", symbol: "leaf.circle.fill", blurb: "Slow aurora, petals, quiet words") { v in
            v.stageBackground = "aurora"
            v.wordStyle = "fade"
            v.transition = "fade"
            v.particles = "petals"
            v.fontFamily = "Manrope"
            v.fontWeight = "medium"
            v.colorMode = "white"
            v.edgeGlow = false
            v.motion = 0.2
            v.stageFontSize = 95
            v.stageLayout = "lines"
            v.linesShown = 2
        },
    ]
}

extension Presets {
    typealias Item = (name: String, symbol: String, values: StyleValues)

    /// The built-in presets in groups, so seventy-odd looks can be browsed a handful at a time.
    static let groups: [(name: String, symbol: String, members: [String])] = [
        ("Live Visuals", "sparkles.tv.fill", ["Visualizer"]),
        ("Space & Light", "moon.stars.fill",
         ["Nebula", "Tunnel", "Warp", "Ringed Planet", "Gravity Well", "Particle Hill", "Sunset Glow"]),
        ("Sculptures", "cube.transparent",
         ["Chrome", "Dot Globe", "Vortex", "Smear", "Helix", "Glass Swirl", "Clockwork"]),
        ("Flow & Contours", "water.waves",
         ["Contours", "Molten", "Terraces", "Silk", "Ink Drops", "Canyon", "Wood Grain"]),
        ("Landscapes & Cities", "building.2.fill",
         ["Voxel Land", "Wire Sea", "Night City", "Shoal", "Northern Lights", "Neon Dunes", "Glow Lagoon", "Paper Bird"]),
        ("Journeys", "airplane", ["Freefall", "Light Hall"]),
        ("Rooms & Grids", "square.grid.3x3.fill", ["TV Wall", "Neon Lattice"]),
        ("Reel Edits", "scissors",
         ["Reel Edit", "Fan Edit", "Cinema Cut", "Poster Drop", "Highlighter", "Hype", "Glitchcore", "Movie Subs",
          "Late Night", "Fisheye", "Fisheye Visual"]),
        ("Moods", "heart.text.square.fill",
         ["Chill", "Love Letter", "Sad Hours", "Golden Hour", "Y2K", "Polaroid Days", "Mixtape", "Moonlit",
          "Snow Globe", "Monsoon", "Sakura", "Festival", "Bubblegum", "Ripple", "Zen Garden", "Love Note",
          "Night Drive", "Galaxy", "Synthwave"]),
        ("Scenes", "photo.on.rectangle.angled",
         ["Late Show", "Stadium", "Art Gallery", "Times Square", "Channel 3", "Cosmos", "Sunset Beach", "High Peaks",
          "Open Road", "Neon Alley", "Deep Blue", "Enchanted", "Code Rain", "Front Page", "Text Thread",
          "Exit Ahead", "Console", "Comic Book", "Night Museum", "Stargazer", "Winter Peaks", "Drive-In", "Arcade",
          "Campfire"]),
    ]

    /// Built-in presets by group, in order. Any preset not listed in a group lands in "More".
    static var grouped: [(name: String, symbol: String, presets: [Preset])] {
        let byName = Dictionary(builtIn.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        var result = groups.map { group in (group.name, group.symbol, group.members.compactMap { byName[$0] }) }
        let listed = Set(groups.flatMap(\.members))
        let rest = builtIn.filter { !listed.contains($0.name) }
        if !rest.isEmpty { result.append(("More", "ellipsis.circle", rest)) }
        return result
    }

    /// What the preset lists show: favourites first, then each group, then the user's own.
    static func sections(keeping current: StyleValues) -> [(name: String, symbol: String, items: [Item])] {
        var sections: [(name: String, symbol: String, items: [Item])] = grouped.map { group in
            (group.name, group.symbol, group.presets.map { ($0.name, $0.symbol, $0.values(keeping: current)) })
        }
        let custom = PresetStore.shared.custom.map { ($0.name, "star.fill", $0.values(keeping: current)) as Item }
        if !custom.isEmpty { sections.append(("Your Presets", "star.fill", custom)) }
        let favourites = PresetMemory.shared.favourites
        let liked = sections.flatMap(\.items).filter { favourites.contains($0.name) }
        if !liked.isEmpty { sections.insert(("Favourites", "heart.fill", liked), at: 0) }
        return sections
    }

    /// Every preset in menu order — favourites, then the groups, then the user's — as (name, symbol, values).
    static func all(keeping current: StyleValues) -> [Item] {
        let list = grouped.flatMap(\.presets).map { ($0.name, $0.symbol, $0.values(keeping: current)) as Item }
            + PresetStore.shared.custom.map { ($0.name, "star.fill", $0.values(keeping: current)) as Item }
        let favourites = PresetMemory.shared.favourites
        return list.filter { favourites.contains($0.name) } + list.filter { !favourites.contains($0.name) }
    }

    /// The lyric style your look started with: the style of the preset it matches once the lyric style and font
    /// are set aside (so changing them doesn't lose track of it), or Cadence's own default otherwise.
    static func defaultLayout(for current: StyleValues) -> (layout: String, preset: String?) {
        func plain(_ v: StyleValues) -> StyleValues {
            var v = v
            v.stageLayout = ""
            v.myFont = false
            v.fontFamily = ""
            v.fontWeight = ""
            v.italic = false
            return v
        }
        let target = plain(current)
        if let match = all(keeping: current).first(where: { plain($0.values) == target }) {
            return (match.values.stageLayout, match.name)
        }
        return (StyleValues().stageLayout, nil)
    }

    /// The name of the preset the current look matches, if any.
    static func current() -> String? {
        all(keeping: Style.shared.v).first { $0.values == Style.shared.v }?.name
    }

    /// Steps through the presets (from the first or last, if the current look isn't a preset) and flashes the
    /// name — for the lock screen, where there's no menu bar. With favourites set, it stays among those.
    static func step(_ by: Int) {
        let favourites = PresetMemory.shared.favourites
        let everything = all(keeping: Style.shared.v)
        let chosen = everything.filter { favourites.contains($0.name) }
        let list = chosen.isEmpty ? everything : chosen
        let current = list.firstIndex { $0.values == Style.shared.v }
        let index = current.map { ($0 + by + list.count) % list.count } ?? (by > 0 ? 0 : list.count - 1)
        pick(list[index].name, list[index].symbol, list[index].values)
    }

    static func pick(_ name: String, _ symbol: String, _ values: StyleValues) {
        Style.shared.v = values
        PresetToast.shared.show(name, symbol)
    }
}

/// Favourite presets, and which preset to use for a particular song or artist.
final class PresetMemory: ObservableObject {
    static let shared = PresetMemory()

    @Published private(set) var favourites: Set<String> {
        didSet { UserDefaults.standard.set(Array(favourites), forKey: "favouritePresets") }
    }
    @Published private(set) var rules: [String: String] {  // "song:<id>" or "artist:<name>" → preset name
        didSet { UserDefaults.standard.set(rules, forKey: "presetRules") }
    }
    private var usual: StyleValues?  // the look to go back to after a song with its own preset
    private var applied: StyleValues?

    private init() {
        favourites = Set(UserDefaults.standard.stringArray(forKey: "favouritePresets") ?? [])
        rules = UserDefaults.standard.dictionary(forKey: "presetRules") as? [String: String] ?? [:]
    }

    func toggleFavourite(_ name: String) {
        if favourites.contains(name) { favourites.remove(name) } else { favourites.insert(name) }
    }

    private func songKey(_ track: Track) -> String { "song:" + track.id }

    private func artistKey(_ track: Track) -> String {
        let first = track.artist.components(separatedBy: CharacterSet(charactersIn: ",&")).first ?? track.artist
        return "artist:" + first.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// The song's own preset wins over the artist's.
    func rule(for track: Track) -> String? { rules[songKey(track)] ?? rules[artistKey(track)] }

    func isPinned(_ track: Track?, artist: Bool) -> Bool {
        guard let track else { return false }
        return rules[artist ? artistKey(track) : songKey(track)] != nil
    }

    /// Pins the current preset to the song or artist, or unpins it.
    func togglePin(_ track: Track?, artist: Bool) {
        guard let track else { return }
        let key = artist ? artistKey(track) : songKey(track)
        if rules[key] != nil {
            rules[key] = nil
        } else if let name = Presets.current() {
            rules[key] = name
            // This look now belongs to the pin, so the next ordinary song goes back to the usual one.
            if usual == nil { usual = Style.shared.v }
            applied = Style.shared.v
        }
    }

    func songChanged(_ track: Track) {
        let style = Style.shared
        // Picking a different look by hand during a pinned song makes that the usual look from now on.
        if let applied, style.v != applied {
            usual = nil
            self.applied = nil
        }
        if let name = rule(for: track),
           let preset = Presets.all(keeping: style.v).first(where: { $0.name == name }) {
            if usual == nil { usual = style.v }
            if preset.values != style.v { style.v = preset.values }
            applied = preset.values
        } else if let usual {
            style.v = usual.keepingSystemSettings(from: style.v)
            self.usual = nil
            applied = nil
        }
        // Shuffle: a song with no pinned look gets a different favourite (or visual, with no favourites).
        if rule(for: track) == nil && style.v.shuffleLooks {
            let everything = Presets.all(keeping: style.v)
            let liked = everything.filter { favourites.contains($0.name) }
            let visuals = Set(Presets.groups.prefix(7).flatMap(\.members))
            let pool = (liked.isEmpty ? everything.filter { visuals.contains($0.name) } : liked)
                .filter { $0.values != style.v }
            if let pick = pool.randomElement() {
                var values = pick.values
                values.shuffleLooks = true
                Presets.pick(pick.name, pick.symbol, values)
            }
        }
    }
}

/// The name of a preset just switched to, shown briefly on the lock screen.
final class PresetToast: ObservableObject {
    static let shared = PresetToast()
    @Published private(set) var name = ""
    @Published private(set) var symbol = "sparkles"
    @Published private(set) var shownAt = Date.distantPast

    func show(_ name: String, _ symbol: String) {
        self.name = name
        self.symbol = symbol
        shownAt = Date()
    }
}

struct PresetToastView: View {
    let date: Date
    @ObservedObject private var toast = PresetToast.shared

    var body: some View {
        let age = date.timeIntervalSince(toast.shownAt)
        if age >= 0 && age < 1.8 {
            let appear = min(age / 0.2, 1)
            let fade = min(max((1.8 - age) / 0.4, 0), 1)
            HStack(spacing: 10) {
                Image(systemName: toast.symbol)
                Text(toast.name)
            }
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(Capsule().fill(Color.black.opacity(0.55)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
            .scaleEffect(0.8 + 0.2 * appear)
            .opacity(appear * fade)
        }
    }
}

struct CustomPreset: Codable, Identifiable {
    var id: String { name }
    let name: String
    let values: StyleValues

    func values(keeping current: StyleValues) -> StyleValues { values.keepingSystemSettings(from: current) }
}

/// Looks the user saved, kept in UserDefaults.
final class PresetStore: ObservableObject {
    static let shared = PresetStore()

    @Published private(set) var custom: [CustomPreset] {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(custom), forKey: "presets") }
    }

    private init() {
        // Laid over the defaults, so a setting added since a preset was saved doesn't lose the preset.
        let data = UserDefaults.standard.data(forKey: "presets")
        let saved = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] } ?? []
        custom = saved.compactMap { item in
            guard let name = item["name"] as? String, let values = item["values"] as? [String: Any],
                  let merged = StyleValues.overDefaults(values) else { return nil }
            return CustomPreset(name: name, values: merged.withoutRetiredBackground())
        }
    }

    func save(_ name: String, _ values: StyleValues) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        custom.removeAll { $0.name == name }
        custom.append(CustomPreset(name: name, values: values))
    }

    func delete(_ name: String) {
        custom.removeAll { $0.name == name }
    }
}

/// Grid of preset cards for the Settings window, plus saving and deleting your own.
struct PresetPicker: View {
    @ObservedObject private var style = Style.shared
    @ObservedObject private var store = PresetStore.shared
    @ObservedObject private var memory = PresetMemory.shared
    @State private var newName = ""

    @State private var open: Set<String> = []
    @State private var hovered: String?

    var body: some View {
        let blurbs = Dictionary(Presets.builtIn.map { ($0.name, $0.blurb) }, uniquingKeysWith: { first, _ in first })
        let custom = Set(store.custom.map(\.name))
        ForEach(Presets.sections(keeping: style.v), id: \.name) { section in
            DisclosureGroup(isExpanded: Binding(
                get: { open.contains(section.name) || section.items.contains { $0.values == style.v } },
                set: { if $0 { open.insert(section.name) } else { open.remove(section.name) } }
            )) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    ForEach(section.items, id: \.name) { item in
                        card(item.name, item.symbol, blurbs[item.name] ?? "Your look", item.values)
                            .overlay(alignment: .topTrailing) {
                                if custom.contains(item.name) && section.name == "Your Presets" {
                                    Button { store.delete(item.name) } label: {
                                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(6)
                                    .help("Delete this preset")
                                }
                            }
                    }
                }
                .padding(.vertical, 4)
            } label: {
                Label("\(section.name)  \(Text("\(section.items.count)").foregroundStyle(.secondary))", systemImage: section.symbol)
                    .font(.headline)
            }
        }
        HStack {
            TextField("Name", text: $newName, prompt: Text("Save the current look as…"))
                .onSubmit(save)
            Button("Save", action: save).disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func save() {
        store.save(newName, style.v)
        newName = ""
    }

    private func card(_ name: String, _ symbol: String, _ blurb: String, _ values: StyleValues) -> some View {
        let selected = style.v == values
        let favourite = memory.favourites.contains(name)
        return Button { style.v = values } label: {
            VStack(alignment: .leading, spacing: 4) {
                PresetThumb(values: values, symbol: symbol, size: CGSize(width: 136, height: 76), live: hovered == name)
                    .font(.title3)
                Text(name).font(.headline)
                Text(blurb).font(.caption).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(selected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Color.accentColor : .clear, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? name : (hovered == name ? nil : hovered) }
        .overlay(alignment: .bottomTrailing) {
            Button { memory.toggleFavourite(name) } label: {
                Image(systemName: favourite ? "heart.fill" : "heart").foregroundStyle(favourite ? Color.pink : .secondary)
            }
            .buttonStyle(.plain)
            .padding(8)
            .help("Favourite")
        }
    }
}

// MARK: - Thumbnails

/// A small picture of a preset's visual: still in lists, moving while the pointer is over it. Presets with
/// other backgrounds keep their symbol.
@MainActor
enum PresetThumbs {
    private static var cache: [String: NSImage] = [:]

    /// The visual a preset shows, if it's one of the generated ones.
    static func kind(_ values: StyleValues) -> String? {
        if values.stageBackground == "visualmix" { return "nebula" }
        return Visuals.tags.contains(values.stageBackground) ? values.stageBackground : nil
    }

    static func still(_ kind: String, _ size: CGSize) -> NSImage? {
        let key = "\(kind)-\(Int(size.width))"
        if let hit = cache[key] { return hit }
        let art = NowPlaying.shared.artwork ?? NSImage(size: NSSize(width: 8, height: 8))
        let renderer = ImageRenderer(content: VisualScene(kind: kind, art: art, size: size, t: 12, motion: 0.6, kick: 0.3,
                                                          beatAge: 0.4, bands: []))
        renderer.scale = 2
        guard let image = renderer.nsImage else { return nil }
        cache[key] = image
        return image
    }
}

struct PresetThumb: View {
    let values: StyleValues
    let symbol: String
    let size: CGSize
    var live = false
    @ObservedObject private var player = NowPlaying.shared

    var body: some View {
        if let kind = PresetThumbs.kind(values) {
            Group {
                if live {
                    TimelineView(.animation(minimumInterval: 1 / 24)) { context in
                        VisualScene(kind: kind, art: player.artwork ?? NSImage(size: NSSize(width: 8, height: 8)), size: size,
                                    t: context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600),
                                    motion: 0.6, kick: 0.3, beatAge: 0.4, bands: [])
                    }
                } else if let still = PresetThumbs.still(kind, size) {
                    Image(nsImage: still).resizable()
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: min(size.height * 0.15, 8), style: .continuous))
        } else {
            Image(systemName: symbol)
        }
    }
}
