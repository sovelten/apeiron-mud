;;;; src/worlds/eridu.lisp — Eridu, the First City
;;;;
;;;; Recreates Eridu (Sumerian: eridug, "the good city"), the southernmost
;;;; of the great Sumerian city-states and — by its own king list — the
;;;; first city of the world, where "kingship descended from heaven."
;;;; It was the seat of Enki (Ea), lord of the Abzu, the freshwater deep
;;;; from which all wisdom and civilization flowed.
;;;;
;;;; The area follows the archaeology of Tell Abu Shahrain in the
;;;; Euphrates marshlands: the mudbrick temple of the E-Abzu on its
;;;; ancient mound, the ziggurat E-engurra, the giparu, the harbor of
;;;; coracles on the Persian Gulf, and the reed quarters that wove the
;;;; marsh into the city.  The lore leans on the Sumerian King List,
;;;; the Eridu Genesis and the flood tradition studied by Irving Finkel
;;;; (the ark tablet) and François Lenormant (the Chaldean origins of
;;;; history).

(in-package #:apeiron.worlds)

(named-readtables:in-readtable pythonic-string-syntax)

(defsection @eridu (:title "Eridu, the First City")
  """Eridu, the first city of the Sumerian civilization, rises from the
  reed marshes where the Euphrates meets the Persian Gulf.  It is the
  city of Enki, lord of the Abzu, the freshwater deep beneath the earth.
  BUILD-ERIDU constructs the city as a self-contained MUD-AREA: the marsh
  causeway, the city gate, the market and harbor, the sacred precinct of
  the E-Abzu with its ziggurat, the House of the Seven Sages, and the
  Abzu itself, guarded by the goat-fish and the Lord of the Deep."""
  (build-eridu function))

;; ─── Eridu ────────────────────────────────────────────────────────────────
;;
;; Layout (north = up):
;;
;;   [Genesis Shrine]                          ← Enki's blessing (blessed-by-enki)
;;        ↑
;;      [The Abzu]                            ← Enki, Lord of the Deep
;;        ↑  (beat-suhur-mashu)
;;   [E-Abzu Temple]                          ← gudug priest, goat-fish
;;        ↑
;;   [House of the] ← [Giparu] ← [Temple Court] → [Ziggurat] → (up) → [Summit]
;;   [Seven Sages]                  ↑                     ↑               (beat-ugallu)
;;                            [Temple Gate]           (east of court)
;;                                              ← riddle: "eridu"
;;                                              ↑
;;   [Date Grove] ← [Market Square] → [Harbor]
;;                      ↑
;;        [Palace] ← [Great Street] → [Reed Quarter]
;;         ↑  (beat-alulim)
;;   [Treasury]
;;                      ↑
;;              [City Gate]
;;                      ↑
;;             [Marsh Causeway]                  ← entrance
;;
;; Gates:
;;   riddle  : Market → Temple Gate — "name the first city"      → answer "eridu"
;;   riddle  : Temple Court → E-Abzu — "name the lord"           → answer "enki"
;;   fight   : E-Abzu → Abzu          — suhur-mashu goat-fish      → "beat-suhur-mashu"
;;   fight   : Palace → Treasury      — Alulim, first king         → "beat-alulim"
;;   fight   : Ziggurat → Summit      — ugallu lion-demon          → "beat-ugallu"
;;   fight   : Abzu → Genesis Shrine  — Enki, Lord of the Deep     → "blessed-by-enki"

(defun build-eridu ()
  "Build the city of Eridu, the first city of Sumer and seat of the god
Enki, as a self-contained MUD-AREA.  The area's entrance is the marsh
causeway at the southern edge of the city.  Returns the area."
  (let ((area (new-area :name "Eridu, the First City")))
    (let* (;; — Streets and gates —──────────────────────────────────────
           (marsh (new-room
                   :name "Marsh Causeway"
                   :description
                   "Reeds taller than a man crowd the causeway, and the air is thick with the smell of mud and brackish water. Far ahead, the sun-baked walls of the first city rise from the marsh — Eridu, where kingship descended from heaven. Bitterns boom in the rushes, and somewhere a fisherman sings."))
           (city-gate (new-room
                       :name "City Gate of Eridu"
                       :description
                       "Two towers of pale mudbrick flank the great gate of Eridu. Above the arch, a faded relief shows the goat-fish, emblem of Enki, and a row of reed bundles — the sacred symbol of the temple. Merchants, fishermen, and reed-binders stream through the gate, while the guards watch you with wary eyes."))
           (street (new-room
                    :name "Great Street of Eridu"
                    :description
                    "The main street of Eridu runs between low houses of mudbrick and reed, their roofs stacked with drying fish and dates. A canal of sweet water runs alongside, its banks busy with women filling jars and boys splashing after ducks. The city hums with the oldest commerce in the world."))
           (reed-quarter (new-room
                          :name "Reed Workers' Quarter"
                          :description
                          "Here the marsh is woven into the city. Bundles of giant reeds lean against every wall; mats, baskets, and fish traps hang drying from the rafters. A reed-binder sits cross-legged, plaiting a mat with the patient rhythm of centuries."))
           (palace (new-room
                    :name "Palace of Alulim"
                    :description
                    "The palace of the first king rises from a mound of its own, its facade of mudbrick glazed in bands of black and red. Guards stand at the cedar door. Within, the air is cool and heavy with incense — Alulim, who ruled 28,800 years, holds court."))
           (treasury (new-room
                      :name "Treasury of the First King"
                      :description
                      "Jars of barley and oil, ingots of copper, and strings of lapis lazuli crowd the treasury. On stone shelves rest offerings from a hundred cities: seals, shells from the gulf, and tablets recording the tribute of the world's first subjects."))
           ;; — The living city —────────────────────────────────────────
           (market (new-room
                    :name "Market Square of Eridu"
                    :description
                    "The market square of Eridu teems with life. Fishermen cry their catch, bakers sell flatbread from clay ovens, and merchants from the gulf bargain over copper and dates. A travellers' tablet stands at the center, where visitors scratch their names."))
           (grove (new-room
                   :name "Date Grove of Eridu"
                   :description
                   "Beyond the houses, a grove of date palms stands in the shelter of the marsh. Bees drone among the blossoms, and the fronds rattle in the sea breeze. Here the sweet dates of Eridu ripen, famous across the land of the two rivers."))
           (harbor (new-room
                    :name "Harbor of Eridu"
                    :description
                    "The harbor opens onto the green sea of the gulf, where round coracles of woven reeds bob at their moorings. Fishermen mend nets beside the quay, and the smell of tar and brine hangs in the air. It was from this water's edge, they say, that the boat of the flood was launched."))
           ;; — The sacred precinct —────────────────────────────────────
           (temple-gate (new-room
                         :name "Temple Gate"
                         :description
                         "A gate of dark wood and bitumen marks the edge of the sacred precinct. A stone tablet stands beside it, inscribed with the names of the antediluvian kings — the line of Eridu. The temple gatekeeper watches you closely. Beyond, the E-Abzu rises on its ancient mound."))
           (temple-court (new-room
                          :name "Temple Court of the E-Abzu"
                          :description
                          "Wide courts paved with baked brick surround the E-Abzu, the House of the Deep. Priests in white robes move in quiet procession, carrying offering bowls of dates and oil. The great temple looms to the north, its walls gleaming with whitewash, its door a mouth of shadow."))
           (giparu (new-room
                    :name "Giparu"
                    :description
                    "The giparu, the sacred residence, is a cluster of quiet rooms around a garden court. Here the priestesses keep the rites of Enki, and here the young scribes learn the cuneiform signs. The air smells of cedar oil and damp clay."))
           (sages (new-room
                   :name "House of the Seven Sages"
                   :description
                   "A long hall where the seven sages — the apkallu, the fish-men of wisdom — are remembered. Bas-reliefs show them rising from the deep to teach mankind the arts of civilization. At the far end, Adapa, first of the sages, sits with a staff of lapis, watching you with ancient eyes."))
           (e-abzu (new-room
                    :name "E-Abzu, Temple of Enki"
                    :description
                    "Within the E-Abzu, the air is cool and heavy with incense. The walls are whitewashed, the floor swept clean, and at the heart of the sanctuary a pool of sweet water glimmers — the Abzu in miniature, the deep from which the world was made. The gudug priest tends the sacred fire."))
           (abzu (new-room
                  :name "The Abzu"
                  :description
                  "You stand at the edge of the Abzu itself — the freshwater ocean beneath the earth, the source of all rivers and the dwelling of Enki. A still, luminous water stretches into darkness, and the air thrums with ancient power. The Lord of the Deep regards you from the far shore."))
           (genesis (new-room
                     :name "Genesis Shrine"
                     :description
                     "A small shrine at the heart of the deep. Two clay tablets rest on a stone shelf: the Eridu Genesis, telling how the first city was founded and how the flood swept the world, and the ark tablet, describing the great round boat in which the seed of life was saved when Enki warned the faithful. Scholars of every age have marveled at these words."))
           ;; — The ziggurat —───────────────────────────────────────────
           (ziggurat (new-room
                      :name "Ziggurat of E-engurra"
                      :description
                      "The ziggurat of E-engurra, the House of the Lord of the Deep, rises in stepped tiers of mudbrick above the temple. A stair climbs its southern face toward the summit, where offerings are made to the sky. An ugallu, a lion-headed demon, paces at the foot of the stair."))
           (summit (new-room
                    :name "Summit Shrine"
                    :description
                    "At the top of the ziggurat the wind sweeps in from the gulf. A small shrine holds an offering table and a brazier of coals. From here the whole marsh spreads below — reed beds, canals, the pale walls of the city, and the endless green of the sea."))
           ;; — Folk of Eridu —──────────────────────────────────────────
           (fisherman (new-npc
                       :name "a reed-fisherman of the marsh"
                       :description "A lean man in a reed kilt, coiling a net strung with shell hooks. 'The marsh feeds us,' he says, 'and the deep gives us fish enough for all the world.'"
                       :hp 10 :max-hp 10
                       :attack-min 2 :attack-max 4
                       :defeat-message "The fisherman splashes into the shallows, crying out that the marsh will remember this!"))
           (boatwright (new-npc
                        :name "the coracle-builder of Eridu"
                        :description "A broad-shouldered boatwright, lashing reeds into a round coracle and sealing it with bitumen. 'Round as the moon,' he grins, 'the shape the god Himself commanded when the waters rose. It saved the seed of every living thing.'"
                        :hp 14 :max-hp 14
                        :attack-min 3 :attack-max 6
                        :defeat-message "The boatwright stumbles back among his reeds. 'Even the god's boat must yield to a stronger hand!'"))
           (reed-binder (new-npc
                         :name "a reed-binder of the quarter"
                         :description "A patient woman plaiting marsh reeds into a mat, her fingers stained green. 'Mud, reed, and water,' she murmurs, 'that is all the city is, and all it needs.'"
                         :hp 10 :max-hp 10
                         :attack-min 2 :attack-max 4
                         :defeat-message "The reed-binder retreats among her mats, shaking her head at such foolishness."))
           (gatekeeper (new-npc
                        :name "a temple gatekeeper"
                        :description "A shaven-headed priest with a bronze staff, his robe bleached white. 'The sacred precinct is not for the careless,' he warns. 'Know the name of the first city before you enter.'"
                        :hp 12 :max-hp 12
                        :attack-min 2 :attack-max 5
                        :defeat-message "The gatekeeper bows his head. 'The gate admits you — may the deep forgive what you are.'"))
           (gudug (new-npc
                   :name "a gudug priest of Enki"
                   :description "The gudug priest of the E-Abzu, robed in white with a shawl of red wool, tends the sacred pool with a bronze ladle. 'The deep accepts only the worthy,' he says."
                   :hp 18 :max-hp 18
                   :attack-min 3 :attack-max 7
                   :defeat-message "The gudug priest steps back, his ladle fallen. 'The temple will not bar you. Go, and be careful what you wake.'"))
           (goat-fish (new-npc
                       :name "the suhur-mashu, goat-fish of the deep"
                       :description "A creature of the deep: the foreparts of a goat, the tail of a fish, scales gleaming with sweet water. It is the guardian of Enki's sanctuary, older than the city, older than the marsh."
                       :hp 25 :max-hp 25
                       :attack-min 5 :attack-max 9
                       :defeat-message "The goat-fish sinks beneath the surface of the pool, and the waters part, opening the way to the Abzu."
                       :victory-flag "beat-suhur-mashu"))
           (ugallu (new-npc
                    :name "an ugallu, lion-demon of the ziggurat"
                    :description "A lion-headed demon, tall as a man, with the body of a man and the claws of a lion, its mane bristling with storm. It guards the stair of the ziggurat against the unworthy."
                    :hp 28 :max-hp 28
                    :attack-min 6 :attack-max 10
                    :defeat-message "The ugallu roars and dissolves into mist, and the stair to the summit stands open."
                    :victory-flag "beat-ugallu"))
           (adapa (new-npc
                   :name "Adapa, first of the Seven Sages"
                   :description "The first of the seven sages, a man of great age with eyes like the deep. He once broke the wing of the South Wind, and was offered the bread of life — and set it down at Enki's bidding. 'Wisdom,' he says, 'is the only immortality.'"
                   :hp 30 :max-hp 30
                   :attack-min 5 :attack-max 9
                   :defeat-message "'You have strength,' Adapa says, and his voice is gentle. 'It pleases me. Go now, and carry wisdom with you.'"
                   :victory-flag "adapa-wisdom"))
           (alulim (new-npc
                    :name "Alulim, first king of Eridu"
                    :description "The first king of the first city, robed in wool and shell, crowned with a circlet of lapis. He has ruled Eridu since kingship descended from heaven, and he does not surrender his treasure lightly."
                    :hp 35 :max-hp 35
                    :attack-min 7 :attack-max 11
                    :defeat-message "Alulim lowers his mace. 'No king can hold back the tide forever. Take what the treasury holds — and remember that all kingship began here, in Eridu.'"
                    :victory-flag "beat-alulim"))
           (enki (new-npc
                  :name "Enki, Lord of the Abzu"
                  :description "The Lord of the Abzu, god of sweet waters and wisdom, stands before you — a figure of light and deep shadow, wearing the horned crown of divinity, the goat-fish coiled at his feet. His voice is the sound of rivers. 'You have come far, mortal. Let us see what the deep has taught you.'"
                  :hp 45 :max-hp 45
                  :attack-min 8 :attack-max 13
                  :defeat-message "'The deep accepts you,' Enki says, and his voice is warm as a spring dawn. 'You have walked the way of wisdom and proven your worth. Go, and carry the blessing of Eridu with you.'"
                  :victory-flag "blessed-by-enki"))
           ;; — Treasures and tablets —──────────────────────────────────
           (guestbook (new-guestbook :name "the travellers tablet of Eridu"))
           (coracle (new-object :name "a round coracle"))
           (reeds (new-object :name "a bundle of marsh reeds"))
           (king-list (new-object :name "a clay tablet of the Sumerian King List"))
           (seal (new-object :name "a lapis lazuli seal of Enki"))
           (offering (new-object :name "an offering bowl of dates"))
           (ark-tablet (new-object :name "the ark tablet"))
           (genesis-tablet (new-object :name "the Eridu Genesis tablet")))
      ;; — Streets and gates —────────────────────────────────────────────
      (area-connect-north-south! area city-gate marsh)
      (area-connect-north-south! area street city-gate)
      (area-connect-north-south! area market street)
      (area-connect-west-east! area reed-quarter street)
      (area-connect-west-east! area street palace)
      (area-connect-north-south! area treasury palace)
      ;; — The living city —──────────────────────────────────────────────
      (area-connect-west-east! area market grove)
      (area-connect-west-east! area harbor market)
      ;; — The sacred precinct —──────────────────────────────────────────
      (area-connect-north-south! area temple-gate market)
      (area-connect-north-south! area temple-court temple-gate)
      (area-connect-west-east! area giparu temple-court)
      (area-connect-north-south! area sages giparu)
      (area-connect-north-south! area e-abzu temple-court)
      (area-connect-north-south! area abzu e-abzu)
      (area-connect-north-south! area genesis abzu)
      ;; — The ziggurat —─────────────────────────────────────────────────
      (area-connect-west-east! area temple-court ziggurat)
      (area-connect-rooms! area ziggurat summit
                           :to '("up" "u" "climb")
                           :from '("down" "d" "descend"))
      ;; — Riddles —──────────────────────────────────────────────────────
      ;; Enter the sacred precinct: name the first city.
      (connection-set-challenge (connection-find market "north")
                                "A priest steps forward: 'Speak the name of the first city of the world, where kingship descended from heaven, and enter the sacred precinct.' Try: answer <name>"
                                "eridu"
                                "solved-eridu-riddle")
      ;; Enter the E-Abzu: name the lord of the deep.
      (connection-set-challenge (connection-find temple-court "north")
                                "The gate of the temple asks: 'Who is the Lord of the sweet waters, whose temple is the E-Abzu and whose home is the deep?' Try: answer <name>"
                                "enki"
                                "solved-enki-riddle")
      ;; — Fight gates —──────────────────────────────────────────────────
      ;; The goat-fish guards the way into the Abzu.
      (set-flag-gate e-abzu "north" "beat-suhur-mashu"
                     "The goat-fish guardian blocks the way to the Abzu. Defeat it first! Try: attack goat")
      ;; Alulim guards his treasury.
      (set-flag-gate palace "north" "beat-alulim"
                     "The first king blocks the treasury door. Try: attack alulim")
      ;; The ugallu bars the stair to the summit.
      (set-flag-gate ziggurat "up" "beat-ugallu"
                     "The lion-demon bars the stair to the summit. Try: attack ugallu")
      (set-flag-gate ziggurat "u" "beat-ugallu"
                     "The lion-demon bars the stair to the summit. Try: attack ugallu")
      (set-flag-gate ziggurat "climb" "beat-ugallu"
                     "The lion-demon bars the stair to the summit. Try: attack ugallu")
      ;; Enki's blessing opens the Genesis Shrine.
      (set-flag-gate abzu "north" "blessed-by-enki"
                     "The deep will not part until the Lord of the Abzu acknowledges your worth. Try: attack enki")
      ;; — Folk and treasures —───────────────────────────────────────────
      (container-add-object harbor fisherman)
      (container-add-object harbor boatwright)
      (container-add-object harbor coracle)
      (container-add-object reed-quarter reed-binder)
      (container-add-object reed-quarter reeds)
      (container-add-object temple-gate gatekeeper)
      (container-add-object temple-gate king-list)
      (container-add-object temple-court offering)
      (container-add-object e-abzu gudug)
      (container-add-object e-abzu goat-fish)
      (container-add-object e-abzu seal)
      (container-add-object sages adapa)
      (container-add-object palace alulim)
      (container-add-object ziggurat ugallu)
      (container-add-object abzu enki)
      (container-add-object genesis ark-tablet)
      (container-add-object genesis genesis-tablet)
      (container-add-object market guestbook)
      (area-set-entrance! area marsh)
      area)))
