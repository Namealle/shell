#pragma once

#include <qobject.h>
#include <qqmlintegration.h>
#include <qstringlist.h>

namespace caelestia {

// QML singleton `Search` (import Caelestia). Thin wrapper over the pure
// matchers in searchcore.hpp so the launcher can filter big lists (12k emoji)
// natively instead of in per-keystroke JavaScript.
class Search : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    // Case-insensitive substring filter, input order preserved (clipboard).
    Q_INVOKABLE static QStringList substring(const QStringList& items, const QString& query);
    // Fuzzy subsequence match, best-first, capped at `limit` (emoji).
    Q_INVOKABLE static QStringList fuzzy(const QStringList& items, const QString& query, int limit = 200);
    // Fuzzy ranking as indices into `items` — for mapping results back to
    // parallel QML objects (clipboard entries) while keeping rank order.
    Q_INVOKABLE static QList<int> fuzzyIndices(const QStringList& items, const QString& query, int limit = 200);
};

} // namespace caelestia
