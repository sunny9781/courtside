package ca.sunny9781.courtside

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.ui.graphics.vector.ImageVector

data class Credentials(val server: String, val username: String, val password: String)

data class AccountInfo(
    val status: String,
    val expires: Long?,          // seconds since 1970
    val maxConnections: Int?,
    val activeConnections: Int?
)

data class ChannelCategory(val id: String, val name: String)

data class Channel(
    val id: Int,
    val number: Int?,
    val name: String,
    val categoryId: String,
    val categoryName: String,
    /** Lowercased XMLTV channel id, empty when the provider doesn't link one. */
    val epgId: String,
    val icon: String?
)

data class Programme(val title: String, val start: Long, val end: Long)   // milliseconds

enum class Sport(val title: String, val icon: ImageVector) {
    BASKETBALL("Basketball", Icons.Filled.SportsBasketball),
    FOOTBALL("Football", Icons.Filled.SportsFootball),
    HOCKEY("Hockey", Icons.Filled.SportsHockey),
    SOCCER("Soccer", Icons.Filled.SportsSoccer),
    BASEBALL("Baseball", Icons.Filled.SportsBaseball),
    FIGHTING("Fighting", Icons.Filled.SportsMma),
    TENNIS("Tennis", Icons.Filled.SportsTennis),
    MOTORSPORT("Motorsport", Icons.Filled.SportsMotorsports),
    GOLF("Golf", Icons.Filled.GolfCourse),
    RUGBY("Rugby", Icons.Filled.SportsRugby),
    AUSSIE_RULES("Aussie Rules", Icons.Filled.Sports),
    LACROSSE("Lacrosse", Icons.Filled.Sports),
    CRICKET("Cricket", Icons.Filled.SportsCricket),
    PICKLEBALL("Pickleball", Icons.Filled.SportsTennis);

    val leagues: List<League> get() = League.all.filter { it.sport == this }
}

data class League(
    val id: String,
    val name: String,
    val sport: Sport,
    /** Path in ESPN's public scoreboard feed. */
    val path: String,
    /** Words that identify this league in a channel name or guide title. */
    val keywords: Set<String>,
    /** Tournaments, races and fight cards rather than one team against another. */
    val isEvent: Boolean = false
) {
    companion object {
        val all = listOf(
            League("nba", "NBA", Sport.BASKETBALL, "basketball/nba", setOf("nba")),
            League("wnba", "WNBA", Sport.BASKETBALL, "basketball/wnba", setOf("wnba")),
            League("ncaam", "NCAA Men", Sport.BASKETBALL, "basketball/mens-college-basketball", setOf("ncaab", "ncaa", "college", "cbb")),
            League("ncaaw", "NCAA Women", Sport.BASKETBALL, "basketball/womens-college-basketball", setOf("ncaaw", "ncaa", "college", "wbb")),
            League("nfl", "NFL", Sport.FOOTBALL, "football/nfl", setOf("nfl")),
            League("ncaaf", "NCAA", Sport.FOOTBALL, "football/college-football", setOf("ncaaf", "ncaa", "college", "cfb")),
            League("cfl", "CFL", Sport.FOOTBALL, "football/cfl", setOf("cfl")),
            League("nhl", "NHL", Sport.HOCKEY, "hockey/nhl", setOf("nhl")),
            League("mlb", "MLB", Sport.BASEBALL, "baseball/mlb", setOf("mlb")),
            League("epl", "Premier League", Sport.SOCCER, "soccer/eng.1", setOf("epl", "premier")),
            League("ucl", "Champions League", Sport.SOCCER, "soccer/uefa.champions", setOf("ucl", "champions")),
            League("mls", "MLS", Sport.SOCCER, "soccer/usa.1", setOf("mls")),
            League("laliga", "La Liga", Sport.SOCCER, "soccer/esp.1", setOf("laliga", "liga")),
            League("seriea", "Serie A", Sport.SOCCER, "soccer/ita.1", setOf("serie")),
            League("bundesliga", "Bundesliga", Sport.SOCCER, "soccer/ger.1", setOf("bundesliga")),
            League("ligue1", "Ligue 1", Sport.SOCCER, "soccer/fra.1", setOf("ligue")),
            League("ufc", "UFC", Sport.FIGHTING, "mma/ufc", setOf("ufc"), isEvent = true),
            // No free boxing schedule: its events and channels come from the TV guide, like pickleball.
            League("boxing", "Boxing", Sport.FIGHTING, "", setOf("boxing"), isEvent = true),
            League("atp", "ATP", Sport.TENNIS, "tennis/atp", setOf("atp", "tennis"), isEvent = true),
            League("wta", "WTA", Sport.TENNIS, "tennis/wta", setOf("wta", "tennis"), isEvent = true),
            League("f1", "Formula 1", Sport.MOTORSPORT, "racing/f1", setOf("f1", "formula"), isEvent = true),
            League("nascar", "NASCAR", Sport.MOTORSPORT, "racing/nascar-premier", setOf("nascar"), isEvent = true),
            League("indycar", "IndyCar", Sport.MOTORSPORT, "racing/irl", setOf("indycar"), isEvent = true),
            League("pga", "PGA Tour", Sport.GOLF, "golf/pga", setOf("pga", "golf"), isEvent = true),
            League("lpga", "LPGA", Sport.GOLF, "golf/lpga", setOf("lpga", "golf"), isEvent = true),
            League("sixnations", "Six Nations", Sport.RUGBY, "rugby/180659", setOf("rugby", "nations")),
            League("premrugby", "Premiership", Sport.RUGBY, "rugby/267979", setOf("rugby", "premiership")),
            League("urc", "URC", Sport.RUGBY, "rugby/270557", setOf("rugby", "urc")),
            League("top14", "Top 14", Sport.RUGBY, "rugby/270559", setOf("rugby", "top")),
            League("afl", "AFL", Sport.AUSSIE_RULES, "australian-football/afl", setOf("afl")),
            League("nll", "NLL", Sport.LACROSSE, "lacrosse/nll", setOf("nll", "lacrosse")),
            League("pll", "PLL", Sport.LACROSSE, "lacrosse/pll", setOf("pll", "lacrosse")),
            League("cricket", "Cricket", Sport.CRICKET, "cricket", setOf("cricket", "ipl", "bbl", "t20", "psl")),
            League("pickleball", "Pickleball", Sport.PICKLEBALL, "", setOf("pickleball", "ppa"))
        )
    }
}

