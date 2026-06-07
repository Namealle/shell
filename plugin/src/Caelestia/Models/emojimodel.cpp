#include "emojimodel.hpp"

#include <QFile>
#include <QTextStream>
#include <QDebug>

namespace caelestia::models {

// --- EmojiSourceModel ---

EmojiSourceModel::EmojiSourceModel(QObject* parent) : QAbstractListModel(parent) {
    loadData();
}

void EmojiSourceModel::loadData() {
    QFile file("/usr/lib/python3.14/site-packages/caelestia/data/emojis.txt");
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        qWarning() << "EmojiSourceModel: Failed to open emojis.txt";
        return;
    }

    QTextStream in(&file);
    while (!in.atEnd()) {
        QString line = in.readLine().trimmed();
        if (line.isEmpty()) continue;

        int firstSpace = line.indexOf(' ');
        if (firstSpace == -1) continue;

        EmojiEntry entry;
        entry.character = line.left(firstSpace);
        entry.name = line.mid(firstSpace + 1).trimmed();
        
        m_allEmojis.append(entry);
    }
}

int EmojiSourceModel::rowCount(const QModelIndex& parent) const {
    if (parent.isValid()) return 0;
    return m_allEmojis.size();
}

QVariant EmojiSourceModel::data(const QModelIndex& index, int role) const {
    if (!index.isValid() || index.row() >= m_allEmojis.size()) {
        return QVariant();
    }

    const auto& entry = m_allEmojis.at(index.row());
    if (role == CharacterRole) {
        return entry.character;
    } else if (role == NameRole) {
        return entry.name;
    }
    return QVariant();
}

QHash<int, QByteArray> EmojiSourceModel::roleNames() const {
    QHash<int, QByteArray> roles;
    roles[CharacterRole] = "character";
    roles[NameRole] = "name";
    return roles;
}

// --- EmojiModel (Proxy) ---

EmojiModel::EmojiModel(QObject* parent) : QSortFilterProxyModel(parent) {
    m_sourceModel = new EmojiSourceModel(this);
    setSourceModel(m_sourceModel);
    setDynamicSortFilter(true);
    setFilterCaseSensitivity(Qt::CaseInsensitive);
}

QString EmojiModel::query() const {
    return m_query;
}

void EmojiModel::setQuery(const QString& query) {
    if (m_query == query) return;

    m_query = query;
    emit queryChanged();
    
    // Changing the filter automatically calculates diffs and animates in QML!
    setFilterFixedString(m_query);
}

bool EmojiModel::useFuzzy() const {
    return m_useFuzzy;
}

void EmojiModel::setUseFuzzy(bool useFuzzy) {
    if (m_useFuzzy == useFuzzy) return;

    m_useFuzzy = useFuzzy;
    emit useFuzzyChanged();
    invalidateFilter();
}


bool EmojiModel::filterAcceptsRow(int source_row, const QModelIndex& source_parent) const {
    if (m_query.isEmpty()) return true;

    QModelIndex index = m_sourceModel->index(source_row, 0, source_parent);
    QString name = m_sourceModel->data(index, EmojiSourceModel::NameRole).toString();
    
    if (!m_useFuzzy) {
        return name.contains(m_query, Qt::CaseInsensitive);
    }
    
    // Simple fuzzy match algorithm (all characters of query must exist in text in order)
    int qIndex = 0;
    int tIndex = 0;
    
    while (qIndex < m_query.length() && tIndex < name.length()) {
        if (m_query.at(qIndex).toLower() == name.at(tIndex).toLower()) {
            qIndex++;
        }
        tIndex++;
    }
    
    return qIndex == m_query.length();
}

} // namespace caelestia::models
