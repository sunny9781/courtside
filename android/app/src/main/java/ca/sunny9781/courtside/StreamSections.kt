package ca.sunny9781.courtside

/**
 * How a game screen lists its streams (the same as the Apple apps): 4K · PPV (fight cards) · the league's own
 * channels · the league's home-country broadcasters · other English-language countries · Other. Foreign-language
 * streams and local stations come back separately, for groups at the bottom that fold open. Within each section
 * the highest quality comes first (2.14: resolution, measured when it's been played, else from the name; then frame
 * rate), and the matcher's order among equals.
 */
object StreamSections {
    data class Section(val name: String, val streams: List<StreamMatch>)
    data class Result(val sections: List<Section>, val foreign: List<Section>, val extras: List<StreamMatch>) {
        val foreignCount: Int get() = foreign.sumOf { it.streams.size }
    }

    fun homeCountries(league: League): List<String> = when (league.id) {
        "nhl", "nll" -> listOf("Canada", "USA")
        "cfl" -> listOf("Canada")
        "epl", "ucl", "sixnations", "premrugby", "f1" -> listOf("UK")
        "urc" -> listOf("UK", "Ireland")
        "laliga" -> listOf("Spain")
        "seriea" -> listOf("Italy")
        "bundesliga" -> listOf("Germany")
        "ligue1", "top14" -> listOf("France")
        "afl" -> listOf("Australia")
        "atp", "wta", "cricket", "pickleball", "boxing" -> emptyList()
        else -> listOf("USA")
    }

    private val english = listOf("USA", "Canada", "UK", "Ireland", "Australia", "New Zealand", "Caribbean")

    private val languageWords = mapOf(
        "french" to "French", "francais" to "French", "français" to "French", "quebec" to "French", "québec" to "French",
        "rds" to "French", "tva" to "French", "latino" to "Latino", "latin" to "Latino", "spanish" to "Spanish",
        "espanol" to "Spanish", "español" to "Spanish", "deportes" to "Spanish", "portuguese" to "Portuguese",
        "arabic" to "Arabic", "hindi" to "Hindi", "punjabi" to "Punjabi", "italian" to "Italian", "german" to "German"
    )

    private fun country(m: StreamMatch): String? =
        m.country ?: Categories.foreignCountry(m.channel.categoryName) ?: Categories.foreignCountry(m.channel.name)

    private fun language(m: StreamMatch): String? {
        for (text in listOf(m.channel.categoryName, m.channel.name)) {
            val words = text.lowercase().split(Regex("[^\\p{L}\\p{N}]+"))
            words.firstNotNullOfOrNull { languageWords[it] }?.let { return it }
        }
        return null
    }

    private fun isForeign(m: StreamMatch, home: List<String>): Boolean {
        if (language(m) != null) return true
        val c = country(m) ?: return false
        return c !in english && c !in home
    }

    private fun foreignGroup(m: StreamMatch): String {
        val lang = language(m)
        if (lang != null && (m.country == null || m.country in english)) return lang
        return country(m) ?: lang ?: "Other"
    }

    private fun isLeagueChannel(m: StreamMatch, league: League): Boolean {
        val cat = m.channel.categoryName.lowercase()
        val words = cat.split(Regex("[^\\p{L}\\p{N}]+")).toSet()
        if (league.name.lowercase() in words || cat.contains(league.name.lowercase())) return true
        return league.keywords.any { it.length in 3..4 && it in words }
    }

    /** 4 = 4K, 3 = 1080p, 2 = 720p / HD (and unknown), 1 = SD. */
    fun qualityRank(m: StreamMatch, measured: Map<Int, String>): Int = when (measured[m.channel.id]) {
        "4K" -> 4
        "1080p" -> 3
        "720p", "HD" -> 2
        "SD", "576p", "480p" -> 1
        else -> m.qualityRank
    }

    /** Highest quality first, keeping the given order among streams of the same quality (sortedWith is stable). */
    fun byQuality(list: List<StreamMatch>, measured: Map<Int, String>, fps: Map<Int, Float>): List<StreamMatch> =
        list.sortedWith(compareByDescending<StreamMatch> { qualityRank(it, measured) }
            .thenByDescending { Math.round(fps[it.channel.id] ?: 0f) })

    fun build(all: List<StreamMatch>, league: League, search: String = "",
              measured: Map<Int, String> = emptyMap(), fps: Map<Int, Float> = emptyMap()): Result {
        // Event sports (motorsport, golf, tennis, fights): a 4K channel the guide doesn't confirm is still listed up top
        // under 4K (4K channels carry these events, and the guide often names the race only as "F2 Feature Race").
        fun shown(m: StreamMatch) = !m.hidden || (league.isEvent && m.is4K)
        val main = all.filter(::shown)
        val base = main.ifEmpty { all }
        val extras = if (main.isEmpty()) emptyList() else all.filter { !shown(it) }
        val home = homeCountries(league)
        val q = search.trim().lowercase()
        fun matchesSearch(m: StreamMatch) = q.isEmpty() || m.channel.name.lowercase().contains(q) || m.channel.categoryName.lowercase().contains(q)

        val found = base.filter(::matchesSearch)
        val list = found.filter { !isForeign(it, home) }
        val foreignList = found.filter { isForeign(it, home) }

        val used = HashSet<Int>()
        val sections = mutableListOf<Section>()
        fun take(name: String, pick: (StreamMatch) -> Boolean) {
            val picked = list.filter { it.channel.id !in used && pick(it) }
            if (picked.isEmpty()) return
            picked.forEach { used += it.channel.id }
            sections += Section(name, byQuality(picked, measured, fps))
        }
        take("4K") { it.is4K }
        if (league.sport == Sport.FIGHTING) take("PPV") { it.isPPV }
        take("${league.name} channels") { isLeagueChannel(it, league) }
        for (c in home) take(c) { country(it) == c }
        for (c in english) if (c !in home) take(c) { country(it) == c }
        take("Other") { true }

        val byGroup = foreignList.groupBy(::foreignGroup)
        val foreign = byGroup.keys.sortedWith(compareByDescending<String> { byGroup[it]!!.size }.thenBy { it })
            .map { Section(it, byQuality(byGroup[it]!!, measured, fps)) }
        return Result(sections, foreign, byQuality(extras.filter(::matchesSearch), measured, fps))
    }
}
