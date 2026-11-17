package ca.sunny9781.courtside

/** Category name helpers (from the Apple apps' CategoryGrouping). */
object Categories {
    fun split(raw: String): Pair<String?, String> {
        val name = raw.trim { it == '|' || it == ':' || it.isWhitespace() }
        for (sep in listOf("|", ":")) {
            val i = name.indexOf(sep)
            if (i >= 0) {
                val head = name.substring(0, i).trim()
                val tail = name.substring(i + 1).trim()
                if (head.isNotEmpty() && head.length <= 24) {
                    return head to (if (tail.isEmpty()) name else tail.trim { it == '|' || it == ':' || it == ' ' })
                }
            }
        }
        return null to name
    }

    private fun words(text: String) = text.lowercase().split(Regex("[^\\p{L}\\p{N}]+")).filter { it.isNotEmpty() }

    fun isAllDay(name: String): Boolean {
        val lower = name.lowercase()
        return lower.contains("24/7") || lower.contains("24-7") || lower.contains("24x7") || "247" in words(name)
    }

    fun isUHD(name: String): Boolean {
        val w = words(name).toSet()
        return w.any { it in setOf("4k", "uhd", "2160p", "2160") } || name.contains("ᵁᴴᴰ") || name.contains("⁴ᴷ")
    }

    private val english = setOf("us", "usa", "uk", "gb", "ca", "can", "canada", "au", "aus", "nz", "ie", "en", "eng", "english")

    private val codes = mapOf(
        "br" to "Brazil", "mx" to "Mexico", "es" to "Spain", "pt" to "Portugal", "fr" to "France", "de" to "Germany",
        "it" to "Italy", "nl" to "Netherlands", "be" to "Belgium", "pl" to "Poland", "tr" to "Turkey", "ar" to "Arabic",
        "arb" to "Arabic", "in" to "India", "pk" to "Pakistan", "ph" to "Philippines", "al" to "Albania", "gr" to "Greece",
        "ro" to "Romania", "ru" to "Russia", "ua" to "Ukraine", "se" to "Sweden", "no" to "Norway", "dk" to "Denmark",
        "fi" to "Finland", "lat" to "Latino", "latam" to "Latino", "cr" to "Costa Rica", "co" to "Colombia", "cl" to "Chile",
        "pe" to "Peru", "ve" to "Venezuela", "ec" to "Ecuador", "do" to "Dominican Republic", "hu" to "Hungary",
        "cz" to "Czechia", "sk" to "Slovakia", "bg" to "Bulgaria", "rs" to "Serbia", "hr" to "Croatia", "ba" to "Bosnia",
        "mk" to "Macedonia", "si" to "Slovenia", "ch" to "Switzerland", "at" to "Austria", "il" to "Israel", "ir" to "Iran",
        "af" to "Afghanistan", "jp" to "Japan", "kr" to "Korea", "cn" to "China", "vn" to "Vietnam", "th" to "Thailand",
        "my" to "Malaysia", "id" to "Indonesia", "so" to "Somalia", "et" to "Ethiopia", "ht" to "Haiti", "ku" to "Kurdish",
        "exyu" to "Ex-Yu", "ex-yu" to "Ex-Yu", "afr" to "Africa", "pr" to "Puerto Rico", "cu" to "Cuba", "ni" to "Nicaragua",
        "hn" to "Honduras", "gt" to "Guatemala", "sv" to "El Salvador", "pa" to "Panama", "uy" to "Uruguay",
        "py" to "Paraguay", "bo" to "Bolivia"
    )

