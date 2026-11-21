package ca.sunny9781.courtside

/**
 * Groups the provider's categories into a tree, worked out from the names every time they load (the same as the
 * Apple apps): 24/7 · Country (Canada, UK, USA…, and Foreign › Brazil, Mexico…) · Movies · Sports (4K, leagues,
 * countries, streaming services) · other shared prefixes · Other. A category can sit in more than one group.
 */
object CategoryGrouping {
    data class Node(val id: String, val name: String, val children: List<Node>, val categories: List<ChannelCategory>) {
        val isGroup: Boolean get() = children.isNotEmpty()
    }

    const val SPORTS = "Sports"
    const val COUNTRY = "Country"
    const val FOREIGN = "Foreign"
    const val OTHER = "Other"
    const val MOVIES = "Movies"
    const val ALL_DAY = "24/7"
    const val NODE = "__node:"
    const val SERVICES = "Streaming services"

    fun build(categories: List<ChannelCategory>): List<Node> {
        val final = HashMap<String, List<List<String>>>()
        val candidate = HashMap<String, List<String>>()
        val counts = HashMap<String, Int>()
        for (cat in categories) {
            val name = cat.name
            val prefix = Categories.split(name).first
            val foreign = Categories.foreignCountry(name)
            val paths = mutableListOf<List<String>>()
            if (Categories.isAllDay(name)) paths.add(listOf(ALL_DAY))
            if (foreign != null) paths.add(listOf(COUNTRY, FOREIGN, foreign))
            if (Categories.isUHD(name)) paths.add(listOf(SPORTS, "4K")) else if (isSports(name)) paths.add(sportsPath(name))
            if (isMovies(name)) paths.add(listOf(MOVIES))
            final[cat.id] = paths
            if (prefix != null && foreign == null && !Categories.isAllDay(name)) {
                val own = ownCountry(prefix)
                if (own != null) candidate[cat.id] = listOf(COUNTRY, own)
                else if (paths.isEmpty()) candidate[cat.id] = listOf(prefix)
            }
            candidate[cat.id]?.let { val k = it.joinToString("/"); counts[k] = (counts[k] ?: 0) + 1 }
        }
        val items = mutableListOf<Pair<ChannelCategory, List<String>>>()
        for (cat in categories) {
            val paths = (final[cat.id] ?: emptyList()).toMutableList()
            candidate[cat.id]?.let { if ((counts[it.joinToString("/")] ?: 0) > 1) paths.add(it) }
            if (paths.isEmpty()) paths.add(listOf(OTHER))
            for (path in paths) items.add(cat to path)
        }
        return sorted(makeNodes(items, emptyList()))
    }

    private fun sorted(nodes: List<Node>): List<Node> =
        nodes.map { it.copy(children = sorted(it.children)) }.sortedWith { a, b -> NaturalOrder.compare(a.name, b.name) }

    private data class Bucket(val key: String)

    private fun makeNodes(items: List<Pair<ChannelCategory, List<String>>>, parentPath: List<String>): List<Node> {
        val entries = mutableListOf<Any>()
        val buckets = LinkedHashMap<String, MutableList<Pair<ChannelCategory, List<String>>>>()
        for ((cat, path) in items) {
            val key = path.firstOrNull()
            if (key != null) {
                if (key !in buckets) { buckets[key] = mutableListOf(); entries.add(Bucket(key)) }
                buckets[key]!!.add(cat to path.drop(1))
            } else entries.add(cat)
        }
        return entries.map { e ->
            when (e) {
                is ChannelCategory -> leaf(e, parentPath.lastOrNull())
                else -> {
                    val key = (e as Bucket).key
                    val members = buckets[key]!!
                    if (members.size == 1) leaf(members[0].first, parentPath.lastOrNull())
                    else {
                        val unique = members.map { it.first }.distinctBy { it.id }
                        val path = parentPath + key
                        Node(NODE + path.joinToString("/"), key, makeNodes(members, path), unique)
                    }
                }
            }
        }
    }