data class Team(
    val name: String,
    val nickname: String,
    val shortName: String,
    val location: String,
    val abbr: String,
    val score: String,
    val logo: String?,
    val record: String = "",
    val linescores: List<String> = emptyList()
) {
    /** Scores that don't fit beside a name (cricket) go on their own line. */
    val hasLongScore: Boolean get() = score.length > 4

    companion object {
        val none = Team("", "", "", "", "", "", null)
    }
}

enum class GameState { UPCOMING, LIVE, FINISHED }

data class Game(
    val id: String,
    val league: League,
    val start: Long?,            // milliseconds
    val state: GameState,
    val statusText: String,
    val away: Team,
    val home: Team,
    val broadcasters: List<String>,
    val isEvent: Boolean = false,
    val eventTitle: String = "",
    val eventDetail: String = "",
    val venue: String = "",
    /** A channel for a sport with no schedule (pickleball), listed after its events. */
    val isChannel: Boolean = false
) {
    val title: String get() = if (isEvent) eventTitle else "${away.nickname} at ${home.nickname}"
    val hasSides: Boolean get() = away.name.isNotEmpty() && home.name.isNotEmpty()
    val headerText: String get() = buildString {
        append(league.name)
        when (state) {
            GameState.LIVE -> append(" · LIVE · ").append(statusText)
            GameState.FINISHED -> append(" · ").append(statusText.ifEmpty { "Final" })
            GameState.UPCOMING -> append(" · ").append(statusText)
        }
    }
}

data class StreamMatch(
    val channel: Channel,
    val reason: String,
    val score: Int,
    val quality: String,
    val qualityRank: Int,
    val recent: Boolean,
    val local: Boolean,
    val likelyOnly: Boolean,
    val country: String?
) {
    val hidden: Boolean get() = local || likelyOnly

    val isPPV: Boolean
        get() {
            val text = (channel.name + " " + channel.categoryName).lowercase()
            return Regex("\\bppv\\b").containsMatchIn(text) || text.contains("pay per view") || text.contains("pay-per-view")
        }

    /** 4K only when the channel's own name says so ("4K", "UHD"). */
    val is4K: Boolean
        get() {
            val upper = channel.name.uppercase()
            val words = upper.split(Regex("[^\\p{L}\\p{N}]+")).toSet()
            return "4K" in words || "UHD" in words || upper.contains("4K")
        }
}

/** What the player shows. The lineup is what up/down flips through. */
data class NowPlaying(val channel: Channel, val gameTitle: String?, val lineup: List<Channel>)