    private val countries = listOf(
        "brazil", "brasil", "costa rica", "mexico", "spain", "espana", "portugal", "france", "germany", "deutschland",
        "italy", "italia", "netherlands", "holland", "belgium", "poland", "turkey", "turkiye", "arabic", "arab",
        "india", "indian", "hindi", "punjabi", "tamil", "telugu", "urdu", "pakistan", "bangla", "bangladesh",
        "philippines", "filipino", "albania", "greece", "greek", "romania", "russia", "russian", "ukraine",
        "sweden", "norway", "denmark", "finland", "nordic", "scandinavia", "latino", "latin", "latam", "spanish",
        "portuguese", "french", "german", "italian", "argentina", "colombia", "chile", "peru", "venezuela",
        "ecuador", "dominican", "honduras", "guatemala", "el salvador", "panama", "uruguay", "paraguay", "bolivia",
        "hungary", "czech", "slovakia", "bulgaria", "serbia", "croatia", "bosnia", "macedonia", "slovenia",
        "balkan", "ex-yu", "exyu", "switzerland", "austria", "israel", "iran", "persian", "farsi", "afghan",
        "kurdish", "japan", "korea", "china", "chinese", "vietnam", "thai", "thailand", "malaysia", "indonesia",
        "somali", "ethiopia", "haiti", "africa", "nigeria", "ghana", "kenya", "armenia", "georgia", "azerbaijan",
        "lithuania", "latvia", "estonia", "malta", "cyprus", "quebec", "francais", "puerto rico", "cuba",
        "nicaragua", "mexican", "brazilian", "caribe"
    )

    private fun display(c: String): String = mapOf(
        "brasil" to "Brazil", "espana" to "Spain", "deutschland" to "Germany", "italia" to "Italy",
        "holland" to "Netherlands", "turkiye" to "Turkey", "arab" to "Arabic", "latin" to "Latino",
        "latam" to "Latino", "exyu" to "Ex-Yu", "ex-yu" to "Ex-Yu", "francais" to "French"
    )[c] ?: c.split(" ").joinToString(" ") { w -> w.replaceFirstChar { it.uppercase() } }

    /** The country or language of a foreign category ("BR |", "Brazil |", "Latino …"). */
    fun foreignCountry(name: String): String? {
        val (prefix, _) = split(name)
        val probe = (prefix ?: name).lowercase().trim()
        if (prefix != null) {
            val p = prefix.lowercase()
            if (p in english) return null
            codes[p]?.let { return it }
            countries.firstOrNull { p == it || p.startsWith("$it ") }?.let { return display(it) }
            return null
        }
        countries.firstOrNull { probe.startsWith("$it ") || probe == it }?.let { return display(it) }
        return null
    }
}

/** Ties games to channels: the channel name has both teams, the guide shows the game, or it's an official broadcaster. */
object Matcher {
    class Indexed(val channel: Channel) {
        val tokens: List<String> = tokens(channel.name)
        val tokenSet: Set<String> = tokens.toSet()
    }

    class Alias(val tokens: List<String>, val notFollowedBy: List<String> = emptyList())

    class GameKey(
        val game: Game, val away: List<List<String>>, val home: List<List<String>>,
        val awayLocation: List<String>, val homeLocation: List<String>, val leagueWords: Set<String>,
        val eventAliases: List<List<String>>, val conflicts: Set<String>, val triggers: Set<String>,
        val from: Long, val to: Long
    )

    fun tokens(text: String): List<String> =
        text.lowercase().map { if (it.isLetterOrDigit()) it else ' ' }.joinToString("").split(' ').filter { it.isNotEmpty() }

    fun has(hay: List<String>, needle: List<String>, notFollowedBy: List<String> = emptyList()): Boolean {
        if (needle.isEmpty() || hay.size < needle.size) return false
        for (i in 0..(hay.size - needle.size)) {
            if (hay[i] != needle[0]) continue
            if (hay.subList(i, i + needle.size) == needle) {
                val next = i + needle.size
                if (next < hay.size && hay[next] in notFollowedBy) continue
                return true
            }
        }
        return false
    }

    fun has(hay: List<String>, alias: Alias) = has(hay, alias.tokens, alias.notFollowedBy)

    fun linkKey(epg: String, start: Long) = "$epg|${start / 1000}"

