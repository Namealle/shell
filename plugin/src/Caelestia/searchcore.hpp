#pragma once

#include <qlist.h>
#include <qstringlist.h>

// Pure, QObject-free matchers so they can be unit-tested with a plain g++
// compile (no moc). The QML-facing `Search` singleton (search.hpp) forwards
// to these.
namespace caelestia::search {

// Case-insensitive substring filter. Preserves input order.
// Empty query returns `items` unchanged.
QStringList substring(const QStringList& items, const QString& query);

// Fuzzy subsequence match with scoring, best match first, capped at `limit`.
// An item matches only if every character of `query` appears in it in order
// (case-insensitive). Empty query returns the first `limit` items.
QStringList fuzzy(const QStringList& items, const QString& query, int limit = 200);

// Same ranking as fuzzy(), but returns the indices into `items` instead of the
// strings — lets a caller map results back to parallel objects (e.g. the
// clipboard entry QObjects) while preserving rank order.
QList<int> fuzzyIndices(const QStringList& items, const QString& query, int limit = 200);

} // namespace caelestia::search
