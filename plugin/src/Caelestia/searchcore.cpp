#include "searchcore.hpp"

#include <algorithm>
#include <climits>

namespace caelestia::search {

QStringList substring(const QStringList& items, const QString& query) {
    if (query.isEmpty())
        return items;

    QStringList out;
    for (const QString& item : items) {
        if (item.contains(query, Qt::CaseInsensitive))
            out << item;
    }
    return out;
}

namespace {

// Score one lowercased item against a lowercased query.
// Returns INT_MIN if `query` is not an in-order subsequence of `item`.
int scoreMatch(const QString& item, const QString& query) {
    int qi = 0;
    int score = 0;
    int lastMatch = -1;

    for (int ii = 0; ii < item.size() && qi < query.size(); ++ii) {
        if (item[ii] != query[qi])
            continue;

        if (lastMatch >= 0) {
            const int gap = ii - lastMatch - 1;
            if (gap == 0)
                score += 15; // contiguous run — the good stuff
            else
                score += 1 - gap; // penalise gaps
        } else {
            score += 1; // first matched char
        }

        // Word-boundary bonus (start, or after a separator)
        if (ii == 0 || item[ii - 1] == ' ' || item[ii - 1] == '-' || item[ii - 1] == '_')
            score += 10;

        lastMatch = ii;
        ++qi;
    }

    if (qi < query.size())
        return INT_MIN; // not all query chars consumed → no match

    score -= static_cast<int>(item.size() / 10); // mild preference for shorter items
    return score;
}

} // namespace

QList<int> fuzzyIndices(const QStringList& items, const QString& query, int limit) {
    if (limit < 0)
        limit = 0;

    QList<int> out;

    if (query.isEmpty()) {
        const int n = std::min<int>(limit, static_cast<int>(items.size()));
        out.reserve(n);
        for (int i = 0; i < n; ++i)
            out << i;
        return out;
    }

    const QString q = query.toLower();

    struct Scored {
        int score;
        int index;
    };
    QList<Scored> scored;
    scored.reserve(items.size());

    for (int i = 0; i < items.size(); ++i) {
        const int s = scoreMatch(items[i].toLower(), q);
        if (s != INT_MIN)
            scored.append({s, i});
    }

    std::stable_sort(scored.begin(), scored.end(), [&](const Scored& a, const Scored& b) {
        if (a.score != b.score)
            return a.score > b.score;
        return items[a.index].size() < items[b.index].size();
    });

    const int n = std::min<int>(limit, static_cast<int>(scored.size()));
    out.reserve(n);
    for (int k = 0; k < n; ++k)
        out << scored[k].index;
    return out;
}

QStringList fuzzy(const QStringList& items, const QString& query, int limit) {
    const QList<int> idx = fuzzyIndices(items, query, limit);
    QStringList out;
    out.reserve(idx.size());
    for (const int i : idx)
        out << items[i];
    return out;
}

} // namespace caelestia::search