    private val extras: Map<String, List<List<String>>> = mapOf(
        "76ers" to listOf(listOf("sixers")),
        "trail blazers" to listOf(listOf("blazers")),
        "timberwolves" to listOf(listOf("wolves")),
        "cavaliers" to listOf(listOf("cavs")),
        "mavericks" to listOf(listOf("mavs")),
        "maple leafs" to listOf(listOf("leafs")),
        "golden knights" to listOf(listOf("knights"), listOf("vegas")),
        "blue jackets" to listOf(listOf("jackets")),
        "manchester united" to listOf(listOf("man", "utd"), listOf("man", "united")),
        "manchester city" to listOf(listOf("man", "city")),
        "tottenham hotspur" to listOf(listOf("tottenham"), listOf("spurs")),
        "wolverhampton wanderers" to listOf(listOf("wolves")),
        "nottingham forest" to listOf(listOf("forest"), listOf("nottm", "forest")),
        "paris saint germain" to listOf(listOf("psg")),
        "inter miami cf" to listOf(listOf("inter", "miami")),
        "bayern munich" to listOf(listOf("bayern")),
        "real madrid" to listOf(listOf("madrid"))
    )

    private val proLeagueWords: Map<Sport, Set<String>> = mapOf(
        Sport.BASKETBALL to setOf("nba", "wnba", "ncaab"),
        Sport.FOOTBALL to setOf("nfl", "ncaaf", "cfl"),
        Sport.HOCKEY to setOf("nhl"),
        Sport.BASEBALL to setOf("mlb"),
        Sport.SOCCER to setOf("epl", "mls", "ucl"),
        Sport.FIGHTING to setOf("ufc", "mma", "boxing"),
        Sport.TENNIS to setOf("atp", "wta"),
        Sport.MOTORSPORT to setOf("f1", "nascar", "indycar", "motogp"),
        Sport.GOLF to setOf("pga", "lpga"),
        Sport.RUGBY to setOf("rugby"),
        Sport.AUSSIE_RULES to setOf("afl"),
        Sport.LACROSSE to setOf("nll", "pll", "lacrosse")
    )

    private val filler = setOf("the", "of", "presented", "by", "at", "in", "2025", "2026", "2027", "fia")

    fun eventAliases(game: Game): List<List<String>> {
        val t = tokens(game.eventTitle).filter { it !in filler }
        val out = mutableListOf<List<String>>()
        fun add(a: List<String>) { if (a.size >= 2 && a !in out) out += a }
        add(t)
        if (t.size > 2) add(t.drop(1))
        val u = t.indexOf("ufc")
        if (u >= 0 && u + 1 < t.size) {
            if (t[u + 1].all { it.isDigit() }) add(listOf("ufc", t[u + 1]))
            if (t[u + 1] == "fight") add(listOf("ufc", "fight", "night"))
        }
        val g = t.indexOf("grand")
        if (g > 0 && g + 1 < t.size && t[g + 1] == "prix") {
            add(t.subList(0, g) + "gp")
            add(t.subList(g - 1, g + 2))
        }
        return out
    }

    fun aliases(team: Team): List<List<String>> {
        val out = mutableListOf<List<String>>()
        for (name in listOf(team.nickname, team.shortName, team.name)) {
            val t = tokens(name)
            if (t.isNotEmpty() && t !in out) out += t
            out += extras[t.joinToString(" ")] ?: emptyList()
        }
        return out
    }

    fun key(game: Game, now: Long): GameKey {
        val away = aliases(game.away)
        val home = aliases(game.home)
        val awayLoc = tokens(game.away.location)
        val homeLoc = tokens(game.home.location)
        val conflicts = proLeagueWords.filterKeys { it != game.league.sport }.values.flatten().toSet()
        val events = if (game.isEvent) eventAliases(game) else emptyList()
        val triggers = HashSet<String>()
        for (a in away + home + events) a.firstOrNull()?.let(triggers::add)
        awayLoc.firstOrNull()?.let(triggers::add)
        homeLoc.firstOrNull()?.let(triggers::add)
        val from: Long
        val to: Long
        when (game.league.sport) {
            Sport.TENNIS, Sport.GOLF -> { from = now - 3 * 3600_000L; to = now + 12 * 3600_000L }
            else -> {
                val start = game.start ?: now
                val length = when (game.league.sport) {
                    Sport.BASEBALL, Sport.FOOTBALL -> 4 * 3600_000L
                    Sport.FIGHTING -> 6 * 3600_000L
                    Sport.MOTORSPORT -> 3 * 3600_000L
                    else -> 12_600_000L   // 3.5 hours
                }
                from = start - 20 * 60_000L
                to = start + length
            }
        }
        return GameKey(game, away, home, awayLoc, homeLoc, game.league.keywords, events, conflicts, triggers, from, to)
    }