    /** Full name, except the prefix is dropped when the group is already that prefix ("CA | Entertainment" under CA). */
    private fun leaf(cat: ChannelCategory, group: String?): Node {
        val (prefix, rest) = Categories.split(cat.name)
        val p = prefix?.lowercase()
        val sameCountry = group != null && prefix?.let { countryName(it) } == group
        val short = group != null && (p == group.lowercase() || sameCountry || (p?.contains("sport") == true))
        return Node(cat.id, if (short) rest else cat.name, emptyList(), listOf(cat))
    }

    fun find(id: String, nodes: List<Node>): Node? {
        for (n in nodes) {
            if (n.id == id) return n
            find(id, n.children)?.let { return it }
        }
        return null
    }

    private fun words(text: String) = text.lowercase().split(NonWord).filter { it.isNotEmpty() }

    private val movieWords = setOf("movie", "movies", "film", "films", "cinema", "cine", "kino", "peliculas", "filmes", "vod", "boxoffice")

    fun isMovies(name: String) = words(name).any { it in movieWords } || name.lowercase().contains("box office")

    private fun sportsPath(name: String): List<String> {
        league(name)?.let { return listOf(SPORTS, it) }
        val prefix = Categories.split(name).first
        if (prefix != null && !prefix.lowercase().contains("sport")) return listOf(SPORTS, prefix.uppercase())
        return listOf(SPORTS, SERVICES, serviceKey(name))
    }

    private val ownCountries = mapOf(
        "us" to "USA", "usa" to "USA", "uk" to "UK", "gb" to "UK", "england" to "UK", "ca" to "Canada", "can" to "Canada",
        "canada" to "Canada", "au" to "Australia", "aus" to "Australia", "australia" to "Australia", "nz" to "New Zealand",
        "ie" to "Ireland", "ireland" to "Ireland", "car" to "Caribbean", "carib" to "Caribbean", "caribbean" to "Caribbean"
    )

    fun ownCountry(prefix: String) = ownCountries[prefix.lowercase()]

    fun countryName(prefix: String) = ownCountry(prefix) ?: Categories.foreignCountry("$prefix | x")

    private val sportWords = setOf(
        "sport", "sports", "nba", "wnba", "nfl", "nhl", "mlb", "ncaa", "ncaaf", "ncaab", "mls", "epl", "soccer",
        "ppv", "ufc", "boxing", "wwe", "wrestling", "mma", "f1", "nascar", "indycar", "motogp", "golf", "tennis",
        "cricket", "rugby", "dazn", "espn", "tsn", "sportsnet", "bein", "redzone", "fanduel", "flosports", "uefa",
        "laliga", "bundesliga", "ligue", "olympics", "efl", "fifa", "ahl", "chl", "hockey", "basketball", "baseball"
    )
    private val sportPhrases = listOf("league pass", "sunday ticket", "center ice", "premier league", "sky sports",
        "tnt sports", "champions league", "serie a", "red zone", "mlb tv")

    fun isSports(name: String): Boolean {
        val lower = name.lowercase()
        return words(name).any { it in sportWords } || sportPhrases.any { lower.contains(it) }
    }

    private data class LeagueWords(val name: String, val words: Set<String>, val phrases: List<String>)

    private val leagues = listOf(
        LeagueWords("WNBA", setOf("wnba"), emptyList()),
        LeagueWords("NBA", setOf("nba"), emptyList()),
        LeagueWords("NFL", setOf("nfl", "redzone"), listOf("sunday ticket", "red zone")),
        LeagueWords("Hockey", setOf("nhl", "ahl", "chl", "ohl", "whl", "qmjhl", "khl", "hockey"), listOf("center ice")),
        LeagueWords("MLB", setOf("mlb"), listOf("mlb tv")),
        LeagueWords("NCAA", setOf("ncaa", "ncaaf", "ncaab", "college"), listOf("big ten", "sec network", "acc network", "pac-12", "pac 12")),
        LeagueWords("Soccer", setOf("soccer", "epl", "efl", "mls", "laliga", "bundesliga", "ligue", "uefa", "futbol", "fifa", "concacaf"),
            listOf("premier league", "champions league", "serie a")),
        LeagueWords("Fighting", setOf("ufc", "boxing", "ppv", "wwe", "wrestling", "mma"), emptyList()),
        LeagueWords("Motorsport", setOf("f1", "nascar", "indycar", "motogp", "formula"), emptyList()),
        LeagueWords("Golf", setOf("golf"), emptyList()),
        LeagueWords("Tennis", setOf("tennis"), emptyList()),
        LeagueWords("Cricket", setOf("cricket"), emptyList()),
        LeagueWords("Rugby", setOf("rugby"), emptyList())
    )

