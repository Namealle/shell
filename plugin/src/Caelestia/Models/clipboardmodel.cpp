#include "clipboardmodel.hpp"

#include <QProcess>
#include <QTextStream>
#include <QDebug>

namespace caelestia::models {

// --- ClipboardSourceModel ---

ClipboardSourceModel::ClipboardSourceModel(QObject* parent) : QAbstractListModel(parent) {
    loadData();
}

void ClipboardSourceModel::loadData() {
    beginResetModel();
    m_entries.clear();

    QProcess process;
    process.start("cliphist", QStringList() << "-preview-width" << "999" << "list");
    if (!process.waitForFinished(1000)) {
        qWarning() << "ClipboardSourceModel: Failed to execute cliphist";
        endResetModel();
        return;
    }

    QString output = QString::fromUtf8(process.readAllStandardOutput());
    QTextStream in(&output);

    while (!in.atEnd()) {
        QString line = in.readLine().trimmed();
        if (line.isEmpty()) continue;

        int firstTab = line.indexOf('\t');
        if (firstTab == -1) continue;

        ClipboardEntry entry;
        entry.clipId = line.left(firstTab);
        entry.content = line.mid(firstTab + 1).trimmed();
        
        m_entries.append(entry);
    }
    
    endResetModel();
}

int ClipboardSourceModel::rowCount(const QModelIndex& parent) const {
    if (parent.isValid()) return 0;
    return m_entries.size();
}

QVariant ClipboardSourceModel::data(const QModelIndex& index, int role) const {
    if (!index.isValid() || index.row() >= m_entries.size()) {
        return QVariant();
    }

    const auto& entry = m_entries.at(index.row());
    if (role == ClipIdRole) {
        return entry.clipId;
    } else if (role == ContentRole) {
        return entry.content;
    }
    return QVariant();
}

QHash<int, QByteArray> ClipboardSourceModel::roleNames() const {
    QHash<int, QByteArray> roles;
    roles[ClipIdRole] = "clipId";
    roles[ContentRole] = "content";
    return roles;
}

// --- ClipboardModel (Proxy) ---

ClipboardModel::ClipboardModel(QObject* parent) : QSortFilterProxyModel(parent) {
    m_sourceModel = new ClipboardSourceModel(this);
    setSourceModel(m_sourceModel);
    setDynamicSortFilter(true);
    setFilterCaseSensitivity(Qt::CaseInsensitive);
}

QString ClipboardModel::query() const {
    return m_query;
}

void ClipboardModel::setQuery(const QString& query) {
    if (m_query == query) return;

    m_query = query;
    emit queryChanged();
    
    setFilterFixedString(m_query);
}

void ClipboardModel::reload() {
    m_sourceModel->loadData();
}

bool ClipboardModel::filterAcceptsRow(int source_row, const QModelIndex& source_parent) const {
    if (m_query.isEmpty()) return true;

    QModelIndex index = m_sourceModel->index(source_row, 0, source_parent);
    QString content = m_sourceModel->data(index, ClipboardSourceModel::ContentRole).toString();
    
    return content.contains(m_query, Qt::CaseInsensitive);
}

} // namespace caelestia::models