    fun matches(hay: List<String>, set: Set<String>, key: GameKey): Boolean {
        if (set.any { it in key.conflicts }) return false
        if (key.eventAliases.any { has(hay, it) }) return true
        if (key.away.any { has(hay, it) } && key.home.any { has(hay, it) }) return true
        if (set.any { it in key.leagueWords } && key.awayLocation.isNotEmpty() && key.homeLocation.isNotEmpty() &&
            has(hay, key.awayLocation) && has(hay, key.homeLocation)) return true
        return false
    }

    fun broadcasterAliases(name: String): List<Alias> {
        val t = tokens(name).toMutableList()
        if (name.endsWith("+")) t += "plus"
        when (t.joinToString(" ")) {
            "espn" -> return listOf(Alias(listOf("espn"), listOf("2", "3", "u", "news", "deportes", "plus")))
            "espn2" -> return listOf(Alias(listOf("espn2")), Alias(listOf("espn", "2")))
            "espn plus" -> return listOf(Alias(listOf("espn", "plus")), Alias(listOf("espn+")))
            "abc" -> return listOf(Alias(listOf("abc"), listOf("news")))
            "nbc" -> return listOf(Alias(listOf("nbc"), listOf("sports", "news", "golf")))
            "cbs" -> return listOf(Alias(listOf("cbs"), listOf("news", "sports", "sn")))
            "cbssn", "cbs sports network" -> return listOf(Alias(listOf("cbs", "sports", "network")), Alias(listOf("cbssn")), Alias(listOf("cbs", "sn")))
            "fox" -> return listOf(Alias(listOf("fox"), listOf("news", "business", "sports", "life", "soccer", "deportes")))
            "fs1" -> return listOf(Alias(listOf("fs1")), Alias(listOf("fox", "sports", "1")))
            "fs2" -> return listOf(Alias(listOf("fs2")), Alias(listOf("fox", "sports", "2")))
            "nba tv" -> return listOf(Alias(listOf("nba", "tv")), Alias(listOf("nbatv")))
            "nfl net", "nfl network" -> return listOf(Alias(listOf("nfl", "network")), Alias(listOf("nfln")))
            "nhl net", "nhl network" -> return listOf(Alias(listOf("nhl", "network")))
            "mlb net", "mlb network" -> return listOf(Alias(listOf("mlb", "network")))
            "usa net", "usa network" -> return listOf(Alias(listOf("usa", "network")))
            "prime video", "amazon prime video", "amazon prime" -> return listOf(Alias(listOf("prime", "video")), Alias(listOf("amazon", "prime")))
            "sn", "sportsnet" -> return listOf(Alias(listOf("sportsnet")), Alias(listOf("sn")), Alias(listOf("sn1")), Alias(listOf("sn360")))
            "tsn" -> return listOf("tsn", "tsn1", "tsn2", "tsn3", "tsn4", "tsn5").map { Alias(listOf(it)) }
            "tnt" -> return listOf(Alias(listOf("tnt")))
            "sportsnet one" -> return listOf(Alias(listOf("sportsnet", "one")), Alias(listOf("sportsnet", "1")), Alias(listOf("sn1")), Alias(listOf("sn", "one")))
            "sportsnet 360" -> return listOf(Alias(listOf("sportsnet", "360")), Alias(listOf("sn360")), Alias(listOf("sn", "360")))
            "sportsnet east", "sportsnet ontario", "sportsnet pacific", "sportsnet west" -> return listOf(Alias(t), Alias(listOf("sn", t[1])))
            "sportsnet plus" -> return listOf(Alias(listOf("sportsnet", "plus")))
            "tva sports" -> return listOf(Alias(listOf("tva", "sports"), listOf("2")), Alias(listOf("tvas")))
            "tva sports 2" -> return listOf(Alias(listOf("tva", "sports", "2")), Alias(listOf("tvas2")))
            "rds" -> return listOf(Alias(listOf("rds"), listOf("2", "info")))
            "cbc" -> return listOf(Alias(listOf("cbc"), listOf("news")))
            "ctv" -> return listOf(Alias(listOf("ctv"), listOf("news", "2", "drama", "comedy", "sci", "life", "nature", "speed", "wild")))
            "sky sports" -> return listOf(Alias(listOf("sky", "sports"), listOf("news", "golf", "f1", "cricket", "racing", "tennis", "arena", "mix")))
        }
        if (t.size == 1 && t[0].length > 1 && t[0].last().isDigit() && t[0].dropLast(1).all { it.isLetter() }) {
            return listOf(Alias(t), Alias(listOf(t[0].dropLast(1), t[0].last().toString())))
        }
        if (t.firstOrNull() == "nbcs" && t.size >= 2) {
            val cities = mapOf("bos" to listOf("boston"), "phi" to listOf("philadelphia"), "ca" to listOf("california"), "ba" to listOf("bay", "area"))
            val rest = t.drop(1)
            val city = cities[rest.joinToString(" ")] ?: rest
            return listOf(Alias(listOf("nbc", "sports") + city), Alias(listOf("nbcs") + city), Alias(t))
        }
        if (t.size >= 3 && t[0] == "fanduel" && t[1] == "sn") {
            val rest = t.drop(2)
            return listOf(Alias(listOf("fanduel", "sports") + rest), Alias(listOf("fanduel", "sn") + rest),
                Alias(listOf("fdsn") + rest), Alias(listOf("bally", "sports") + rest))
        }
        return if (t.isEmpty()) emptyList() else listOf(Alias(t))
    }

