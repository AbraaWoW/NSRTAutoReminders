-- Généré automatiquement par NSRTAutoReminders-build.py — NE PAS ÉDITER.
-- Recharge (cd) et durée d'effet (dur) en secondes, depuis
-- /api/spells de WoW Timeline. Sert aux barres de la timeline.
local _, EP = ...
EP.SpellTable = {
    [498] = { cd = 60, dur = 8 },  -- Divine Protection
    [586] = { cd = 30, dur = 5 },  -- Fade
    [642] = { cd = 300, dur = 8 },  -- Divine Shield
    [740] = { cd = 150, dur = 6 },  -- Tranquility
    [871] = { cd = 120, dur = 8 },  -- Shield Wall
    [1022] = { cd = 300, dur = 10 },  -- Blessing of Protection
    [1122] = { cd = 180, dur = 30 },  -- Summon Infernal
    [1160] = { cd = 45, dur = 8 },  -- Demoralizing Shout
    [1719] = { cd = 60, dur = 10 },  -- Recklessness
    [1856] = { cd = 120 },  -- Vanish
    [1966] = { cd = 15, dur = 6 },  -- Feint
    [2825] = { dur = 40 },  -- Bloodlust
    [5217] = { cd = 30, dur = 6 },  -- Tiger's Fury
    [5277] = { cd = 120, dur = 10 },  -- Evasion
    [5938] = { cd = 25 },  -- Shiv
    [6940] = { cd = 120, dur = 12 },  -- Blessing of Sacrifice
    [10060] = { cd = 120, dur = 20 },  -- Power Infusion
    [11426] = { cd = 25 },  -- Ice Barrier
    [12051] = { cd = 90, dur = 6 },  -- Evocation
    [13750] = { dur = 20 },  -- Adrenaline Rush
    [15286] = { cd = 120, dur = 15 },  -- Vampiric Embrace
    [19236] = { cd = 90, dur = 10 },  -- Desperate Prayer
    [19574] = { cd = 30, dur = 15 },  -- Bestial Wrath
    [20572] = { cd = 120, dur = 15 },  -- Blood Fury
    [22812] = { cd = 60, dur = 8 },  -- Barkskin
    [22842] = { cd = 36, dur = 3 },  -- Frenzied Regeneration
    [23920] = { cd = 10, dur = 5 },  -- Spell Reflection
    [26297] = { cd = 180, dur = 12 },  -- Berserking
    [29166] = { cd = 180, dur = 8 },  -- Innervate
    [31224] = { cd = 60, dur = 5 },  -- Cloak of Shadows
    [31821] = { cd = 180, dur = 8 },  -- Aura Mastery
    [31850] = { cd = 120, dur = 8 },  -- Ardent Defender
    [31884] = { cd = 120, dur = 20 },  -- Avenging Wrath
    [32375] = { cd = 120 },  -- Mass Dispel
    [33206] = { cd = 180, dur = 8 },  -- Pain Suppression
    [33891] = { cd = 120, dur = 30 },  -- Incarnation: Tree of Life
    [42650] = { cd = 240, dur = 30 },  -- Army of the Dead
    [45182] = { cd = 360, dur = 3 },  -- Cheating Death
    [45438] = { cd = 240 },  -- Ice Block
    [46585] = { cd = 120, dur = 60 },  -- Raise Dead
    [47585] = { cd = 120, dur = 6 },  -- Dispersion
    [47788] = { cd = 180 },  -- Guardian Spirit
    [48265] = { cd = 45, dur = 10 },  -- Death's Advance
    [48707] = { cd = 60, dur = 5 },  -- Anti-Magic Shell
    [48792] = { cd = 180, dur = 8 },  -- Icebound Fortitude
    [49028] = { cd = 120, dur = 8 },  -- Dancing Rune Weapon
    [49039] = { cd = 120, dur = 10 },  -- Lichborne
    [51052] = { cd = 120, dur = 10 },  -- Anti-Magic Zone
    [51271] = { cd = 60, dur = 12 },  -- Pillar of Frost
    [51690] = { cd = 120 },  -- Killing Spree
    [55233] = { cd = 90, dur = 10 },  -- Vampiric Blood
    [55342] = { cd = 120, dur = 40 },  -- Mirror Image
    [58984] = { cd = 120 },  -- Shadowmeld
    [61336] = { cd = 180, dur = 6 },  -- Survival Instincts
    [62618] = { cd = 180, dur = 10 },  -- Power Word: Barrier
    [64843] = { cd = 180, dur = 8 },  -- Divine Hymn
    [65116] = { cd = 120, dur = 8 },  -- Stoneform
    [73325] = { cd = 90 },  -- Leap of Faith
    [79206] = { cd = 120, dur = 15 },  -- Spiritwalker's Grace
    [80240] = { cd = 30, dur = 12 },  -- Havoc
    [84714] = { cd = 60 },  -- Frozen Orb
    [87023] = { cd = 300, dur = 6 },  -- Cauterize
    [91374] = { cd = 90, dur = 15 },  -- Mark of Khardros
    [92099] = { cd = 120, dur = 20 },  -- Skardyn's Grace
    [97462] = { cd = 180, dur = 10 },  -- Rallying Cry
    [98008] = { cd = 180, dur = 6 },  -- Spirit Link Totem
    [102342] = { cd = 90, dur = 12 },  -- Ironbark
    [102558] = { cd = 180, dur = 30 },  -- Incarnation: Guardian of Ursoc
    [104773] = { cd = 300, dur = 8 },  -- Unending Resolve
    [106898] = { cd = 120, dur = 8 },  -- Stampeding Roar
    [106951] = { cd = 120, dur = 15 },  -- Berserk
    [107574] = { cd = 90, dur = 20 },  -- Avatar
    [108271] = { cd = 90, dur = 12 },  -- Astral Shift
    [108280] = { cd = 180, dur = 10 },  -- Healing Tide Totem
    [108416] = { cd = 60 },  -- Dark Pact
    [109304] = { cd = 120 },  -- Exhilaration
    [114050] = { dur = 15 },  -- Ascendance
    [114051] = { cd = 10, dur = 15 },  -- Ascendance
    [114052] = { cd = 180 },  -- Ascendance
    [114165] = { cd = 30 },  -- Holy Prism
    [115176] = { cd = 300, dur = 8 },  -- Zen Meditation
    [115203] = { cd = 180, dur = 15 },  -- Fortifying Brew
    [115310] = { cd = 180 },  -- Revival
    [116680] = { cd = 30 },  -- Thunder Focus Tea
    [116849] = { cd = 120 },  -- Life Cocoon
    [118038] = { cd = 120, dur = 8 },  -- Die by the Sword
    [120517] = { cd = 60 },  -- Halo
    [120644] = { cd = 60 },  -- Halo
    [121471] = { cd = 180, dur = 20 },  -- Shadow Blades
    [122470] = { cd = 90, dur = 10 },  -- Touch of Karma
    [123904] = { cd = 120, dur = 24 },  -- Invoke Xuen, the White Tiger
    [123981] = { cd = 240, dur = 3 },  -- Purgatory
    [132578] = { cd = 180, dur = 25 },  -- Invoke Niuzao the Black Ox
    [153561] = { cd = 45 },  -- Meteor
    [167105] = { cd = 45, dur = 10 },  -- Colossus Smash
    [184364] = { cd = 180, dur = 8 },  -- Enraged Regeneration
    [185311] = { cd = 30, dur = 4 },  -- Crimson Vial
    [185313] = { dur = 8 },  -- Shadow Dance
    [186257] = { cd = 180, dur = 12 },  -- Aspect of the Cheetah
    [186265] = { cd = 120 },  -- Aspect of the Turtle
    [186289] = { cd = 90, dur = 15 },  -- Aspect of the Eagle
    [187827] = { cd = 180, dur = 15 },  -- Metamorphosis
    [190319] = { cd = 60, dur = 10 },  -- Combustion
    [191634] = { cd = 60 },  -- Stormkeeper
    [192077] = { cd = 120, dur = 15 },  -- Windrush Totem
    [194509] = { cd = 20 },  -- Power Word: Radiance
    [196718] = { cd = 180, dur = 8 },  -- Darkness
    [197214] = { cd = 30 },  -- Sundering
    [198013] = { cd = 40, dur = 2 },  -- Eye Beam
    [198589] = { cd = 60, dur = 10 },  -- Blur
    [198793] = { cd = 25 },  -- Vengeful Retreat
    [200025] = { cd = 15, dur = 8 },  -- Beacon of Virtue
    [200166] = { cd = 120, dur = 20 },  -- Metamorphosis
    [200183] = { cd = 120, dur = 20 },  -- Apotheosis
    [202770] = { cd = 60, dur = 8 },  -- Fury of Elune
    [204018] = { cd = 300, dur = 10 },  -- Blessing of Spellwarding
    [204021] = { cd = 60, dur = 10 },  -- Fiery Brand
    [204066] = { cd = 60, dur = 8 },  -- Lunar Beam
    [205021] = { cd = 60, dur = 5 },  -- Ray of Frost
    [205180] = { cd = 120, dur = 8 },  -- Summon Darkglare
    [205636] = { cd = 60, dur = 10 },  -- Force of Nature
    [209261] = { cd = 480, dur = 15 },  -- Last Resort
    [212084] = { cd = 40, dur = 2 },  -- Fel Devastation
    [212431] = { cd = 30, dur = 3 },  -- Explosive Shot
    [212641] = { cd = 300, dur = 8 },  -- Guardian of Ancient Kings
    [215956] = { cd = 120, dur = 30 },  -- Horn of Valor
    [216331] = { cd = 60, dur = 12 },  -- Avenging Crusader
    [228260] = { cd = 120, dur = 15 },  -- Voidform
    [235313] = { cd = 25 },  -- Blazing Barrier
    [235450] = { cd = 25 },  -- Prismatic Barrier
    [246344] = { cd = 90 },  -- Cursed Stone Idol
    [255937] = { cd = 45, dur = 15 },  -- Wake of Ashes
    [258860] = { cd = 40, dur = 4 },  -- Essence Break
    [260243] = { cd = 45, dur = 6 },  -- Volley
    [260708] = { cd = 30, dur = 15 },  -- Sweeping Strikes
    [263165] = { cd = 30, dur = 3 },  -- Void Torrent
    [264735] = { cd = 180, dur = 8 },  -- Survival of the Fittest
    [265187] = { cd = 60, dur = 15 },  -- Summon Demonic Tyrant
    [265954] = { cd = 90 },  -- My'das Talisman
    [268836] = { cd = 90, dur = 18 },  -- Vial of Animated Blood
    [268998] = { cd = 90 },  -- Balefire Branch
    [273104] = { cd = 120, dur = 8 },  -- Fireblood
    [274837] = { cd = 45, dur = 6 },  -- Feral Frenzy
    [279302] = { cd = 90 },  -- Frostwyrm's Fury
    [280719] = { cd = 25 },  -- Secret Technique
    [288613] = { cd = 120 },  -- Trueshot
    [299869] = { cd = 120 },  -- Modular Platinum Plating
    [321507] = { cd = 45, dur = 8 },  -- Touch of the Magi
    [322109] = { cd = 180 },  -- Touch of Death
    [322118] = { cd = 120, dur = 4.5 },  -- Invoke Yu'lon, the Jade Serpent
    [322507] = { cd = 60 },  -- Celestial Brew
    [325153] = { cd = 60, dur = 3 },  -- Exploding Keg
    [325197] = { cd = 120, dur = 25 },  -- Invoke Chi-Ji, the Red Crane
    [325361] = { dur = 6.5 },  -- Glyph of Destruction
    [326707] = { dur = 3 },  -- Cleansing Pain
    [326994] = { dur = 3.5 },  -- Blood Price
    [327122] = { dur = 6 },  -- Ravage
    [328117] = { dur = 10 },  -- March of the Penitent
    [329455] = { dur = 10 },  -- Desolate
    [329770] = { dur = 21.5 },  -- Root of Extinction (Seeds)
    [330959] = { dur = 36 },  -- Danse Macabre
    [331314] = { dur = 12 },  -- Destructive Impact
    [331634] = { dur = 6 },  -- Dark Recital
    [332318] = { dur = 4 },  -- Destructive Stomp
    [332619] = { dur = 3 },  -- Shattering Pain
    [332687] = { dur = 2 },  -- Colossal Roar
    [332937] = { dur = 6 },  -- Ravage
    [334498] = { dur = 5 },  -- Seismic Upheaval
    [334522] = { dur = 10 },  -- Consume
    [334765] = { dur = 36 },  -- Heart Rend
    [334797] = { dur = 2.5 },  -- Rip Soul
    [334942] = { dur = 2.5 },  -- Vicious Lunge
    [342246] = { cd = 60 },  -- Alter Time
    [342281] = { dur = 1.5 },  -- Lingering Anima (Soak)
    [342544] = { dur = 2 },  -- Pulverizing Meteor
    [342863] = { dur = 3 },  -- Echoing Screech
    [343393] = { cd = 90, dur = 15 },  -- Sunblood Amethyst
    [343527] = { cd = 60, dur = 8 },  -- Execution Sentence
    [345397] = { dur = 12 },  -- Wave of Blood
    [345739] = { cd = 90 },  -- Grim Codex
    [345801] = { cd = 120, dur = 16 },  -- Soulletting Ruby
    [346530] = { dur = 10 },  -- Spike
    [347350] = { dur = 30 },  -- Dancing Fever
    [347369] = { dur = 180 },  -- The Jailer's Gaze
    [347609] = { dur = 3 },  -- Wailing Arrow
    [347670] = { dur = 9 },  -- Shadow Dagger
    [347726] = { dur = 5 },  -- Veil of Darkness
    [347740] = { dur = 15 },  -- Hungering Mist
    [348109] = { dur = 9 },  -- Banshee Wail
    [348513] = { dur = 6 },  -- Hammer
    [348987] = { dur = 9 },  -- Break Shackles
    [349030] = { dur = 8 },  -- Titanic Death Gaze
    [349419] = { dur = 7 },  -- Chains
    [350039] = { dur = 8 },  -- Arthura's Crushing Gaze
    [350469] = { dur = 10 },  -- Malevolence
    [350542] = { dur = 12 },  -- Fragments of Destiny
    [350732] = { dur = 2 },  -- Sunder
    [350828] = { dur = 2 },  -- Deathlink
    [351066] = { dur = 2.6 },  -- Shatter
    [351067] = { dur = 2.6 },  -- Shatter
    [351073] = { dur = 2.6 },  -- Shatter
    [351117] = { dur = 9 },  -- Crushing Dread
    [351353] = { dur = 1 },  -- Banshee's Fury
    [351680] = { dur = 8 },  -- Destiny
    [352538] = { dur = 5 },  -- Purging Protocol
    [352589] = { dur = 6 },  -- Meltdown
    [352933] = { dur = 30 },  -- Dance
    [354011] = { dur = 0.5 },  -- Bane Arrows
    [354068] = { dur = 1 },  -- Banshee's Fury
    [354265] = { dur = 6 },  -- Twist Fate
    [355294] = { dur = 12 },  -- Resentment
    [355352] = { dur = 2 },  -- Obliterate
    [355571] = { dur = 6 },  -- Axe
    [355787] = { dur = 6 },  -- Scythe
    [355936] = { cd = 30 },  -- Dream Breath
    [356021] = { dur = 2 },  -- Dark Communion (Orbs)
    [356870] = { dur = 1.5 },  -- Flameclasp Trap
    [357170] = { cd = 60, dur = 8 },  -- Time Dilation
    [358704] = { dur = 1.5 },  -- Arrow
    [359033] = { dur = 45 },  -- Intermission
    [359483] = { dur = 3.4 },  -- Domination Core
    [359770] = { dur = 7 },  -- Ravening Burrow
    [359816] = { cd = 120, dur = 15 },  -- Dreamflight
    [359829] = { dur = 2.5 },  -- Dust Flail
    [359975] = { dur = 2.5 },  -- Riftmaw
    [359979] = { dur = 2.5 },  -- Rend
    [360006] = { dur = 2.5 },  -- Cloud of Carrion
    [360145] = { dur = 10 },  -- Fearful Trepidation
    [360194] = { cd = 120, dur = 16 },  -- Deathmark
    [360279] = { dur = 7 },  -- Rune of Damnation
    [360295] = { dur = 30 },  -- Necrotic Ritual
    [360300] = { dur = 20 },  -- Swarm of Decay
    [360373] = { dur = 2 },  -- Unholy Attunement
    [360412] = { dur = 10 },  -- Exposed Core
    [360414] = { dur = 45 },  -- Pneumatic Impact
    [360451] = { dur = 6.5 },  -- Retch
    [360687] = { dur = 2 },  -- Runecarver's Deathtouch
    [360960] = { dur = 6 },  -- Staggering Barrage
    [360977] = { dur = 3 },  -- Lightshatter Beam
    [361200] = { dur = 20 },  -- Recharge (intermission / mythic)
    [361513] = { dur = 3 },  -- Obliteration Arc
    [361568] = { dur = 3 },  -- Withering Seeds
    [361676] = { dur = 1.5 },  -- Earthbreaker Missiles
    [361789] = { dur = 6 },  -- Hand of Destruction
    [361989] = { dur = 8.75 },  -- Blasphemy
    [362028] = { dur = 6 },  -- Relentless Domination
    [362275] = { dur = 1 },  -- Adds
    [362405] = { dur = 35 },  -- Kingsmourne Hungers
    [362569] = { dur = 8 },  -- Frost Blast
    [362601] = { dur = 1.9 },  -- Unstable Mote (Mines)
    [362617] = { dur = 6 },  -- Oppression
    [362721] = { dur = 8 },  -- Dimensional Tear
    [362801] = { dur = 5.5 },  -- Glyph of Relocation
    [362805] = { dur = 10 },  -- Disintegration Halo
    [362885] = { dur = 2 },  -- Stasis Trap
    [363088] = { dur = 3 },  -- Cosmic Shift (Knock)
    [363130] = { dur = 4 },  -- Synthesize (Intermission start)
    [363332] = { dur = 15 },  -- Unbreaking Grasp
    [363534] = { cd = 180 },  -- Rewind
    [363893] = { dur = 3.6 },  -- Martyrdom
    [363916] = { cd = 150, dur = 12 },  -- Obsidian Scales
    [364114] = { dur = 5 },  -- Shatter Sphere
    [364652] = { dur = 1.9 },  -- Protoform Cascade (Frontal)
    [364881] = { dur = 6 },  -- Matter Dissolution
    [364904] = { dur = 10 },  -- Anti-Matter
    [364941] = { dur = 12 },  -- Windswept Wings
    [364962] = { dur = 999 },  -- Core Overload
    [364979] = { dur = 5.74 },  -- Shatter
    [365030] = { dur = 3 },  -- Wicked Star
    [365033] = { dur = 6 },  -- Desolation
    [365126] = { dur = 2 },  -- Wracking Pain
    [365150] = { dur = 6 },  -- Rune of Domination
    [365169] = { dur = 1.5 },  -- Defile
    [365212] = { dur = 1.5 },  -- Chains of Anguish
    [365295] = { dur = 2 },  -- Befouled Barrier
    [365350] = { cd = 90, dur = 12 },  -- Arcane Surge
    [365805] = { dur = 3.5 },  -- Empowered Hopebreaker
    [365958] = { dur = 2.75 },  -- Hopelessness
    [367079] = { dur = 3 },  -- Seismic Tremors
    [368847] = { cd = 20, dur = 12 },  -- Firestorm
    [370537] = { cd = 90, dur = 30 },  -- Stasis
    [370553] = { cd = 120 },  -- Tip the Scales
    [370615] = { dur = 3.5 },  -- Molten Cleave
    [370665] = { cd = 60 },  -- Rescue
    [370960] = { cd = 180, dur = 5 },  -- Emerald Communion
    [370966] = { cd = 90, dur = 6 },  -- The Hunt
    [371976] = { dur = 7 },  -- Chilling Blast
    [372056] = { dur = 1.5 },  -- Crush
    [372082] = { dur = 7 },  -- Enveloping Webs
    [372238] = { dur = 9 },  -- Call Spiderlings
    [372322] = { dur = 1.5 },  -- Earthen Pillar
    [372456] = { dur = 8 },  -- Absolute Zero
    [372648] = { dur = 6 },  -- Pervasive Cold
    [373027] = { dur = 9 },  -- Suffocating Webs
    [373059] = { dur = 10 },  -- Primal Blizzard
    [373405] = { dur = 9 },  -- Gossamer Burst
    [373487] = { dur = 5 },  -- Lightning Crash
    [373678] = { dur = 10 },  -- Biting Chill
    [373817] = { dur = 7 },  -- Chilling Aura
    [374022] = { dur = 8 },  -- Searing Carnage
    [374038] = { dur = 6 },  -- Meteor Axes
    [374215] = { dur = 7 },  -- Thunder Strike
    [374227] = { cd = 120, dur = 8 },  -- Zephyr
    [374691] = { dur = 5 },  -- Seismic Rupture
    [374968] = { cd = 120, dur = 10 },  -- Time Spiral
    [375087] = { cd = 120, dur = 14 },  -- Dragonrage
    [375331] = { dur = 4 },  -- Conductive Mark
    [375576] = { cd = 60 },  -- Divine Toll
    [375580] = { dur = 1.5 },  -- Zephyr Slam
    [375871] = { dur = 10.5 },  -- Wildfire
    [376279] = { dur = 2.5 },  -- Concussive Slam
    [376943] = { dur = 14 },  -- Cyclone
    [377166] = { dur = 6.5 },  -- Resonating Annihilation
    [377612] = { dur = 6 },  -- Hurricane Wing / Tempest Wing
    [377658] = { dur = 33 },  -- Electrified Jaws
    [380175] = { dur = 9 },  -- Greatstaff of the Broodkeeper
    [380487] = { dur = 5.5 },  -- Rock Blast
    [381615] = { dur = 8 },  -- Static Charge / Fulminating Charge
    [381755] = { cd = 300 },  -- Earth Elemental
    [381768] = { cd = 120, dur = 20 },  -- Spoils of Neltharus
    [381989] = { dur = 30 },  -- Keep It Rolling
    [382266] = { cd = 30 },  -- Fire Breath
    [382411] = { cd = 30 },  -- Eternity Surge
    [382563] = { dur = 11.5 },  -- Magma Burst
    [383073] = { dur = 3.25 },  -- Shattering Impact
    [383410] = { cd = 120, dur = 15 },  -- Celestial Alignment
    [383781] = { cd = 180, dur = 20 },  -- Algeth'ar Puzzle Box
    [383941] = { cd = 180, dur = 20 },  -- Irideus Fragment
    [384352] = { cd = 60, dur = 8 },  -- Doom Winds
    [385059] = { cd = 45, dur = 4 },  -- Odyn's Fury
    [385068] = { dur = 3 },  -- Ball Lightning (Dodge)
    [385627] = { cd = 60, dur = 14 },  -- Kingsbane
    [385884] = { cd = 150, dur = 20 },  -- Time-Breaching Talon
    [385954] = { cd = 45 },  -- Shield Charge
    [386410] = { dur = 2 },  -- Thunderous Blast
    [387849] = { dur = 50 },  -- Coalescing Storm
    [388007] = { cd = 45, dur = 30 },  -- Blessing of Summer
    [388010] = { cd = 45, dur = 30 },  -- Blessing of Autumn
    [388410] = { dur = 4 },  -- Crosswinds
    [388643] = { dur = 3 },  -- Volatile Current
    [388716] = { dur = 6.5 },  -- Icy Shroud
    [389870] = { dur = 3.5 },  -- Storm Break (Teleport)
    [390163] = { cd = 60, dur = 2 },  -- Sigil of Spite
    [390715] = { dur = 7.5 },  -- Flamerift
    [390796] = { dur = 5 },  -- Erupting Bedrock
    [390920] = { dur = 5 },  -- Shocking Burst
    [391019] = { dur = 6 },  -- Frigid Torrent
    [391055] = { dur = 1.5 },  -- Enveloping Earth
    [391268] = { dur = 3 },  -- Earth Smite
    [391382] = { dur = 4 },  -- Blowback
    [391528] = { cd = 60, dur = 4 },  -- Convoke the Spirits
    [391600] = { dur = 15 },  -- Conductive Mark
    [392360] = { dur = 9 },  -- Reforestation
    [392983] = { cd = 40, dur = 6 },  -- Strike of the Windlord
    [396023] = { dur = 2.5 },  -- Incinerating Roar
    [396269] = { dur = 1.5 },  -- Mortal Stoneslam
    [396351] = { dur = 2 },  -- Infused Fallout
    [399713] = { dur = 8 },  -- Magnetic Charge
    [400777] = { dur = 5 },  -- Charged Smash
    [401306] = { cd = 60 },  -- Elementium Pocket Anvil
    [401316] = { dur = 3 },  -- Hellsteel Carnage
    [401325] = { dur = 27 },  -- Burning Claws
    [401383] = { dur = 2 },  -- Oppressing Howl
    [401810] = { dur = 10 },  -- Glittering Surge
    [402050] = { dur = 6 },  -- Searing Breath
    [402583] = { cd = 150 },  -- Beacon to the Beyond
    [402989] = { dur = 7.5 },  -- Molten Spittle
    [403057] = { dur = 10 },  -- Surrender to Corruption
    [403203] = { dur = 2 },  -- Flame Slash
    [403272] = { dur = 5 },  -- Echoing Fissure
    [403326] = { dur = 20 },  -- Wings of Extinction
    [403459] = { dur = 3 },  -- Coalescing Void
    [403517] = { dur = 8 },  -- Embrace of Nothingness (Meteor)
    [403625] = { dur = 5.5 },  -- Scouring Eternity (Hide)
    [403631] = { cd = 120, dur = 12 },  -- Breath of Eons
    [403671] = { dur = 4 },  -- Overpowering Stomp
    [403699] = { dur = 2 },  -- Shadow Spike
    [403740] = { dur = 2.5 },  -- Igniting Roar
    [403741] = { dur = 5.5 },  -- Cosmic Ascension
    [403978] = { dur = 3 },  -- Blast Wave
    [404456] = { dur = 2.5 },  -- Abyssal Breath
    [404713] = { dur = 4 },  -- Bellowing Roar
    [404732] = { dur = 5 },  -- Fiery Meteor
    [404744] = { dur = 25 },  -- Terror Claws
    [404846] = { dur = 1.5 },  -- Incinerating Maws
    [404896] = { dur = 1 },  -- Molten Eruption
    [404977] = { cd = 180 },  -- Time Skip
    [405016] = { cd = 6, dur = 2 },  -- Umbral Detonation
    [405042] = { dur = 3 },  -- Unstable Essence
    [405433] = { dur = 3 },  -- Umbral Annihilation
    [405437] = { dur = 5 },  -- Gloom Conflagration
    [405812] = { dur = 3 },  -- Animate Golems
    [405821] = { dur = 5 },  -- Charged Smash
    [405914] = { dur = 2 },  -- Withering Vulnerability
    [406222] = { dur = 2 },  -- Calamitous Strike
    [406227] = { dur = 6 },  -- Deep Breath
    [406358] = { dur = 5 },  -- Rending Charge
    [406678] = { dur = 3 },  -- Tactical Destruction
    [406732] = { cd = 120, dur = 10 },  -- Spatial Paradox
    [406789] = { cd = 120, dur = 10 },  -- Spatial Paradox
    [407207] = { dur = 5 },  -- Rushing Darkness
    [407496] = { dur = 11 },  -- Infinite Duress (Knock)
    [407552] = { dur = 2 },  -- Temporal Anomaly
    [407641] = { dur = 5 },  -- Wrath of Djaruun
    [407775] = { dur = 3 },  -- Violent Eruption
    [407790] = { dur = 6.5 },  -- Sunder Shadow
    [407917] = { dur = 6 },  -- Ebon Destruction
    [408193] = { dur = 1 },  -- Convergent Eruption
    [408422] = { dur = 3 },  -- Void Slash
    [408959] = { dur = 4.3 },  -- Devastating Leap
    [409359] = { dur = 10 },  -- Desperate Immolation
    [410223] = { dur = 3 },  -- Shadowflame Breath
    [410516] = { dur = 4.3 },  -- Catastrophic Slam
    [410968] = { dur = 7 },  -- Volcanic Heart
    [411236] = { dur = 28 },  -- Void Claws
    [414658] = { cd = 240, dur = 6 },  -- Ice Cold
    [415624] = { dur = 1.5 },  -- Heart Stopper
    [416048] = { dur = 4.5 },  -- Umbral Destruction
    [417131] = { cd = 120, dur = 3 },  -- Rage of Fyr'alath
    [417431] = { dur = 2.43 },  -- Fyr'alath's Bite
    [417455] = { dur = 10.43 },  -- Dream Rend
    [417634] = { dur = 10 },  -- Raging Inferno
    [417939] = { cd = 120 },  -- Echoing Tyrstone
    [418527] = { cd = 180, dur = 20 },  -- Mirror of Fractured Tomorrows
    [418531] = { dur = 3 },  -- Smashing Viscera
    [418757] = { dur = 12 },  -- Polymorph Bomb
    [419123] = { dur = 5 },  -- Flamefall
    [419278] = { cd = 180 },  -- Iridal, the Earth's Master
    [419506] = { dur = 6 },  -- Firestorm
    [420236] = { dur = 2 },  -- Falling Star
    [420525] = { dur = 12.5 },  -- Blind Rage
    [420907] = { dur = 7.5 },  -- Viridian Rain
    [420933] = { dur = 5 },  -- Flood of the Firelands
    [420947] = { dur = 12.5 },  -- Barreling Charge
    [421020] = { dur = 18 },  -- Agonizing Claws
    [421029] = { dur = 6 },  -- Song of the Dragon
    [421284] = { dur = 1.6 },  -- Coiling Flames
    [421292] = { dur = 22 },  -- Constricting Thicket
    [421316] = { dur = 18 },  -- Consuming Flame
    [421343] = { dur = 3 },  -- Brand of Damnation
    [421398] = { dur = 2 },  -- Fire Beam
    [421453] = { cd = 240, dur = 6 },  -- Ultimate Penitence
    [421455] = { dur = 10 },  -- Overheated
    [421840] = { dur = 20 },  -- Uprooted Agony
    [422026] = { dur = 12.5 },  -- Tortured Scream
    [422083] = { cd = 120, dur = 24 },  -- Smoldering Seedling
    [422146] = { cd = 120, dur = 12 },  -- Belor'relos, the Suncaller
    [422172] = { dur = 30 },  -- World In Flames
    [422303] = { cd = 90, dur = 3 },  -- Bandolier of Twisted Blades
    [422441] = { cd = 150 },  -- Branch of the Tormented Ancient
    [422776] = { dur = 1.6 },  -- Marked for Torment
    [422837] = { dur = 12 },  -- Apocalypse Roar
    [422956] = { cd = 120, dur = 18 },  -- Nymue's Unraveling Spindle
    [423117] = { dur = 2.5 },  -- Cataclysm Jaws
    [423260] = { dur = 10.5 },  -- Blazing Mushroom
    [423265] = { dur = 10 },  -- Flaming Germination
    [423611] = { cd = 120, dur = 20 },  -- Ashes of the Embersoul
    [424352] = { dur = 4 },  -- Dreadfire Barrage
    [424495] = { dur = 5 },  -- Mass Entanglement
    [424581] = { dur = 12 },  -- Fiery Growth
    [425025] = { dur = 10 },  -- Furious Outburst
    [425492] = { dur = 1 },  -- Infernal Maw
    [426368] = { dur = 2 },  -- Darkflame Cleave
    [426519] = { dur = 14 },  -- Weaver's Burden
    [426591] = { cd = 45, dur = 14 },  -- Goremaw's Bite
    [427113] = { cd = 120, dur = 2 },  -- Dreambinder, Loom of the Great Cycle
    [427319] = { dur = 18 },  -- Flash Fire
    [429257] = { cd = 90 },  -- Witherbark's Branch
    [429973] = { dur = 2.5 },  -- Smoldering Backdraft
    [431416] = { cd = 300 },  -- Health Pot
    [431418] = { cd = 300 },  -- Algari Mana Potion
    [431932] = { cd = 300, dur = 30 },  -- Tempered Potion
    [433519] = { cd = 20, dur = 1.5 },  -- Phase Blades
    [433874] = { cd = 120 },  -- Deep Breath
    [434697] = { dur = 19 },  -- Brutal Crush
    [434803] = { dur = 8 },  -- Carnivorous Contest
    [435136] = { dur = 6 },  -- Venomous Lash
    [435138] = { dur = 8 },  -- Digestive Acid
    [435403] = { dur = 30 },  -- Phase Lunge
    [435405] = { dur = 29 },  -- Starless Night
    [436203] = { dur = 3.7 },  -- Juggernaut Charge
    [436358] = { cd = 45, dur = 2 },  -- Demolish
    [436971] = { dur = 6 },  -- Assassination
    [437093] = { dur = 1 },  -- Feast
    [437592] = { cd = 5, dur = 6 },  -- Reactive Toxin
    [437620] = { dur = 10 },  -- Nether Rift
    [438012] = { dur = 3 },  -- Hungering Bellows
    [438245] = { dur = 6 },  -- Twilight Massacre
    [438343] = { cd = 10, dur = 1.5 },  -- Venomous Rain
    [438677] = { dur = 2 },  -- Stinging Swarm
    [439784] = { dur = 2 },  -- Spinneret's Strands
    [439789] = { dur = 2 },  -- Rolling Acid
    [439795] = { dur = 4 },  -- Web Reave
    [439811] = { cd = 24, dur = 5.5 },  -- Erosive Spray
    [439814] = { dur = 4 },  -- Silken Tomb
    [439843] = { cd = 45, dur = 12 },  -- Reaper's Mark
    [440179] = { dur = 12 },  -- Entangled
    [440377] = { dur = 35 },  -- Void Shredders
    [440899] = { dur = 1.5 },  -- Liquefy
    [441626] = { cd = 16, dur = 2 },  -- Web Vortex
    [441791] = { cd = 12, dur = 1.8 },  -- Burrowed Eruption
    [442428] = { dur = 2 },  -- Decimate
    [442432] = { dur = 16 },  -- Ingest Black Blood
    [442526] = { dur = 7.5 },  -- Experimental Dosage
    [442530] = { cd = 10, dur = 8 },  -- Goresplatter
    [442726] = { cd = 60, dur = 20 },  -- Malevolence
    [442994] = { dur = 9 },  -- Unleashed Swarm
    [443003] = { dur = 9.5 },  -- Volatile Concoction
    [443028] = { cd = 90, dur = 4 },  -- Celestial Conduit
    [443124] = { cd = 120 },  -- Mad Queen's Mandate
    [443325] = { cd = 4.5, dur = 1.5 },  -- Infest
    [443336] = { cd = 6, dur = 1.5 },  -- Royal Condemnation
    [443337] = { cd = 90 },  -- Charged Stormrook Plume
    [443407] = { cd = 90, dur = 15 },  -- Skarmorak Shard
    [443529] = { cd = 90 },  -- Burin of the Candle King
    [443531] = { cd = 120, dur = 20 },  -- Signet of the Priory
    [443536] = { cd = 120 },  -- Bursting Lightshard
    [443888] = { dur = 7 },  -- Abyssal Infusion
    [444282] = { cd = 90 },  -- Creeping Coagulum
    [444363] = { cd = 40, dur = 5 },  -- Gruesome Disgorge
    [444489] = { dur = 20 },  -- Skyterror's Corrosive Organ
    [444687] = { dur = 1.5 },  -- Savage Assault
    [444829] = { dur = 3 },  -- Queen's Summons
    [444959] = { dur = 20 },  -- Spymaster's Web
    [445123] = { dur = 5 },  -- Hulking Crash
    [445422] = { dur = 5 },  -- Frothing Gluttony
    [446035] = { cd = 90, dur = 6 },  -- Bladestorm
    [446344] = { dur = 5 },  -- Sticky Web
    [447411] = { dur = 6 },  -- Wrest
    [448904] = { cd = 90 },  -- Ravenous Honey Buzzer
    [449946] = { cd = 90, dur = 15 },  -- Treacherous Transmitter
    [452806] = { dur = 2.5 },  -- Acidic Eruption
    [452930] = { cd = 60, dur = 6 },  -- Demonic Healthstone
    [455373] = { cd = 2.5, dur = 2.5 },  -- Infested Spawn
    [456245] = { dur = 12 },  -- Stinging Delirium
    [456420] = { dur = 5 },  -- Shattering Sweep
    [459627] = { cd = 25, dur = 1.5 },  -- Tank Buster
    [459671] = { dur = 12 },  -- Spew Oil
    [459943] = { dur = 1 },  -- Call Bikers
    [460181] = { dur = 4 },  -- Pay-Line
    [460472] = { cd = 30, dur = 2.5 },  -- The Big Hit
    [461060] = { cd = 30, dur = 2 },  -- Spin To Win!
    [463798] = { dur = 4 },  -- Lightning Bash
    [463900] = { dur = 8 },  -- Thunderdrum Salvo
    [464112] = { cd = 50, dur = 1.25 },  -- Demolish
    [464149] = { dur = 3 },  -- Incinerator
    [464399] = { cd = 5, dur = 1 },  -- Electromagnetic Sorting
    [464584] = { dur = 37 },  -- Sound Cloud
    [464772] = { dur = 10 },  -- Reward
    [465232] = { cd = 10, dur = 2 },  -- Sonic Ba-Boom
    [465872] = { dur = 20 },  -- Colossal Clash
    [465952] = { cd = 4.5, dur = 3 },  -- Big Bad Buncha Bombs
    [466340] = { cd = 30, dur = 3 },  -- Scatterblast Canisters
    [466342] = { dur = 3 },  -- Tick-Tock Canisters
    [466470] = { dur = 2 },  -- Frostshatter Boots
    [466509] = { dur = 7 },  -- Stormfury Finger Gun
    [466539] = { dur = 3.5 },  -- Unstable Crawler Mines
    [466545] = { dur = 6.5 },  -- Spray and Pray
    [466652] = { cd = 90, dur = 5 },  -- Vexie's Pit Whistle
    [466673] = { cd = 30 },  -- Scrapfield 9001
    [466681] = { cd = 90, dur = 15 },  -- House of Cards
    [466751] = { cd = 4, dur = 1 },  -- Venting Heat
    [466810] = { cd = 90, dur = 20 },  -- Chromebustible Bomb Suit
    [466860] = { dur = 20 },  -- Bleeding Edge
    [466958] = { cd = 22, dur = 1.5 },  -- Molten Gold Knuckles
    [466961] = { cd = 12, dur = 2.125 },  -- Faulty Zap
    [467117] = { dur = 10 },  -- Overdrive / Trash Compactor
    [467182] = { dur = 4.5 },  -- Suppression
    [467201] = { cd = 10, dur = 2.5 },  -- Molten Gold Knuckles
    [467379] = { dur = 10 },  -- Goblin-guided Rocket
    [467606] = { dur = 5 },  -- Sound Cannon
    [468149] = { dur = 6 },  -- Exhaust Fumes
    [468207] = { dur = 6 },  -- Incendiary Fire
    [469993] = { dur = 5 },  -- Foul Exhaust
    [470286] = { cd = 120, dur = 15 },  -- Torq's Big Red Button
    [471142] = { cd = 120, dur = 15 },  -- Flarendo's Pilot Light
    [471212] = { cd = 20, dur = 6 },  -- Junkmaestro's Mega Magnet
    [471214] = { cd = 90, dur = 4 },  -- Gallagio Bottle Service
    [472233] = { cd = 3, dur = 3.5 },  -- Blastburn Roarcannon
    [472433] = { cd = 90 },  -- Evangelism
    [472631] = { dur = 10 },  -- Earthshaker Gaol
    [473260] = { dur = 5 },  -- Blaring Drop
    [473276] = { dur = 1 },  -- Activate Inventions!
    [473650] = { dur = 10 },  -- Scrapbomb
    [473748] = { dur = 3.3 },  -- Amplification!
    [1214190] = { dur = 4 },  -- Eruption Stomp
    [1214688] = { dur = 5 },  -- Sparkblast Ignition
    [1214872] = { dur = 1.5 },  -- Pyro Party Pack
    [1215488] = { dur = 12 },  -- Disintegration Beam
    [1216508] = { cd = 4.5, dur = 2 },  -- Screw Up
    [1217231] = { dur = 1.5 },  -- Foot-Blasters
    [1217355] = { dur = 4 },  -- Polarization Generator
    [1217953] = { cd = 10, dur = 3 },  -- Giga Blast
    [1217954] = { cd = 3, dur = 1 },  -- Meltdown
    [1218103] = { dur = 4 },  -- Eye Beam
    [1218418] = { dur = 2 },  -- Wire Transfer
    [1219102] = { cd = 120, dur = 10 },  -- Ringing Ritual Mud
    [1219263] = { dur = 6 },  -- Obliteration Arcanocannon
    [1219450] = { dur = 6 },  -- Manifest Matrices
    [1219531] = { dur = 5 },  -- Eradicating Salvo
    [1220394] = { dur = 2 },  -- Shattering Backhand
    [1220488] = { cd = 120, dur = 15 },  -- Darkfuse Medichopper
    [1221622] = { dur = 8 },  -- Awaken Fungi
    [1221637] = { dur = 16 },  -- Fungal Bloom
    [1221781] = { dur = 2 },  -- Putrid Fist
    [1221787] = { dur = 2 },  -- Bursting Postules
    [1222088] = { dur = 8 },  -- Festering Vines
    [1222232] = { dur = 13 },  -- Devourer's Ire
    [1223085] = { dur = 2.5 },  -- Double Whammy Shot
    [1224787] = { dur = 4 },  -- Conquer
    [1224812] = { dur = 2.5 },  -- Vanquish
    [1224864] = { dur = 24 },  -- Behead
    [1225582] = { dur = 3 },  -- Soul Calling
    [1225616] = { dur = 8 },  -- Soulfire Convergence
    [1226024] = { dur = 6 },  -- Starkiller Swing
    [1226395] = { dur = 8 },  -- Overinfusion Burst
    [1226648] = { dur = 4 },  -- Galactic Smash
    [1227117] = { dur = 4.5 },  -- Fel Devastation
    [1227226] = { cd = 25, dur = 4 },  -- Writhing Wave
    [1227263] = { cd = 45, dur = 3 },  -- Piercing Strand
    [1227276] = { dur = 6 },  -- Soulfray Annihilation
    [1227355] = { dur = 2.5 },  -- Voidstep
    [1227549] = { dur = 8 },  -- Banishment
    [1227631] = { dur = 5 },  -- Arcane Expulsion
    [1227734] = { dur = 6.2 },  -- Coalesce Voidwing
    [1227782] = { cd = 4, dur = 2 },  -- Arcane Outrage
    [1227809] = { dur = 6 },  -- The Hunt
    [1228053] = { dur = 1 },  -- Reap
    [1228075] = { dur = 7 },  -- Nexus Beams
    [1228115] = { dur = 7 },  -- Netherbreaker
    [1228163] = { dur = 4 },  -- Dimension Breath
    [1228213] = { dur = 7 },  -- Astral Harvest
    [1228216] = { dur = 7 },  -- Astral Harvest
    [1228502] = { cd = 46, dur = 1.2 },  -- Overwhelming Power
    [1229038] = { dur = 5 },  -- Devour
    [1230087] = { dur = 4 },  -- Massive Smash
    [1230263] = { dur = 3 },  -- Netherblast
    [1230979] = { dur = 4 },  -- Dark Matter
    [1231716] = { dur = 10 },  -- Extinguish The Stars
    [1231720] = { dur = 5 },  -- Invoke Collector
    [1231871] = { dur = 4 },  -- Shockwave Slam
    [1232221] = { dur = 3.5 },  -- Death Throes
    [1232399] = { dur = 4.5 },  -- Dread Mortar
    [1232467] = { dur = 8 },  -- Grasp of Emptiness
    [1232721] = { cd = 90, dur = 10 },  -- Loom'ithar's Living Silk
    [1232802] = { cd = 120, dur = 30 },  -- Araz's Ritual Forge
    [1232973] = { dur = 5 },  -- Supernova
    [1233093] = { dur = 25 },  -- Collapsing Star
    [1233272] = { cd = 32, dur = 15 },  -- Lunar Eclipse
    [1233346] = { cd = 32, dur = 15 },  -- Solar Eclipse
    [1233415] = { dur = 12 },  -- Mana Splinter
    [1233416] = { dur = 10 },  -- Crystalline Shockwave
    [1233448] = { cd = 45, dur = 15 },  -- Dark Transformation
    [1233556] = { dur = 20 },  -- Unyielding Netherprism
    [1233787] = { dur = 2 },  -- Dark Hand
    [1233819] = { dur = 6 },  -- Void Expulsion
    [1233863] = { dur = 24 },  -- Fel Rush
    [1233865] = { dur = 10 },  -- Null Corona
    [1234044] = { dur = 8 },  -- Darkened Sky
    [1234263] = { dur = 4 },  -- Cosmic Collapse
    [1234529] = { dur = 1.25 },  -- Cosmic Maw
    [1234768] = { cd = 300 },  -- Silvermoon Health Potion
    [1235425] = { cd = 60, dur = 20 },  -- Soulbinder's Embrace
    [1236616] = { cd = 300, dur = 30 },  -- Light's Potential
    [1236648] = { cd = 300 },  -- Lightfused Mana Potion
    [1236994] = { cd = 300, dur = 30 },  -- Potion of Recklessness
    [1237272] = { dur = 5 },  -- Lair Weaving
    [1237614] = { dur = 6 },  -- Ranger Captain's Mark
    [1237694] = { dur = 4 },  -- Mass Ejection
    [1237837] = { dur = 2 },  -- Call of the Void
    [1238009] = { cd = 300 },  -- Health Pot
    [1238765] = { dur = 8.5 },  -- Extinction
    [1238843] = { dur = 4 },  -- Devouring Cosmos
    [1239080] = { dur = 8 },  -- Aspect of the End
    [1239262] = { dur = 2.5 },  -- Conqueror's Cross
    [1240891] = { dur = 2.5 },  -- Sigil of Chains
    [1241059] = { cd = 45 },  -- Celestial Infusion
    [1241100] = { dur = 4 },  -- Mystic Lash
    [1241291] = { dur = 8 },  -- Light Dive
    [1241768] = { dur = 5 },  -- Shadowclaw Slam
    [1241833] = { dur = 8 },  -- Fracture
    [1242088] = { cd = 15, dur = 4 },  -- Arcane Expulsion
    [1242259] = { dur = 8 },  -- Spirit Bomb
    [1242260] = { dur = 6 },  -- Infused Quills
    [1242515] = { dur = 6 },  -- Voidlight Convergence
    [1243743] = { dur = 5 },  -- Interrupting Tremor
    [1243887] = { dur = 7 },  -- Void Harvest
    [1243981] = { dur = 2 },  -- Silverstrike Barrage
    [1244029] = { cd = 90, dur = 15 },  -- Lily of the Eternal Weave
    [1244221] = { dur = 4 },  -- Dread Breath
    [1244917] = { dur = 2.5 },  -- Void Howl
    [1245391] = { dur = 4 },  -- Gloom
    [1245396] = { dur = 10 },  -- Consume
    [1245404] = { dur = 3.5 },  -- Ravenous Dive
    [1245645] = { dur = 1.5 },  -- Rakfang
    [1246167] = { cd = 90, dur = 6 },  -- The Hunt
    [1246175] = { dur = 20 },  -- Entropic Unraveling
    [1246487] = { dur = 6 },  -- Avenger's Shield
    [1246653] = { dur = 12 },  -- Caustic Phlegm
    [1246709] = { dur = 30.5 },  -- Death Drop + Rebirth
    [1246736] = { dur = 3 },  -- Judgment
    [1246918] = { dur = 3 },  -- Cosmic Barrier
    [1247738] = { dur = 3 },  -- Void Convergence
    [1248449] = { dur = 15 },  -- Aura of Wrath
    [1248451] = { dur = 25 },  -- Aura of Peace
    [1248644] = { dur = 20 },  -- Divine Toll
    [1248697] = { dur = 14 },  -- Despotic Command
    [1248710] = { dur = 20 },  -- Tyr's Wrath
    [1248847] = { dur = 25 },  -- Radiant Barrier
    [1248994] = { dur = 10 },  -- Execution Sentence
    [1249265] = { dur = 5.5 },  -- Umbral Collapse
    [1249609] = { dur = 11.5 },  -- Dark Rune
    [1249625] = { cd = 90, dur = 15 },  -- Zenith
    [1249658] = { cd = 90 },  -- Breath of Sindragosa
    [1249748] = { dur = 20 },  -- Midnight Flames
    [1250646] = { cd = 90, dur = 8 },  -- Takedown
    [1251361] = { dur = 3 },  -- Shadow's Advance
    [1251386] = { dur = 4 },  -- Safeguard Prism
    [1251857] = { dur = 3 },  -- Judgment
    [1253032] = { dur = 5 },  -- Shattering Twilight
    [1253915] = { dur = 3 },  -- Heaven's Glaives
    [1254081] = { dur = 6 },  -- Fractured Projection
    [1254199] = { dur = 6 },  -- Parasite Expulsion
    [1255738] = { dur = 15 },  -- Searing Radiance
    [1256855] = { dur = 15 },  -- Void Breath
    [1257052] = { cd = 60, dur = 3 },  -- Dark Harvest
    [1257087] = { dur = 8 },  -- Consuming Miasma
    [1258150] = { dur = 2 },  -- Pop!
    [1258610] = { dur = 3 },  -- Rift Emergence
    [1258673] = { dur = 4 },  -- Swirling Whirlpools
    [1258880] = { dur = 20 },  -- Void Fall
    [1260052] = { dur = 5 },  -- Primordial Roar
    [1260459] = { cd = 90, dur = 15 },  -- Vaelgor's Final Stare
    [1260633] = { cd = 120 },  -- Gloom-Spattered Dreadscale
    [1260712] = { dur = 3 },  -- Oblivion's Wrath
    [1260837] = { dur = 4 },  -- Abyssal Rain
    [1261193] = { cd = 60, dur = 3 },  -- Boomstick
    [1262289] = { dur = 5 },  -- Alndust Upheaval
    [1262623] = { dur = 4 },  -- Nullbeam
    [1265131] = { dur = 1.5 },  -- Vaelwing
    [1267049] = { dur = 2.5 },  -- Heaven's Lance
    [1276452] = { cd = 120, dur = 20 },  -- Grimoire: Imp Lord
    [1276467] = { cd = 120, dur = 20 },  -- Grimoire: Fel Ravager
    [1276672] = { cd = 120, dur = 12 },  -- Summon Doomguard
    [1277027] = { dur = 3 },  -- Mutilate
    [1280935] = { dur = 2 },  -- Dripping Fangs
    [1281951] = { dur = 6 },  -- Water Jet
    [1282043] = { dur = 6 },  -- Into the Darkwell
    [1282412] = { dur = 3 },  -- Core Harvest
    [1282487] = { dur = 8 },  -- Fangs of the Coiled Altar
    [1282516] = { dur = 5 },  -- Malignant Catalyst
    [1282937] = { dur = 5 },  -- Iceblade Flurry
    [1283489] = { dur = 5 },  -- Guillotine
    [1283623] = { dur = 6 },  -- Widow's Kiss
    [1283832] = { dur = 3 },  -- Axegrinder
    [1284015] = { dur = 45 },  -- Alluring Bubble
    [1284103] = { dur = 6 },  -- Possession Barrage
    [1284251] = { dur = 1.5 },  -- Venom Coagulation
    [1284434] = { dur = 16 },  -- Toxic Droplets
    [1284458] = { dur = 1.5 },  -- Empowering Slam
    [1284471] = { dur = 8 },  -- Blighted Blood
    [1284487] = { dur = 1.5 },  -- Bloodvenom Injection
    [1284525] = { dur = 6 },  -- Galvanize
    [1284635] = { dur = 30 },  -- Vitriolic Stasis
    [1284663] = { dur = 4 },  -- Imbibe
    [1285425] = { dur = 8 },  -- Raging Crosswinds
    [1285563] = { dur = 30 },  -- Total Eclipse
    [1285643] = { dur = 5 },  -- Dreadmarch
    [1285681] = { dur = 4 },  -- Soulcoil Ignition
    [1286033] = { dur = 25 },  -- Dig In
    [1286441] = { dur = 3 },  -- Spiritcackle
    [1286620] = { dur = 4 },  -- Soul Sever
    [1286860] = { dur = 20 },  -- Rage of the Shackled
    [1286895] = { dur = 5 },  -- Gloombomb
    [1286918] = { dur = 15 },  -- Eternal Nightfall
    [1288232] = { dur = 8 },  -- Unstable Miasma
    [1288538] = { dur = 1.5 },  -- Stone Breaker
    [1289192] = { dur = 5 },  -- Caustic Deluge
    [1290516] = { dur = 4 },  -- Ravenous Feast
    [1290814] = { dur = 12 },  -- Coiling Ichor
    [1290956] = { dur = 6 },  -- Stir the Depths
    [1291404] = { dur = 3 },  -- Venomous Emergence
    [1291894] = { cd = 120, dur = 20 },  -- Soulcoiler Ritual Vessel
    [1292248] = { dur = 15 },  -- Soul Transfer
    [1294293] = { cd = 14, dur = 4 },  -- Vile Flood
    [1295124] = { dur = 20 },  -- Ritual of Awakening
    [1295132] = { cd = 300, dur = 30 },  -- Liquid Luster
    [1295854] = { dur = 3.5 },  -- Shredding Shards
    [1296021] = { dur = 9 },  -- Blink Nova
    [1296062] = { dur = 4 },  -- Shell Spin
    [1296301] = { dur = 4 },  -- Mephitic Thrash
    [1296878] = { dur = 8 },  -- Shifting Protovenom
    [1297075] = { cd = 60 },  -- Final Ascension
    [1297761] = { cd = 90, dur = 20 },  -- Voracious Heart of Ula'tek
    [1297908] = { cd = 240, dur = 2 },  -- Font of Venomous Rage
    [1298367] = { dur = 5 },  -- Mother's Wrath
    [1298381] = { dur = 8 },  -- Defilement of the Coiled Altar
    [1299267] = { dur = 3.5 },  -- Grim Guillotine
    [1299526] = { dur = 20 },  -- Venomous Heart
    [1299673] = { dur = 5 },  -- Invoke
    [1299684] = { dur = 3 },  -- Sever
    [1299960] = { dur = 3 },  -- Toxic Deluge
    [1301117] = { dur = 2 },  -- Grasping Fangs
    [1301213] = { dur = 3 },  -- Shadow Molt
    [1301511] = { dur = 6 },  -- Voidswarm
    [1302950] = { dur = 3 },  -- Writhing Gestation
    [1302951] = { dur = 44 },  -- Suffocating Darkness
    [1303230] = { dur = 5 },  -- Blood Torrent
    [1303406] = { dur = 8 },  -- Abyssal Grasp
    [1304012] = { dur = 4 },  -- Call of the Serpent
    [1304032] = { dur = 35 },  -- Soulbinding
    [1304045] = { dur = 6 },  -- Unspeakable Horrors
    [1304424] = { dur = 8 },  -- Extinguish
    [1305959] = { dur = 12 },  -- Venomous Surge
    [1306872] = { dur = 18 },  -- Sanguine Storm
    [1306906] = { cd = 14, dur = 2 },  -- Venomfang
    [1307292] = { dur = 3 },  -- Blighted Sever
    [1308356] = { dur = 3 },  -- Rouse the Brood
    [1308927] = { dur = 12 },  -- Spectral Coils
    [1311807] = { dur = 6 },  -- Caustic Waves
    [1313393] = { dur = 7.5 },  -- Chilling Frost
}