    fun league(name: String): String? {
        val w = words(name).toSet()
        val lower = name.lowercase()
        return leagues.firstOrNull { l -> w.any { it in l.words } || l.phrases.any { lower.contains(it) } }?.name
    }

    private val regionSuffixes = setOf("uk", "us", "usa", "ca", "de", "fr", "es", "it", "au", "nz", "ie", "mx", "br", "latam", "intl", "international")

    private val countSuffix = Regex("\\s*\\(\\d+\\)\\s*$")

    /** "DAZN UK (2)", "DAZN CA" and "DAZN" all give "DAZN"; "HBO Max US" gives "HBO Max". */
    fun serviceKey(name: String): String {
        val (prefix, rest0) = Categories.split(name)
        var rest = if (prefix?.lowercase()?.contains("sport") == true) rest0 else name
        rest = rest.replace(countSuffix, "")
        val pieces = rest.split(" ").filter { it.isNotEmpty() }.toMutableList()
        if (pieces.size > 1 && pieces.last().lowercase() in regionSuffixes) pieces.removeAt(pieces.size - 1)
        val key = pieces.joinToString(" ").trim()
        return key.ifEmpty { name }
    }
}

/**
 * One search box for the whole EPG: categories by name and channels by name or by what's on now, grouped by category.
 * "NFL" → every NFL category plus NFL channels elsewhere; "lions" → just the channels mentioning the Lions.
 */
object EpgSearch {
    data class Hit(val category: ChannelCategory, val path: String, val channels: List<Channel>, val directHits: Int) {
        val id: String get() = category.id
        fun startsOpen(totalHits: Int) = directHits > 0 || totalHits <= 4
    }

    fun run(raw: String, model: AppModel, grouped: Boolean, now: Long = System.currentTimeMillis()): List<Hit> {
        val q = raw.trim().lowercase()
        if (q.length < 2) return emptyList()
        val paths = if (grouped) pathMap(model.categoryTree) else emptyMap()
        val hits = mutableListOf<Hit>()
        for (cat in model.categories) {
            val channels = model.channelsByCategory[cat.id] ?: emptyList()
            val catMatch = cat.name.lowercase().contains(q)
            val direct = channels.filter { ch ->
                ch.lowerName.contains(q) || model.currentProgramme(ch, now)?.title?.lowercase()?.contains(q) == true
            }
            if (!catMatch && direct.isEmpty()) continue
            hits.add(Hit(cat, paths[cat.id] ?: "", if (catMatch) channels else direct, direct.size))
        }
        return hits.sortedWith { a, b ->
            when {
                (a.directHits > 0) != (b.directHits > 0) -> if (a.directHits > 0) -1 else 1
                a.directHits != b.directHits -> b.directHits - a.directHits
                else -> NaturalOrder.compare(a.category.name, b.category.name)
            }
        }
    }

    /** Category id → "Sports › NFL", from the first place it appears in the tree. */
    private fun pathMap(nodes: List<CategoryGrouping.Node>, parent: List<String> = emptyList()): Map<String, String> {
        val out = HashMap<String, String>()
        for (n in nodes) {
            if (n.isGroup) {
                for ((k, v) in pathMap(n.children, parent + n.name)) if (k !in out) out[k] = v
            } else {
                val cat = n.categories.firstOrNull() ?: continue
                if (cat.id !in out) out[cat.id] = parent.joinToString(" › ")
            }
        }
        return out
    }
}