    private val countryPrefixes = mapOf(
        "uk" to "UK", "gb" to "UK", "england" to "UK", "ca" to "Canada", "can" to "Canada", "canada" to "Canada",
        "us" to "USA", "usa" to "USA", "es" to "Spain", "spain" to "Spain", "it" to "Italy", "italy" to "Italy",
        "de" to "Germany", "germany" to "Germany", "fr" to "France", "france" to "France",
        "car" to "Caribbean", "au" to "Australia", "aus" to "Australia", "australia" to "Australia", "nz" to "New Zealand",
        "ie" to "Ireland", "ireland" to "Ireland", "mx" to "Mexico", "mexico" to "Mexico"
    )

    private val standaloneCodes = mapOf(
        "uk" to "UK", "gb" to "UK", "us" to "USA", "usa" to "USA", "ca" to "Canada", "can" to "Canada", "au" to "Australia",
        "nz" to "New Zealand", "ie" to "Ireland", "de" to "Germany", "fr" to "France", "es" to "Spain", "it" to "Italy",
        "mx" to "Mexico", "br" to "Brazil", "car" to "Caribbean", "pt" to "Portugal", "nl" to "Netherlands"
    )

    private val serviceCountries = mapOf(
        "kayo" to "Australia", "foxtel" to "Australia", "stan" to "Australia", "optus" to "Australia",
        "fubo" to "Canada", "crave" to "Canada"
    )

    private val networkHomes: List<Pair<List<String>, String>> = listOf(
        listOf("espn") to "USA", listOf("espn2") to "USA", listOf("espnu") to "USA", listOf("abc") to "USA", listOf("nbc") to "USA",
        listOf("cbs") to "USA", listOf("fox") to "USA", listOf("fs1") to "USA", listOf("fs2") to "USA", listOf("tnt") to "USA",
        listOf("trutv") to "USA", listOf("tbs") to "USA", listOf("nhl", "network") to "USA", listOf("nba", "tv") to "USA",
        listOf("nfl", "network") to "USA", listOf("mlb", "network") to "USA", listOf("peacock") to "USA", listOf("paramount") to "USA",
        listOf("usa", "network") to "USA", listOf("cbssn") to "USA", listOf("acc", "network") to "USA", listOf("sec", "network") to "USA",
        listOf("big", "ten") to "USA", listOf("msg") to "USA", listOf("nesn") to "USA",
        listOf("tsn") to "Canada", listOf("tsn1") to "Canada", listOf("tsn2") to "Canada", listOf("tsn3") to "Canada",
        listOf("tsn4") to "Canada", listOf("tsn5") to "Canada", listOf("sportsnet") to "Canada", listOf("rds") to "Canada",
        listOf("tva", "sports") to "Canada", listOf("cbc") to "Canada", listOf("ctv") to "Canada",
        listOf("sky", "sports") to "UK", listOf("tnt", "sports") to "UK", listOf("bbc") to "UK", listOf("itv") to "UK",
        listOf("premier", "sports") to "UK"
    )

