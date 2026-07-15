#include "search.hpp"

#include "searchcore.hpp"

namespace caelestia {

QStringList Search::substring(const QStringList& items, const QString& query) {
    return search::substring(items, query);
}

QStringList Search::fuzzy(const QStringList& items, const QString& query, int limit) {
    return search::fuzzy(items, query, limit);
}

} // namespace caelestia