    fun country(channel: Channel): String? {
        val texts = listOf(channel.name, channel.categoryName)
        for (text in texts) {
            Categories.split(text).first?.lowercase()?.let { p -> countryPrefixes[p]?.let { return it } }
            Categories.foreignCountry(text)?.let { return it }
            if (text.startsWith("(")) {
                val close = text.indexOf(')')
                if (close > 0) {
                    val code = text.substring(1, close).trim().lowercase()
                    (countryPrefixes[code] ?: standaloneCodes[code])?.let { return it }
                }
            }
        }
        for (text in texts) {
            for (w in text.split(Regex("[^\\p{L}\\p{N}]+"))) {
                if (w.length in 2..3 && w == w.uppercase() && w.all { it.isLetter() }) standaloneCodes[w.lowercase()]?.let { return it }
            }
        }
        for (text in texts) {
            val t = tokens(text).toSet()
            serviceCountries.entries.firstOrNull { it.key in t }?.let { return it.value }
        }
        val nameTokens = tokens(channel.name)
        return networkHomes.firstOrNull { has(nameTokens, it.first) }?.second
    }

    private fun aboutOtherSport(c: Indexed, key: GameKey): Boolean =
        c.tokenSet.any { it in key.conflicts } || tokens(c.channel.categoryName).any { it in key.conflicts }

    private fun isOtherEvent(c: Indexed): Boolean = c.channel.name.contains("@") || "vs" in c.tokenSet || "v" in c.tokenSet

    private fun neverLive(channel: Channel): Boolean {
        val cat = channel.categoryName.lowercase()
        return cat.contains("radio") || Categories.isAllDay(channel.categoryName) || channel.name.lowercase().startsWith("radio")
    }

    private fun isCallSign(name: String) =
        name.length == 4 && (name.startsWith("K") || name.startsWith("W")) && name.all { it.isUpperCase() && it.isLetter() }

    private fun guideAllows(channel: Channel, key: GameKey, guide: Map<String, List<Programme>>): Boolean {
        val progs = (guide[channel.epgId] ?: emptyList()).filter { it.start < key.to && it.end > key.from }
        if (progs.isEmpty()) return true
        val sporty = setOf("live", "football", "soccer", "hockey", "basketball", "baseball", "match", "game",
            "nfl", "nhl", "nba", "mlb", "mls", "premier", "liga", "serie", "bundesliga", "ligue")
        val words = sporty + key.leagueWords + key.triggers
        return progs.any { p -> tokens(p.title).any { it in words } }
    }

    private val states = setOf(
        "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "DC", "FL", "GA", "HI", "ID", "IL", "IN", "IA", "KS", "KY",
        "LA", "ME", "MD", "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ", "NM", "NY", "NC", "ND", "OH",
        "OK", "OR", "PA", "RI", "SC", "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI", "WY"
    )
    private val networks = setOf("abc", "nbc", "cbs", "fox", "cw", "pbs", "mynetwork", "telemundo", "univision", "ctv", "global", "citytv")

    private fun isLocal(channel: Channel): Boolean {
        if (channel.categoryName.lowercase().contains("local")) return true
        val words = channel.name.split(Regex("[^\\p{L}\\p{N}]+")).filter { it.isNotEmpty() }
        if (words.any { isCallSign(it) }) return true
        val first = words.firstOrNull()
        if (first != null && first.length == 2 && first in states) return words.drop(1).any { it.lowercase() in networks }
        return false
    }

    fun quality(set: Set<String>): Pair<String, Int> = when {
        set.any { it in setOf("4k", "uhd", "2160p", "2160", "ᵁᴴᴰ", "ᵘʰᵈ", "⁴ᴷ", "⁴ᵏ") } -> "4K" to 4
        set.any { it in setOf("fhd", "1080p", "1080", "ᶠᴴᴰ", "ᶠʰᵈ") } -> "1080p" to 3
        set.any { it in setOf("hd", "720p", "720") } -> "HD" to 2
        set.any { it in setOf("sd", "480p") } -> "SD" to 1
        else -> "" to 2
    }

    private fun rankOf(label: String) = when (label) { "4K" -> 4; "1080p" -> 3; "720p" -> 2; else -> 1 }

    /** Every game's streams at once, best match first. */
    fun matchAll(
        games: List<Game>, channels: List<Indexed>, guide: Map<String, List<Programme>>,
        measured: Map<Int, String>, recent: Set<Int>, now: Long
    ): Map<String, List<StreamMatch>> {
        val keys = games.map { key(it, now) }
        val triggers = keys.flatMap { it.triggers }.toSet()
        val live = channels.filter { !neverLive(it.channel) }

        // 1. Guide titles
        val guideHits = HashMap<String, MutableSet<String>>()
        for ((epg, progs) in guide) {
            for (p in progs) {
                val hay = tokens(p.title)
                val set = hay.toSet()
                if (set.none { it in triggers }) continue
                keys.firstOrNull { p.start < it.to && p.end > it.from && matches(hay, set, it) }?.let {
                    guideHits.getOrPut(it.game.id) { HashSet() }.add(epg)
                }
            }
        }
        // 2. Channel names
        val nameHits = HashMap<String, MutableSet<Int>>()
        for (c in live) {
            if (c.tokenSet.none { it in triggers }) continue
            for (k in keys) if (matches(c.tokens, c.tokenSet, k)) nameHits.getOrPut(k.game.id) { HashSet() }.add(c.channel.id)
        }
        // 3. Broadcasters
        val broadcasterHits = HashMap<String, Set<Int>>()
        for (name in games.flatMap { it.broadcasters }.toSet()) {
            broadcasterHits[name] = if (isCallSign(name)) {
                live.filter { c -> c.channel.name.split(Regex("[^\\p{L}\\p{N}]+")).contains(name) }.map { it.channel.id }.toSet()
            } else {
                val aliases = broadcasterAliases(name)
                live.filter { c -> aliases.any { has(c.tokens, it) } }.map { it.channel.id }.toSet()
            }
        }
        val countryCache = HashMap<Int, String?>()
        fun countryOf(c: Channel) = countryCache.getOrPut(c.id) { country(c) }
        val byId = live.associateBy { it.channel.id }
        val byEpg = HashMap<String, MutableList<Int>>()
        for (c in live) if (c.channel.epgId.isNotEmpty()) byEpg.getOrPut(c.channel.epgId) { mutableListOf() }.add(c.channel.id)

        val result = HashMap<String, List<StreamMatch>>()
        for (k in keys) {
            val id = k.game.id
            val named = nameHits[id] ?: emptySet<Int>()
            val inGuide = (guideHits[id] ?: emptySet<String>()).flatMap { byEpg[it] ?: emptyList() }.toSet()
            val broadcast = HashMap<Int, String>()
            for (b in k.game.broadcasters) {
                for (cid in broadcasterHits[b] ?: emptySet()) {
                    if (cid in broadcast) continue
                    val ic = byId[cid] ?: continue
                    if (cid !in named && cid !in inGuide && (aboutOtherSport(ic, k) || isOtherEvent(ic))) continue
                    broadcast[cid] = b
                }
            }
            val list = mutableListOf<StreamMatch>()
            for (cid in named + inGuide + broadcast.keys) {
                val c = byId[cid] ?: continue
                val reasons = mutableListOf<String>()
                var score = 0
                if (cid in named) { reasons += "Channel name has the teams"; score += 3 }
                if (cid in inGuide) { reasons += "In the guide"; score += 3 }
                broadcast[cid]?.let { reasons += "Broadcaster: $it"; score += 2 }
                var q = quality(c.tokenSet)
                if (q.second < 4 && Categories.isUHD(c.channel.categoryName)) q = "4K" to 4
                measured[cid]?.let { q = it to rankOf(it) }
                // 4K channels mostly carry only chosen events, so the network alone isn't enough.
                if (q.second == 4 && cid !in named && cid !in inGuide) {
                    if (!guideAllows(c.channel, k, guide)) continue
                    reasons.clear(); reasons += "4K version of ${broadcast[cid] ?: ""}, not confirmed for this game"
                    score = 1
                }
                list += StreamMatch(c.channel, reasons.joinToString(" · "), score, q.first, q.second, cid in recent,
                    isLocal(c.channel), score == 1, countryOf(c.channel))
            }
            result[id] = list.sortedWith(Comparator { a, b ->
                when {
                    a.hidden != b.hidden -> if (!a.hidden) -1 else 1
                    a.is4K != b.is4K -> if (a.is4K) -1 else 1
                    a.score != b.score -> b.score - a.score
                    a.recent != b.recent -> if (a.recent) -1 else 1
                    a.qualityRank != b.qualityRank -> b.qualityRank - a.qualityRank
                    else -> a.channel.name.compareTo(b.channel.name)
                }
            })
        }
        return result
    }

    private fun rank(label: String) = when (label) { "4K" -> 4; "1080p" -> 3; "720p", "HD" -> 2; else -> 1 }

    /**
     * Sports with no schedule feed (pickleball): events built from what the guide says is on now or in the next six
     * hours (anything on a channel named for the sport, or titled with its words anywhere), with the channels showing
     * them as the streams. The sport's own channels follow as entries of their own, after the events.
     */
    fun guideEvents(league: League, channels: List<Indexed>, guide: Map<String, List<Programme>>,
                    measured: Map<Int, String>, now: Long): Pair<List<Game>, Map<String, List<StreamMatch>>> {
        data class Found(val title: String, val start: Long, val end: Long, val channels: MutableList<Indexed>)
        val words = league.keywords + league.name.lowercase()
        val sportName = league.name.lowercase()
        val own = channels.filter { it.channel.name.lowercase().contains(sportName) }
        val ownIds = own.map { it.channel.id }.toSet()
        val found = LinkedHashMap<String, Found>()
        // The sport's own channels get one card each (below); their schedules aren't split into cards.
        for (c in channels) {
            if (c.channel.epgId.isEmpty() || c.channel.id in ownIds) continue
            for (p in guide[c.channel.epgId] ?: continue) {
                if (p.end <= now || p.start >= now + 6 * 3600_000L) continue
                val lower = p.title.lowercase()
                if (tokens(p.title).none { it in words } && !lower.contains(sportName)) continue
                val key = lower.filter { it.isLetterOrDigit() } + "-" + (p.start / 900_000L)
                found.getOrPut(key) { Found(p.title, p.start, p.end, mutableListOf()) }.channels.add(c)
            }
        }
        fun streamFor(c: Indexed, reason: String): StreamMatch {
            val q = measured[c.channel.id]?.let { it to rank(it) } ?: quality(c.tokenSet)
            return StreamMatch(c.channel, reason, 3, q.first, q.second, false, false, false, country(c.channel))
        }
        val games = mutableListOf<Game>()
        val matches = HashMap<String, List<StreamMatch>>()
        for ((key, f) in found) {
            val live = f.start <= now
            val id = "guide-${league.id}-$key"
            games.add(Game(id, league, f.start, if (live) GameState.LIVE else GameState.UPCOMING,
                if (live) "Live" else clockTime(f.start), Team.none, Team.none, emptyList(), isEvent = true,
                eventTitle = f.title,
                eventDetail = if (f.channels.size == 1) "On ${f.channels[0].channel.name}" else "On ${f.channels.size} channels"))
            matches[id] = f.channels.map { streamFor(it, "In the guide") }.sortedByDescending { it.qualityRank }
        }
        games.sortBy { it.start ?: Long.MAX_VALUE }
        for (c in own.sortedBy { it.channel.name }) {
            val id = "guide-${league.id}-ch-${c.channel.id}"
            val current = guide[c.channel.epgId]?.firstOrNull { it.start <= now && it.end > now }
            games.add(Game(id, league, null, GameState.UPCOMING, "Channel", Team.none, Team.none, emptyList(),
                isEvent = true, eventTitle = c.channel.name, eventDetail = current?.let { "Now: ${it.title}" } ?: "",
                isChannel = true))
            matches[id] = listOf(streamFor(c, "${league.name} channel"))
        }
        return games to matches
    }
}
